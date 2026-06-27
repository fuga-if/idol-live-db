// edits.ts — オープン編集エンドポイント。
//
//   POST /edits                                   マスタの create/update/delete を 1 リクエスト = 1 edit_batch で受ける
//   GET  /master/:recordType/:recordName/history  そのレコードの編集履歴
//
// 反映方式 = 即時オープン編集 (ログイン済み全ユーザーが直接編集 → 即 CloudKit 反映、承認待ちゼロ)。
// CloudKit Public DB が single source of truth。edit_history は監査 / revert 元。
//
// server logic 順序 (契約厳守):
//   (1) getAuthUser → 401
//   (2) users.is_banned → 403
//   (3) checkRateLimit(edit) → 429
//   (4) 各 op を validateMasterEdit(isAdmin) → 400
//   (5) update/delete 対象の recordName を cloudKitLookup で before 取得 (サーバ権威。client の before は信頼しない)
//       update は before に送信フィールドを重ねた「マージ後の全フィールド」に正規化する (部分送信でも
//       未送信フィールドは現状維持。クリアは null 明示送信のみ)。
//   (6) edit_batch INSERT (cloudkit_ok=0)
//   (7) create/update → buildForceUpdate, delete → buildSoftDelete で CloudKitOperation 構築し cloudKitModify
//   (8) 成功時のみ cloudkit_ok=1 + 各 op を edit_history INSERT (before=lookup値, after=マージ後の全フィールド)
//   (9) users.contribution_count++  ((8)(9) は finalizeEditBatch で原子化)
//   (10) { ok:true, batchId, results:[{recordType, recordName, op, ok, fields}] }
//        results[].fields は「反映後の確定レコード」(サーバが CloudKit に送った正規化済みフィールド。
//        modifiedAt 注入 / boolean→0,1 / create のサーバ採番 recordName を含む)。iOS はこれで楽観更新する。
//        delete は fields=null (ソフト削除。deletedAt/modifiedAt のみ注入)。
//   失敗時: CloudKit 失敗 → 502 (edit_batch は cloudkit_ok=0 のまま、edit_history は書かない)

import {
  buildForceUpdate,
  buildSoftDelete,
  cloudKitLookup,
  cloudKitModify,
  flattenCkFields,
  type CloudKitOperation,
} from "./cloudkit";
import { validateMasterEdit, type EditOp } from "./master_validators";
import {
  createEditBatch,
  finalizeEditBatch,
  getRecordHistory,
  type BatchOp,
  type EditHistoryEntry,
} from "./edit_history";
import {
  SETLIST_RECORD_TYPES,
  SHOW_SETLIST_TYPE,
  applyOpsToSnapshot,
  fetchShowSetlistSnapshot,
} from "./setlist_snapshot";
import { maskDisplayName } from "./feed";

// ---------------------------------------------------------------------------
// 依存注入: index.ts の makeResponders / checkIsAdmin / getAuthUser / upsertUser に依存するため
// ハンドラはこれらをまとめた deps を受け取る (index.ts のクロージャパターンに合わせる)。
// ---------------------------------------------------------------------------

// edits.ts は index.ts の具象 Env を直接知らないため、必要最小フィールドを EditsEnv とし、
// 注入される各ヘルパは具象 Env を保持できるよう env 型を generic <E extends EditsEnv> で貫通させる
// (具象 Env が APPLE_BUNDLE_ID 等の追加必須フィールドを持っていても型整合する)。
export interface EditsEnv {
  DB: D1Database;
  CLOUDKIT_KEY_ID: string;
  CLOUDKIT_PRIVATE_KEY: string;
}

export interface EditsDeps<E extends EditsEnv> {
  /** Bearer から認証ユーザーを得る (未認証 null)。 */
  getAuthUser: (request: Request, env: E) => Promise<{ uid: string; email?: string } | null>;
  /** users 行を保証する (FK 違反による履歴孤児を防ぐ)。 */
  upsertUser: (env: E, uid: string, name?: string, picture?: string) => Promise<void>;
  /** admin 判定 (構造マスタ編集・フィールド allowlist 免除)。 */
  checkIsAdmin: (env: E, uid: string) => Promise<boolean>;
  /** レート制限判定 (action='edit')。 */
  checkRateLimit: (
    db: D1Database,
    uid: string,
    action: string
  ) => Promise<{ allowed: boolean; used: number; limit: number; reset_at: string }>;
  json: (data: unknown, status?: number) => Response;
  error: (message: string, status?: number) => Response;
  rateLimitResponse: (used: number, limit: number, resetAt: string) => Response;
}

// ---------------------------------------------------------------------------
// 入力 DTO
// ---------------------------------------------------------------------------

interface EditOpInput {
  op: EditOp;
  recordType: string;
  recordName?: string;
  fields?: Record<string, unknown>;
}

// 新規作成時のサーバ採番 prefix (既存 apply.ts の song_/ev_ 規約を踏襲)。
// SetlistItem は位置非依存化 (sli_<uuid>。position はフィールド) — 契約 v2 #3。
const RECORD_NAME_PREFIX: Record<string, string> = {
  Song: "song",
  Event: "ev",
  Show: "sh",
  SetlistItem: "sli",
  SetlistPerformer: "slp",
  SongArtist: "sa",
  ShowCast: "sc",
  // コーレス / 参考動画 (確定契約 §4: SongCall=call_<uuid>, SongVideo=ytref_<uuid>)。
  SongCall: "call",
  SongVideo: "ytref",
};

const MAX_OPS = 1000;        // 1 batch あたりの op 上限 (既存 /admin/cloudkit/save 踏襲)
const MAX_BODY_BYTES = 2_000_000;
const MAX_FIELD_STR = 50_000;
const CK_CHUNK = 200;        // cloudKitModify の 1 リクエストあたり op 数

function generateRecordName(recordType: string): string | null {
  const prefix = RECORD_NAME_PREFIX[recordType];
  if (!prefix) return null;
  return `${prefix}_${crypto.randomUUID()}`;
}

/** 構築済み op から、注入された modifiedAt(ms) を読み出す (履歴の modified_at を CK 実値に揃える)。 */
function modifiedAtOf(op: CloudKitOperation): number {
  const v = op.record.fields.modifiedAt?.value;
  return typeof v === "number" ? v : Date.now();
}

/** results / 件数からサーバ側で要約を機械生成 (クライアント summary は信頼しない)。 */
function buildSummary(entries: EditHistoryEntry[], clientSummary?: string): string {
  const counts: Record<string, number> = {};
  for (const e of entries) {
    const key = `${e.recordType}.${e.op}`;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  const machine = Object.entries(counts)
    .map(([k, n]) => `${k} x${n}`)
    .join(", ");
  // クライアント summary は参考情報として末尾に付すが、監査の主体は機械生成側。
  const trimmed = clientSummary?.slice(0, 200);
  return trimmed ? `${machine} — ${trimmed}` : machine;
}

/**
 * update のマージセマンティクス (フィールド消失バグの根本対策):
 * 既存レコード (サーバ権威 before) に「送信されたフィールドだけ」を重ね、書き戻す全フィールドを構成する。
 *   - 送信されたフィールド   → その値で上書き (null は「明示クリア」と解釈)
 *   - 送信されないフィールド → before の現在値を維持
 * 旧実装は送信フィールドのみを edit_history.after / setlist スナップショット / results に流していたため、
 * クライアントのフォームに無いフィールド (lyricist/composer/releaseDate 等) が「消えた」状態で記録され、
 * revert・楽観更新経由で実データ消失を招いた (batch 16/55/56)。
 * modifiedAt は buildForceUpdate が常に再注入するため merge からは除外する。
 */
function mergeUpdateFields(
  before: Record<string, unknown>,
  sent: Record<string, unknown>
): Record<string, unknown> {
  const merged: Record<string, unknown> = { ...before };
  delete merged.modifiedAt;
  for (const [k, v] of Object.entries(sent)) {
    if (v === undefined) continue;
    merged[k] = v;
  }
  return merged;
}

/** ops 全体の batch.op を決定する (単一 op はその種別、混在/複数 update+delete は replace)。 */
function deriveBatchOp(ops: EditOpInput[]): BatchOp {
  if (ops.length === 1) return ops[0].op;
  const kinds = new Set(ops.map((o) => o.op));
  if (kinds.size === 1) return [...kinds][0] as BatchOp;
  return "replace";
}

/**
 * setlist op (SetlistItem | SetlistPerformer) が属する showId を解決する。
 *   - SetlistItem: 自身の recordName から itemIdToShowId を引く
 *   - SetlistPerformer: setlistItemId (fields or before) → itemIdToShowId を引く
 * いずれも itemIdToShowId が事前構築済み (batch 内 item + lookup 補完) であることを前提とする。
 */
function showIdOfSetlistOp(
  op: { recordType: string; recordName: string; fields: Record<string, unknown> },
  itemIdToShowId: Map<string, string>,
  beforeMap: Map<string, Record<string, unknown>>
): string | undefined {
  if (op.recordType === "SetlistItem") return itemIdToShowId.get(op.recordName);
  if (op.recordType === "SetlistPerformer") {
    const itemId =
      (typeof op.fields.setlistItemId === "string" && op.fields.setlistItemId) ||
      (beforeMap.get(op.recordName)?.setlistItemId as string | undefined);
    return itemId ? itemIdToShowId.get(itemId) : undefined;
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// POST /edits
// ---------------------------------------------------------------------------

export async function handlePostEdits<E extends EditsEnv>(
  request: Request,
  env: E,
  deps: EditsDeps<E>
): Promise<Response> {
  const { json, error, rateLimitResponse } = deps;

  // (1) auth
  const user = await deps.getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  // body パース + サイズ/件数ガード
  const rawBody = await request.text();
  if (rawBody.length > MAX_BODY_BYTES) return error("body too large (max 2MB)", 413);
  let body: { ops?: EditOpInput[]; summary?: string } | null;
  try {
    body = JSON.parse(rawBody) as { ops?: EditOpInput[]; summary?: string };
  } catch {
    return error("invalid json body");
  }
  const ops = body?.ops ?? [];
  if (!Array.isArray(ops) || ops.length === 0) return error("ops is required (non-empty array)");
  if (ops.length > MAX_OPS) return error(`too many ops (max ${MAX_OPS})`, 413);

  // (2)(3) ban + rate を並列確認
  const [dbUser, rl] = await Promise.all([
    env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
      .bind(user.uid)
      .first<{ is_banned: number }>(),
    deps.checkRateLimit(env.DB, user.uid, "edit"),
  ]);
  if (dbUser?.is_banned) return error("Banned", 403);
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const isAdmin = await deps.checkIsAdmin(env, user.uid);

  // マスタ事実 (Song/Idol/Event/Show/Setlist 等) の直接編集は管理者のみ。
  // 一般ユーザーは /edit-requests (GitHub issue 化 → 人手で取り込み) に回す。
  // コミュニティ投稿 (コーレス SongCall / 参考動画 SongVideo) は従来どおり全員オープン。
  if (!isAdmin) {
    const COMMUNITY_TYPES = new Set(["SongCall", "SongVideo"]);
    const masterOp = ops.find((o) => !COMMUNITY_TYPES.has(String(o?.recordType ?? "")));
    if (masterOp) {
      return error(
        "master edits are request-based; submit a correction request via /edit-requests",
        422
      );
    }
  }

  // (4) 各 op を検証 + 正規化。1 件でも不正なら 400 で全体中断 (CloudKit には一切書かない)。
  interface NormalizedOp {
    op: EditOp;
    recordType: string;
    recordName: string;       // create はここで採番済み
    fields: Record<string, unknown>;
    generated: boolean;       // サーバ採番した新規か
  }
  const normalized: NormalizedOp[] = [];
  for (const raw of ops) {
    if (!raw || typeof raw !== "object") return error("each op must be an object");
    const { op, recordType } = raw;
    const fields = raw.fields ?? {};

    // フィールド値サイズガード
    for (const [k, v] of Object.entries(fields)) {
      if (typeof v === "string" && v.length > MAX_FIELD_STR) {
        return error(`fields.${k} too long (max 50KB)`, 413);
      }
    }

    const validErr = validateMasterEdit({ recordType, op, recordName: raw.recordName, fields }, isAdmin);
    if (validErr) return error(validErr, 400);

    let recordName = raw.recordName;
    let generated = false;
    if (op === "create" && !recordName) {
      const gen = generateRecordName(recordType);
      if (!gen) return error(`cannot generate recordName for ${recordType}`, 400);
      recordName = gen;
      generated = true;
    }
    if (!recordName) return error("recordName is required for update/delete", 400);

    // SongCall/SongVideo の createdAt はサーバ権威で注入する (確定契約 §4: allowlist 外なので
    // ユーザーは送れない。validateMasterEdit 通過後に注入し CloudKit/履歴へ確定値として残す)。
    // 編集者匿名性 (§1) のため authorDisplayName は注入しない。
    if (op === "create" && (recordType === "SongCall" || recordType === "SongVideo")) {
      fields.createdAt = Date.now();
    }

    normalized.push({ op, recordType, recordName, fields, generated });
  }

  // (5) update/delete 対象の before をサーバ権威で取得 (client の before は信頼しない)。
  //     create はサーバ採番した新規 recordName なので lookup 不要 (before=null)。
  const lookupNames = normalized
    .filter((n) => (n.op === "update" || n.op === "delete") && !n.generated)
    .map((n) => n.recordName);
  const beforeMap = new Map<string, Record<string, unknown>>();
  if (lookupNames.length > 0) {
    const lookup = await cloudKitLookup(
      [...new Set(lookupNames)],
      env.CLOUDKIT_KEY_ID,
      env.CLOUDKIT_PRIVATE_KEY
    );
    if (!lookup.ok) return error(`cloudkit_lookup_error: ${lookup.error}`, 502);
    for (const [name, rec] of lookup.records ?? []) {
      beforeMap.set(name, flattenCkFields(rec.fields));
    }
  }

  // update を「全置換」ではなく「差分マージ」として解釈する (全 recordType 共通)。
  // 以降の処理 (CloudKit forceUpdate / edit_history.after / setlist スナップショット / results) は
  // すべてマージ後の「実際の全フィールド状態」を取り回す。before が無い update は create 相当なのでそのまま。
  for (const n of normalized) {
    if (n.op !== "update") continue;
    const before = beforeMap.get(n.recordName);
    if (before) n.fields = mergeUpdateFields(before, n.fields);
  }

  // setlist 編集判定: SetlistItem/SetlistPerformer op を含む batch は show 単位スナップショットを記録する
  // (RedTeam Critical #1 対策。位置依存 recordName 時代の壊れた個別 revert を回避し show 全体で置換可能にする)。
  const hasSetlistOps = normalized.some((n) => SETLIST_RECORD_TYPES.has(n.recordType));

  // SetlistPerformer の showId は performer 自身に無いため、紐づく SetlistItem (setlistItemId) 経由で解決する。
  // batch 内に対応 item が無い performer は、その setlistItemId を CloudKit lookup して showId を補完する。
  const itemIdToShowId = new Map<string, string>();
  if (hasSetlistOps) {
    // (a) batch 内 SetlistItem の showId を先に登録
    for (const n of normalized) {
      if (n.recordType !== "SetlistItem") continue;
      const sid =
        (typeof n.fields.showId === "string" && n.fields.showId) ||
        (beforeMap.get(n.recordName)?.showId as string | undefined);
      if (sid) itemIdToShowId.set(n.recordName, sid);
    }
    // (b) batch 外の SetlistItem を参照する performer の itemId を lookup
    const unresolvedItemIds = new Set<string>();
    for (const n of normalized) {
      if (n.recordType !== "SetlistPerformer") continue;
      const itemId =
        (typeof n.fields.setlistItemId === "string" && n.fields.setlistItemId) ||
        (beforeMap.get(n.recordName)?.setlistItemId as string | undefined);
      if (itemId && !itemIdToShowId.has(itemId)) unresolvedItemIds.add(itemId);
    }
    if (unresolvedItemIds.size > 0) {
      const itemLookup = await cloudKitLookup(
        [...unresolvedItemIds],
        env.CLOUDKIT_KEY_ID,
        env.CLOUDKIT_PRIVATE_KEY
      );
      if (!itemLookup.ok) return error(`cloudkit_lookup_error: ${itemLookup.error}`, 502);
      for (const [name, rec] of itemLookup.records ?? []) {
        const sid = flattenCkFields(rec.fields).showId;
        if (typeof sid === "string") itemIdToShowId.set(name, sid);
      }
    }
  }

  // CloudKit op を構築 (create/update → forceUpdate, delete → soft delete)。
  // 同時に edit_history エントリ (before=lookup値, after=マージ後の全フィールド, modifiedAt=注入値) を組む。
  const ckOps: CloudKitOperation[] = [];
  const entries: EditHistoryEntry[] = [];
  for (const n of normalized) {
    const before = n.op === "create" ? null : beforeMap.get(n.recordName) ?? null;
    // update/delete で CloudKit に対象が無い場合の扱い:
    //   - delete: 既に存在しない → no-op だが soft delete は冪等なのでそのまま送る (before=null)
    //   - update: 対象なし → 実質 create 相当。before=null で forceUpdate (CloudKit が upsert)
    if (n.op === "delete") {
      const ckOp = buildSoftDelete(n.recordType, n.recordName);
      ckOps.push(ckOp);
      entries.push({
        recordType: n.recordType,
        recordName: n.recordName,
        op: "delete",
        before,
        after: null,
        modifiedAt: modifiedAtOf(ckOp),
      });
    } else {
      const ckOp = buildForceUpdate(n.recordType, n.recordName, n.fields);
      ckOps.push(ckOp);
      entries.push({
        recordType: n.recordType,
        recordName: n.recordName,
        op: n.op, // 'create' | 'update'
        before,
        after: n.fields,
        modifiedAt: modifiedAtOf(ckOp),
      });
    }
  }

  // setlist 編集の場合、CloudKit 反映 *前* に show 単位 before スナップショットを権威取得する
  // (反映後だと現状が変わってしまうため、必ずここで取る)。after は反映成功後に op を重ねて再構成。
  //
  // 確定契約 §5: SetlistItem/SetlistPerformer の単独 op であっても必ず ShowSetlist スナップショット行を
  // 生成する不変条件を強制する。よって全 setlist op が showId に解決できることをここで保証し、
  // 1 件でも解決不能なら CloudKit へ書く前に 400 で中断する (snapshot 無しの setlist 編集を作らない
  // = revert が個別レコード起点に退行するのを根絶する)。
  const affectedShowIds = new Set<string>();
  if (hasSetlistOps) {
    for (const n of normalized) {
      if (!SETLIST_RECORD_TYPES.has(n.recordType)) continue;
      const sid = showIdOfSetlistOp(n, itemIdToShowId, beforeMap);
      if (!sid) {
        return error(
          `cannot resolve showId for ${n.recordType}/${n.recordName}; setlist edits must be attributable to a show`,
          400
        );
      }
      affectedShowIds.add(sid);
    }
  }
  const beforeSnapshots = new Map<string, Awaited<ReturnType<typeof fetchShowSetlistSnapshot>>>();
  for (const showId of affectedShowIds) {
    const snap = await fetchShowSetlistSnapshot(showId, env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
    if (!snap.ok) return error(`setlist_snapshot_error: ${snap.error}`, 502);
    beforeSnapshots.set(showId, snap);
  }

  // FK 孤児防止: edit_batch.editor_id が users(id) を NOT NULL 参照するため、
  // CloudKit 書き込み前に users 行を保証する (RedTeam High)。
  await deps.upsertUser(env, user.uid, user.email);

  // (6) edit_batch を cloudkit_ok=0 で先行 INSERT
  const batchOp = deriveBatchOp(normalized);
  const summary = buildSummary(entries, body?.summary);
  let batchId: number;
  try {
    batchId = await createEditBatch(env.DB, {
      editorId: user.uid,
      op: batchOp,
      source: "app",
      summary,
    });
  } catch (e: any) {
    return error(`failed to create edit batch: ${String(e?.message ?? e)}`, 500);
  }

  // (7) CloudKit へ反映 (200 件ずつ chunk)。1 chunk でも失敗したら 502。
  //     edit_batch は cloudkit_ok=0 のまま残り、edit_history は書かない (= 反映成功時のみ履歴記録)。
  for (let i = 0; i < ckOps.length; i += CK_CHUNK) {
    const chunk = ckOps.slice(i, i + CK_CHUNK);
    const res = await cloudKitModify(chunk, env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
    if (!res.ok) {
      console.error(`[edits] cloudkit failed batch=${batchId} at ${i}/${ckOps.length}: ${res.error}`);
      return error(`cloudkit_error: ${res.error}`, 502);
    }
  }

  // setlist 編集なら show 単位スナップショット行を edit_history に追加する
  // (record_type='ShowSetlist', record_name=showId, before=反映前の全セトリ, after=反映後の全セトリ)。
  // これが setlist の唯一の revert 元になる (個別 SetlistItem 行は監査の粒度表示用)。
  if (hasSetlistOps) {
    const setlistOps = normalized
      .filter((n) => SETLIST_RECORD_TYPES.has(n.recordType))
      .map((n) => ({ op: n.op, recordType: n.recordType, recordName: n.recordName, fields: n.fields }));
    const snapModifiedAt = Date.now();
    for (const [showId, snap] of beforeSnapshots) {
      if (!snap.ok) continue; // 上で 502 済みだが型ガード
      const opsForShow = setlistOps.filter((o) => showIdOfSetlistOp(o, itemIdToShowId, beforeMap) === showId);
      const afterSnap = applyOpsToSnapshot(snap.snapshot, opsForShow);
      entries.push({
        recordType: SHOW_SETLIST_TYPE,
        recordName: showId,
        op: "snapshot",
        before: { items: snap.snapshot.items, performers: snap.snapshot.performers },
        after: { items: afterSnap.items, performers: afterSnap.performers },
        modifiedAt: snapModifiedAt,
      });
    }
  }

  // results[] の確定レコードを組む (契約 #3: iOS の楽観更新がサーバ正規化値を使えるように)。
  // ckOps[i] は normalized[i] と 1:1 (同一ループ構築。setlist snapshot 行は後で entries にのみ追加)。
  // create/update は CloudKit へ送った正規化済み fields (modifiedAt 注入 / boolean→0,1 込み) を平坦化して返す。
  // delete はソフト削除 (deletedAt/modifiedAt のみ) なので fields=null とし、iOS はローカル削除で処理する。
  const results = normalized.map((n, i) => ({
    recordType: n.recordType,
    recordName: n.recordName,
    op: n.op,
    ok: true,
    fields: n.op === "delete" ? null : flattenCkFields(ckOps[i].record.fields),
  }));

  // (8)(9) cloudkit_ok=1 + edit_history INSERT + contribution_count++ を原子的に。
  //     ここで失敗しても CloudKit は反映済みなので ok を返し、cloudkit_ok=0 の孤児として後で reconcile。
  try {
    await finalizeEditBatch(env.DB, batchId, user.uid, entries);
  } catch (e: any) {
    console.error(`[edits] finalize failed batch=${batchId} (CK applied, history orphaned): ${String(e?.message ?? e)}`);
    // CloudKit には反映済み。クライアントの楽観更新を妨げないため 200 を返す。
    return json({ ok: true, batchId, results, warning: "history_not_recorded" });
  }

  // (10)
  return json({ ok: true, batchId, results });
}

// ---------------------------------------------------------------------------
// GET /master/:recordType/:recordName/history
// ---------------------------------------------------------------------------

export async function handleGetRecordHistory<E extends EditsEnv>(
  recordType: string,
  recordName: string,
  url: URL,
  env: E,
  deps: Pick<EditsDeps<E>, "json" | "error">
): Promise<Response> {
  const { json } = deps;
  const limit = parsePositiveInt(url.searchParams.get("limit"), 30);
  const rows = await getRecordHistory(env.DB, recordType, recordName, limit);
  // 一覧では変更フィールド名のみの要約 + フル diff を併せて返す (RedTeam Medium: 応答肥大対策の一次表現)。
  // レスポンスキーは確定契約により camelCase (batchId/changedFields/editorName/modifiedAt 等)。
  const history = rows.map((r) => {
    const before = r.before_json ? safeParse(r.before_json) : null;
    const after = r.after_json ? safeParse(r.after_json) : null;
    return {
      id: r.id,
      batchId: r.batch_id,
      op: r.op,
      changedFields: changedFields(before, after),
      before,
      after,
      // 他人の編集履歴が公開されるためメール混入を伏せる (feed.ts と同じマスク。編集者匿名性)。
      editorName: maskDisplayName(r.editor_name),
      source: r.source,
      modifiedAt: r.modified_at,
      createdAt: r.created_at,
      reverted: !!r.reverted || r.reverted_at != null,
    };
  });
  return json({ history });
}

function parsePositiveInt(s: string | null, fallback: number): number {
  const n = s ? parseInt(s, 10) : NaN;
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

function safeParse(s: string): Record<string, unknown> | null {
  try {
    return JSON.parse(s) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** before/after から変更されたフィールド名を抽出。 */
function changedFields(
  before: Record<string, unknown> | null,
  after: Record<string, unknown> | null
): string[] {
  if (!before) return after ? Object.keys(after) : [];
  if (!after) return Object.keys(before); // delete
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  const changed: string[] = [];
  for (const k of keys) {
    if (k === "modifiedAt" || k === "deletedAt") continue;
    if (JSON.stringify(before[k]) !== JSON.stringify(after[k])) changed.push(k);
  }
  return changed;
}
