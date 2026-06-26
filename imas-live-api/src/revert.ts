// revert.ts — 編集 batch の巻き戻し (本人 revert + admin モデレーション)。
//
//   POST /edits/:batchId/revert          本人 (自分の batch のみ) または admin が 1 batch を revert
//   POST /admin/revert-user              admin が 1 ユーザーの全編集を新しい順に一括 revert (also_ban 任意)
//   GET  /admin/users/:id/edits          admin が対象ユーザーの編集 batch 一覧を閲覧
//
// 設計 (area="moderation-revert" + 契約 v2):
//   revert は edit_history を唯一の rollback ソースとして「逆適用」する。1 batch = all-or-nothing:
//     - op=create → buildSoftDelete (deletedAt セット。ハード削除は iOS 差分同期に伝播しないため禁止)
//     - op=update → before_json で buildForceUpdate (権威 before へ巻き戻し。
//                    編集で追加されたフィールド (after にあって before に無い) は explicit-null でクリア)
//     - op=delete → before_json + deletedAt=null で buildForceUpdate (ソフト削除を解除して復元)
//     - op=snapshot (ShowSetlist) → show のセトリ全体を before スナップショットへ置換
//                    (before の全 item/performer を forceUpdate + after にだけ在る現存分を softDelete)
//   競合スキップ: 対象レコードの最新編集が「この batch 以外かつ別 editor」なら、その batch 全体を skip
//                (善良ユーザーの後続修正を踏み潰さない。RedTeam High: 判定は created_at ではなく id で行う)。
//   冪等性: edit_batch.reverted_at が既に立っていれば already_reverted (二重 revert 防止)。
//   監査連続性: revert 自体を op=revert / source=revert / reverts_batch_id=対象 の新規 batch として記録する。
//   原子性: D1↔CloudKit は跨ぐため完全な原子性は不可。CloudKit 全 op 成功時のみ D1 を確定 (reverted_at +
//           各 edit_history.reverted=1 + revert 履歴 INSERT を 1 つの D1 batch())。CloudKit 失敗 → 502 で
//           reverted_at を立てない (soft delete / forceUpdate は冪等なので再実行で安全に残りを処理)。

import {
  buildForceUpdate,
  buildSoftDelete,
  cloudKitModify,
  type CloudKitOperation,
} from "./cloudkit";
import { SHOW_SETLIST_TYPE, fetchShowSetlistSnapshot } from "./setlist_snapshot";

const CK_CHUNK = 200; // cloudKitModify の 1 リクエストあたり op 数 (/edits と同じ)

export interface RevertEnv {
  DB: D1Database;
  CLOUDKIT_KEY_ID: string;
  CLOUDKIT_PRIVATE_KEY: string;
}

// ---------------------------------------------------------------------------
// D1 row 型
// ---------------------------------------------------------------------------

interface BatchRow {
  id: number;
  editor_id: string;
  source: string;
  op: string;
  cloudkit_ok: number;
  reverted_at: number | null;
}

interface HistoryRow {
  id: number;
  record_type: string;
  record_name: string;
  op: string; // 'create' | 'update' | 'delete' | 'snapshot'
  before_json: string | null;
  after_json: string | null;
}

/** revert 1 件の結果種別。 */
export type RevertOutcome =
  | "reverted"
  | "already_reverted"
  | "skipped_conflict"
  | "not_found"
  | "not_applied"
  | "forbidden"
  | "failed";

export interface RevertResult {
  batchId: number;
  outcome: RevertOutcome;
  /** revert 操作を記録した新規 batch の id (outcome='reverted' のみ)。 */
  revertBatchId?: number;
  /** skip / failed の理由。 */
  reason?: string;
}

// ---------------------------------------------------------------------------
// 逆適用 op の構築
// ---------------------------------------------------------------------------

function safeParseObject(s: string | null): Record<string, unknown> | null {
  if (!s) return null;
  try {
    const v = JSON.parse(s);
    return v && typeof v === "object" ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}

/**
 * update の巻き戻し fields を構築する。
 * before の全フィールドを送り、さらに「編集で追加された (after にあって before に無い)」フィールドは
 * explicit-null でクリアする (buildForceUpdate が null を value:null で送るため、追加値が CloudKit に
 * 残って差分同期で復活する Critical#1 を防ぐ)。
 */
function buildUpdateRevertFields(
  before: Record<string, unknown>,
  after: Record<string, unknown> | null
): Record<string, unknown> {
  const fields: Record<string, unknown> = { ...before };
  // システム管理フィールドは送らない (buildForceUpdate が modifiedAt を再注入。deletedAt は update では触らない)。
  delete fields.modifiedAt;
  delete fields.deletedAt;
  if (after) {
    for (const k of Object.keys(after)) {
      if (k === "modifiedAt" || k === "deletedAt") continue;
      if (!(k in fields)) fields[k] = null; // 追加されたフィールドを明示クリア
    }
  }
  return fields;
}

/** ShowSetlist スナップショットの before/after に格納される形。 */
interface SnapshotShape {
  items?: Array<{ recordName: string; fields: Record<string, unknown> }>;
  performers?: Array<{ recordName: string; fields: Record<string, unknown> }>;
}

/**
 * ShowSetlist スナップショット行の逆適用 op を構築する。
 * before の全 item/performer を forceUpdate で復元し、after にだけ存在する (= この編集で増えた) 分は
 * softDelete する。これにより show のセトリ全体が before の状態へ戻る。
 */
function buildSnapshotRevertOps(
  before: SnapshotShape,
  after: SnapshotShape | null
): CloudKitOperation[] {
  const ops: CloudKitOperation[] = [];
  const beforeItemNames = new Set<string>();
  const beforePerfNames = new Set<string>();

  for (const it of before.items ?? []) {
    beforeItemNames.add(it.recordName);
    // before に在ったレコードは復元 (deletedAt をクリアして確実に生かす)。
    ops.push(buildForceUpdate("SetlistItem", it.recordName, { ...it.fields, deletedAt: null }));
  }
  for (const pf of before.performers ?? []) {
    beforePerfNames.add(pf.recordName);
    ops.push(buildForceUpdate("SetlistPerformer", pf.recordName, { ...pf.fields, deletedAt: null }));
  }
  // after にだけ在る (この編集で追加された) レコードは soft delete で除去する。
  for (const it of after?.items ?? []) {
    if (!beforeItemNames.has(it.recordName)) ops.push(buildSoftDelete("SetlistItem", it.recordName));
  }
  for (const pf of after?.performers ?? []) {
    if (!beforePerfNames.has(pf.recordName)) ops.push(buildSoftDelete("SetlistPerformer", pf.recordName));
  }
  return ops;
}

/**
 * ShowSetlist スナップショット行の逆適用 op を **現状セトリの再 query** を起点に構築する (確定契約 §5)。
 *
 * 保存済み after に頼らず、revert 時点の CloudKit の現状セトリ (showId == record_name) を再取得し:
 *   - before の全 item/performer を forceUpdate で復元 (deletedAt クリア)
 *   - 現状に在るが before に無いレコードを soft-delete
 * とする。これにより「保存時の after が古い/取りこぼした」場合でも現状を正として確実に before へ収束する。
 * 第三者の後続編集は競合スキップ (hasConflict) で別途弾かれるため、ここで踏み潰すことはない
 * (競合があれば revert 自体が skipped_conflict になりこの関数は呼ばれない)。
 *
 * 再 query 失敗時は null を返す (呼び出し側で failed 扱いにし reverted_at を立てない)。
 */
async function buildSnapshotRevertOpsLive(
  showId: string,
  before: SnapshotShape,
  env: RevertEnv
): Promise<CloudKitOperation[] | null> {
  const ops: CloudKitOperation[] = [];
  const beforeItemNames = new Set<string>();
  const beforePerfNames = new Set<string>();

  for (const it of before.items ?? []) {
    beforeItemNames.add(it.recordName);
    ops.push(buildForceUpdate("SetlistItem", it.recordName, { ...it.fields, deletedAt: null }));
  }
  for (const pf of before.performers ?? []) {
    beforePerfNames.add(pf.recordName);
    ops.push(buildForceUpdate("SetlistPerformer", pf.recordName, { ...pf.fields, deletedAt: null }));
  }

  // 現状セトリを CloudKit から権威再取得 (soft-deleted は除外済み)。
  const live = await fetchShowSetlistSnapshot(showId, env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
  if (!live.ok) return null;

  // 現状に在って before に無い = この編集以降に増えた分 → soft-delete (before へ収束)。
  for (const it of live.snapshot.items) {
    if (!beforeItemNames.has(it.recordName)) ops.push(buildSoftDelete("SetlistItem", it.recordName));
  }
  for (const pf of live.snapshot.performers) {
    if (!beforePerfNames.has(pf.recordName)) ops.push(buildSoftDelete("SetlistPerformer", pf.recordName));
  }
  return ops;
}

/**
 * 1 件の edit_history 行から CloudKit 逆適用 op 群を構築する (非 snapshot 行用の同期版)。
 * 逆適用不能 (例: create なのに before/after が無い) なら null を返す (呼び出し側で failed 扱い)。
 *
 * ShowSetlist スナップショット行は現状セトリ再 query が必要なため別経路 (buildSnapshotRevertOpsLive)。
 * ここでは予測 (predictRevertOutcome) のため snapshot は「before があれば構築可」とだけ判定し、
 * buildSnapshotRevertOps (保存 after ベース) で op 数を見積もる。
 */
function buildRevertOpsForEntry(row: HistoryRow): CloudKitOperation[] | null {
  const before = safeParseObject(row.before_json);
  const after = safeParseObject(row.after_json);

  if (row.op === SHOW_SETLIST_TYPE || row.op === "snapshot") {
    // ShowSetlist スナップショット (record_type='ShowSetlist', op='snapshot')。
    if (!before) return null; // before が無いスナップショットは復元不能
    return buildSnapshotRevertOps(before as SnapshotShape, after as SnapshotShape | null);
  }

  switch (row.op) {
    case "create":
      // 追加されたレコードを soft delete で消す。
      return [buildSoftDelete(row.record_type, row.record_name)];
    case "update": {
      if (!before) return null; // before 不明 = 元状態が無い → 逆適用不能
      return [buildForceUpdate(row.record_type, row.record_name, buildUpdateRevertFields(before, after))];
    }
    case "delete": {
      // soft delete を解除して復元。before の全フィールド + deletedAt=null。
      // before が無い (元から欠落) 場合でも deletedAt クリアだけは送る (冪等)。
      const fields: Record<string, unknown> = before ? { ...before } : {};
      delete fields.modifiedAt;
      fields.deletedAt = null;
      return [buildForceUpdate(row.record_type, row.record_name, fields)];
    }
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// 競合検出: 対象 batch の各レコードについて、より新しい他者編集が無いか
// ---------------------------------------------------------------------------

/**
 * この batch が touch した (record_type, record_name) のいずれかに対し、
 * 「この batch より新しい cloudkit_ok=1 の編集が、別の editor によって行われている」場合 true。
 * その場合 batch 全体を skip する (善良ユーザーの後続修正を保護)。
 *
 * 判定は created_at ではなく edit_history.id (単調増加) で行う (RedTeam High: 同時刻衝突を避ける)。
 * revert 操作自体 (source='revert') は競合カウントから除外する (モデレーションの修復まで踏まないため)。
 */
async function hasConflict(
  db: D1Database,
  batch: BatchRow,
  historyRows: HistoryRow[]
): Promise<{ conflict: boolean; record?: string }> {
  const maxHistId = historyRows.reduce((m, r) => (r.id > m ? r.id : m), 0);
  for (const row of historyRows) {
    // ShowSetlist スナップショットは個別 SetlistItem/Performer 行とは別レイヤなので、
    // 同 record_name (= showId) で ShowSetlist の後続編集があるかを見る。
    const later = await db
      .prepare(
        `SELECT eh.id
           FROM edit_history eh
           JOIN edit_batch eb ON eb.id = eh.batch_id
          WHERE eh.record_type = ? AND eh.record_name = ?
            AND eh.id > ?
            AND eb.cloudkit_ok = 1
            AND eb.source != 'revert'
            AND eb.editor_id != ?
          LIMIT 1`
      )
      .bind(row.record_type, row.record_name, maxHistId, batch.editor_id)
      .first<{ id: number }>();
    if (later) return { conflict: true, record: `${row.record_type}/${row.record_name}` };
  }
  return { conflict: false };
}

// ---------------------------------------------------------------------------
// predictRevertOutcome — dry-run 用。CloudKit / D1 を一切書かずに予測 outcome を返す
// ---------------------------------------------------------------------------

/**
 * 確定契約 §2 (revert dry_run): batchId を実際に巻き戻さず、revertBatch と同じ事前判定
 * (存在 / cloudkit_ok / 冪等 / 競合 skip / 逆適用 op 構築可否) だけを行い予測 outcome を返す。
 * CloudKit modify は呼ばない。revertBatch の判定ロジックと厳密に一致させること
 * (ずれると preview と実適用が乖離する)。
 *
 * 予測なので revertBatchId は付かない (まだ revert batch を作らない)。
 */
export async function predictRevertOutcome(
  env: RevertEnv,
  batchId: number,
  opts: { skipConflict?: boolean } = {}
): Promise<RevertResult> {
  const skipConflict = opts.skipConflict ?? true;

  const batch = await env.DB.prepare(
    "SELECT id, editor_id, source, op, cloudkit_ok, reverted_at FROM edit_batch WHERE id = ?"
  )
    .bind(batchId)
    .first<BatchRow>();
  if (!batch) return { batchId, outcome: "not_found" };
  if (!batch.cloudkit_ok) return { batchId, outcome: "not_applied", reason: "edit not applied to CloudKit" };
  if (batch.reverted_at != null) return { batchId, outcome: "already_reverted" };

  const { results: allRows } = await env.DB.prepare(
    `SELECT id, record_type, record_name, op, before_json, after_json
       FROM edit_history WHERE batch_id = ? ORDER BY id DESC`
  )
    .bind(batchId)
    .all<HistoryRow>();
  const rows = allRows ?? [];
  if (rows.length === 0) return { batchId, outcome: "failed", reason: "no edit_history rows" };

  const hasSnapshot = rows.some((r) => r.record_type === SHOW_SETLIST_TYPE);
  const applyRows = hasSnapshot ? rows.filter((r) => r.record_type === SHOW_SETLIST_TYPE) : rows;

  if (skipConflict) {
    const c = await hasConflict(env.DB, batch, applyRows);
    if (c.conflict) return { batchId, outcome: "skipped_conflict", reason: `newer edit by another user on ${c.record}` };
  }

  // 逆適用 op が 1 行でも構築不能なら revertBatch は failed になる → 予測でも failed。
  let opCount = 0;
  for (const row of applyRows) {
    const ops = buildRevertOpsForEntry(row);
    if (ops === null) {
      return { batchId, outcome: "failed", reason: `cannot build revert op for ${row.record_type}/${row.record_name} (op=${row.op})` };
    }
    opCount += ops.length;
  }
  if (opCount === 0) return { batchId, outcome: "failed", reason: "no revert operations" };

  return { batchId, outcome: "reverted" };
}

// ---------------------------------------------------------------------------
// revertBatch — 1 batch を all-or-nothing で巻き戻す
// ---------------------------------------------------------------------------

/**
 * batchId を巻き戻す。actorUid は revert 実行者 (本人 or admin)。
 *
 * 前提チェックは呼び出し側 (route ハンドラ) で auth/admin 判定済みとし、ここでは
 *   - batch の存在 / cloudkit_ok / reverted_at (冪等) / 競合
 * を見て CloudKit 逆適用 → D1 確定までを行う。
 *
 * skipConflict=true (既定) なら後続他者編集ありで skipped_conflict。false なら強制 revert (admin force 用)。
 */
export async function revertBatch(
  env: RevertEnv,
  batchId: number,
  actorUid: string,
  opts: { skipConflict?: boolean } = {}
): Promise<RevertResult> {
  const skipConflict = opts.skipConflict ?? true;

  const batch = await env.DB.prepare(
    "SELECT id, editor_id, source, op, cloudkit_ok, reverted_at FROM edit_batch WHERE id = ?"
  )
    .bind(batchId)
    .first<BatchRow>();
  if (!batch) return { batchId, outcome: "not_found" };
  if (!batch.cloudkit_ok) return { batchId, outcome: "not_applied", reason: "edit not applied to CloudKit" };
  if (batch.reverted_at != null) return { batchId, outcome: "already_reverted" };

  // 逆適用対象の history 行を新しい順 (id DESC) に取得。
  // ShowSetlist スナップショット行があれば、それが setlist の唯一の revert 元になるため、
  // 同 batch 内の個別 SetlistItem/SetlistPerformer 行はスキップする (二重適用回避)。
  const { results: allRows } = await env.DB.prepare(
    `SELECT id, record_type, record_name, op, before_json, after_json
       FROM edit_history WHERE batch_id = ? ORDER BY id DESC`
  )
    .bind(batchId)
    .all<HistoryRow>();
  const rows = allRows ?? [];
  if (rows.length === 0) return { batchId, outcome: "failed", reason: "no edit_history rows" };

  const hasSnapshot = rows.some((r) => r.record_type === SHOW_SETLIST_TYPE);
  const applyRows = hasSnapshot
    ? rows.filter((r) => r.record_type === SHOW_SETLIST_TYPE)
    : rows;

  // 競合判定は applyRows の record に対して行う (スナップショットがある場合は ShowSetlist record で判定)。
  if (skipConflict) {
    const c = await hasConflict(env.DB, batch, applyRows);
    if (c.conflict) return { batchId, outcome: "skipped_conflict", reason: `newer edit by another user on ${c.record}` };
  }

  // CloudKit 逆適用 op を構築 (all-or-nothing: 1 行でも逆適用不能なら failed で中断)。
  // ShowSetlist スナップショット行だけは現状セトリ再 query 起点で構築する (確定契約 §5)。
  const ckOps: CloudKitOperation[] = [];
  for (const row of applyRows) {
    let ops: CloudKitOperation[] | null;
    if (row.record_type === SHOW_SETLIST_TYPE || row.op === "snapshot") {
      const before = safeParseObject(row.before_json) as SnapshotShape | null;
      if (!before) return { batchId, outcome: "failed", reason: `snapshot before missing for ${row.record_name}` };
      // record_name = showId。現状セトリを再 query して before へ収束させる op を構築。
      ops = await buildSnapshotRevertOpsLive(row.record_name, before, env);
      if (ops === null) {
        return { batchId, outcome: "failed", reason: `cannot re-query current setlist for show ${row.record_name}` };
      }
    } else {
      ops = buildRevertOpsForEntry(row);
      if (ops === null) {
        return { batchId, outcome: "failed", reason: `cannot build revert op for ${row.record_type}/${row.record_name} (op=${row.op})` };
      }
    }
    ckOps.push(...ops);
  }
  if (ckOps.length === 0) return { batchId, outcome: "failed", reason: "no revert operations" };

  // CloudKit へ反映 (200 件ずつ chunk)。1 chunk でも失敗したら 502 相当 (reverted_at を立てない)。
  for (let i = 0; i < ckOps.length; i += CK_CHUNK) {
    const chunk = ckOps.slice(i, i + CK_CHUNK);
    const res = await cloudKitModify(chunk, env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
    if (!res.ok) {
      console.error(`[revert] cloudkit failed batch=${batchId} at ${i}/${ckOps.length}: ${res.error}`);
      return { batchId, outcome: "failed", reason: `cloudkit_error: ${res.error}` };
    }
  }

  // CloudKit 成功 → D1 を原子的に確定する:
  //   (a) 対象 batch.reverted_at / reverted_by をセット
  //   (b) 対象 batch の各 edit_history.reverted = 1
  //   (c) revert 操作自体を新規 batch (op=revert, source=revert, reverts_batch_id=対象) として INSERT
  //   (d) その revert batch を cloudkit_ok=1 にし、逆向き履歴 (before↔after を入れ替え) を記録
  const now = Date.now();
  const summary = `revert batch #${batchId}`;
  const revertRow = await env.DB.prepare(
    `INSERT INTO edit_batch (editor_id, source, op, summary, reverts_batch_id, cloudkit_ok, created_at)
     VALUES (?, 'revert', 'revert', ?, ?, 1, ?)
     RETURNING id`
  )
    .bind(actorUid, summary, batchId, now)
    .first<{ id: number }>();
  if (!revertRow) return { batchId, outcome: "failed", reason: "failed to create revert batch" };
  const revertBatchId = revertRow.id;

  const stmts: D1PreparedStatement[] = [
    env.DB.prepare("UPDATE edit_batch SET reverted_at = ?, reverted_by = ? WHERE id = ?").bind(
      now,
      actorUid,
      batchId
    ),
    env.DB.prepare("UPDATE edit_history SET reverted = 1 WHERE batch_id = ?").bind(batchId),
  ];
  // 逆向き履歴: 対象の各 op の before/after を入れ替えて revert batch に記録する
  // (op=revert として監査の連続性を保つ。after=元 before, before=元 after)。
  for (const row of applyRows) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO edit_history
           (batch_id, record_type, record_name, op, before_json, after_json, modified_at, created_at, reverted)
         VALUES (?, ?, ?, 'revert', ?, ?, ?, ?, 0)`
      ).bind(
        revertBatchId,
        row.record_type,
        row.record_name,
        row.after_json, // revert 後の before = 元の after
        row.before_json, // revert 後の after = 元の before
        now,
        now
      )
    );
  }
  try {
    await env.DB.batch(stmts);
  } catch (e: any) {
    console.error(`[revert] D1 finalize failed batch=${batchId} (CK applied): ${String(e?.message ?? e)}`);
    // CloudKit は反映済み。revert batch 行は残るが reverted_at が立たない可能性 → 再実行で冪等に補正可能。
    return { batchId, outcome: "failed", reason: "db_finalize_failed_after_cloudkit" };
  }

  return { batchId, outcome: "reverted", revertBatchId };
}

// ---------------------------------------------------------------------------
// revertUserEdits — 1 ユーザーの全編集を新しい順に一括 revert (admin)
// ---------------------------------------------------------------------------

export interface RevertUserSummary {
  userId: string;
  banned: boolean;
  reverted: number;
  skipped: number;
  failed: number;
  alreadyReverted: number;
  /** 確定契約 §2: dry-run (CloudKit 未実行・予測のみ) なら true。 */
  dryRun: boolean;
  items: RevertResult[];
}

const MAX_REVERT_BATCHES = 1000; // 1 リクエストで巻き戻す batch 上限 (攻撃ベクタ・CPU/CloudKit quota 保護)

/**
 * 対象ユーザーの cloudkit_ok=1 / 未 revert / source='app' の編集 batch を新しい順に巻き戻す。
 * also_ban=true なら先に is_banned=1 (+ 付けた Good 撤去) を確定してから revert する
 * (revert 中の追加編集を止めるため。/admin/ban と同じ Good 撤去で水増しを巻き戻す)。
 *
 * source='app' のみを対象にする (source='revert' のモデレーション操作や seed を誤って巻き戻さない)。
 * since (ms) 指定時はそれ以降の編集に絞る。
 *
 * 確定契約 §2 (dry_run): dryRun=true のときは CloudKit modify を一切呼ばず、対象 batchId 一覧と
 * 各 batch の予測 outcome (競合 skip 判定を含む) だけを集計して返す。BAN も行わない (banned=false 固定)。
 * iOS のプレビューはこの dryRun:true 経路を叩く。
 */
export async function revertUserEdits(
  env: RevertEnv,
  actorUid: string,
  params: { userId: string; alsoBan?: boolean; since?: number; skipConflict?: boolean; dryRun?: boolean }
): Promise<RevertUserSummary> {
  const { userId } = params;
  const skipConflict = params.skipConflict ?? true;
  const dryRun = params.dryRun ?? false;
  let banned = false;

  // dry-run は副作用ゼロ (BAN もしない)。本実行のみ also_ban を先に確定する。
  if (params.alsoBan && !dryRun) {
    await env.DB.batch([
      env.DB.prepare("UPDATE users SET is_banned = 1 WHERE id = ?").bind(userId),
      // BAN 対象が付けた Good を撤去 (受け手の goods_received は都度 COUNT 算出なので自動で減る)。
      env.DB.prepare("DELETE FROM edit_good WHERE user_id = ?").bind(userId),
    ]);
    banned = true;
  }

  // 巻き戻し対象 batch を新しい順に取得 (新しい順 = 逆適用順)。
  // 取得時点で id を範囲固定し、revert 実行中に積まれた新規編集を巻き込まない (RedTeam High)。
  const sinceClause = params.since != null ? " AND created_at >= ?" : "";
  const stmt = env.DB.prepare(
    `SELECT id FROM edit_batch
       WHERE editor_id = ? AND cloudkit_ok = 1 AND reverted_at IS NULL AND source = 'app'${sinceClause}
       ORDER BY id DESC
       LIMIT ?`
  );
  const bound =
    params.since != null
      ? stmt.bind(userId, params.since, MAX_REVERT_BATCHES)
      : stmt.bind(userId, MAX_REVERT_BATCHES);
  const { results } = await bound.all<{ id: number }>();
  const batchIds = (results ?? []).map((r) => r.id);

  const items: RevertResult[] = [];
  let reverted = 0;
  let skipped = 0;
  let failed = 0;
  let alreadyReverted = 0;

  for (const id of batchIds) {
    // dry-run は予測のみ (CloudKit / D1 へ書かない)。本実行は実際に巻き戻す。
    const r = dryRun
      ? await predictRevertOutcome(env, id, { skipConflict })
      : await revertBatch(env, id, actorUid, { skipConflict });
    items.push(r);
    switch (r.outcome) {
      case "reverted":
        reverted++;
        break;
      case "skipped_conflict":
        skipped++;
        break;
      case "already_reverted":
        alreadyReverted++;
        break;
      default:
        failed++;
        break;
    }
  }

  return { userId, banned, reverted, skipped, failed, alreadyReverted, dryRun, items };
}

// ---------------------------------------------------------------------------
// HTTP ハンドラ (index.ts のクロージャ deps を注入する。edits.ts と同じパターン)。
// ---------------------------------------------------------------------------

export interface RevertDeps<E extends RevertEnv> {
  getAuthUser: (request: Request, env: E) => Promise<{ uid: string; email?: string } | null>;
  checkIsAdmin: (env: E, uid: string) => Promise<boolean>;
  json: (data: unknown, status?: number) => Response;
  error: (message: string, status?: number) => Response;
}

/** RevertOutcome を HTTP ステータスに対応付ける (本人/admin revert 共通)。 */
function outcomeStatus(outcome: RevertOutcome): number {
  switch (outcome) {
    case "reverted":
    case "already_reverted":
    case "skipped_conflict":
      return 200; // 冪等・競合スキップは「リクエストは正常処理」扱い
    case "not_found":
      return 404;
    case "not_applied":
      return 409;
    case "forbidden":
      return 403;
    case "failed":
    default:
      return 502; // CloudKit 逆適用失敗 / 逆適用不能
  }
}

// ---------------------------------------------------------------------------
// POST /edits/:batchId/revert — 本人 (自分の batch のみ) または admin が 1 batch を revert
// ---------------------------------------------------------------------------

export async function handlePostRevertBatch<E extends RevertEnv>(
  request: Request,
  env: E,
  deps: RevertDeps<E>,
  batchIdRaw: string
): Promise<Response> {
  const { json, error } = deps;

  const user = await deps.getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const batchId = parseInt(batchIdRaw, 10);
  if (!Number.isInteger(batchId) || batchId <= 0) return error("invalid batchId", 400);

  // body は任意。admin は force で競合を無視して強制 revert できる (本人は force 不可)。
  let force = false;
  try {
    const raw = await request.text();
    if (raw) {
      const body = JSON.parse(raw) as { force?: boolean } | null;
      force = !!body?.force;
    }
  } catch {
    return error("invalid json body", 400);
  }

  const isAdmin = await deps.checkIsAdmin(env, user.uid);

  // 対象 batch の所有者確認 (本人 or admin のみ)。
  const owner = await env.DB.prepare("SELECT editor_id FROM edit_batch WHERE id = ?")
    .bind(batchId)
    .first<{ editor_id: string }>();
  if (!owner) return error("edit batch not found", 404);
  if (owner.editor_id !== user.uid && !isAdmin) return error("Forbidden", 403);

  // force (競合無視) は admin のみ許可。本人 revert は常に競合スキップ。
  const skipConflict = !(force && isAdmin);

  const result = await revertBatch(env, batchId, user.uid, { skipConflict });
  // レスポンスキーは確定契約により camelCase (batchId/revertBatchId)。
  return json(
    {
      batchId: result.batchId,
      outcome: result.outcome,
      revertBatchId: result.revertBatchId,
      reason: result.reason,
    },
    outcomeStatus(result.outcome)
  );
}

// ---------------------------------------------------------------------------
// POST /admin/revert-user — admin が 1 ユーザーの全編集を一括 revert
// ---------------------------------------------------------------------------

export async function handlePostAdminRevertUser<E extends RevertEnv>(
  request: Request,
  env: E,
  deps: RevertDeps<E>
): Promise<Response> {
  const { json, error } = deps;

  const user = await deps.getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);
  if (!(await deps.checkIsAdmin(env, user.uid))) return error("Forbidden", 403);

  // 確定契約 §2: body は camelCase 直受け { userId, since?, alsoBan?, dryRun? } (+ force=競合無視)。
  let body:
    | { userId?: string; alsoBan?: boolean; since?: number; force?: boolean; dryRun?: boolean }
    | null;
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return error("invalid json body", 400);
  }
  const userId = body?.userId;
  if (!userId || typeof userId !== "string") return error("userId is required", 400);

  const since = typeof body?.since === "number" && Number.isFinite(body.since) ? body.since : undefined;

  const summary = await revertUserEdits(env, user.uid, {
    userId,
    alsoBan: !!body?.alsoBan,
    since,
    skipConflict: !body?.force, // admin は force で競合無視可
    dryRun: !!body?.dryRun,     // dryRun=true は CloudKit 未実行・予測のみ (banned=false 固定)
  });

  // レスポンスキーは確定契約 §1/§2 により camelCase 直返し
  // (userId/alreadyReverted/dryRun/items[].batchId/revertBatchId)。
  return json({
    userId: summary.userId,
    banned: summary.banned,
    reverted: summary.reverted,
    skipped: summary.skipped,
    failed: summary.failed,
    alreadyReverted: summary.alreadyReverted,
    dryRun: summary.dryRun,
    items: summary.items.map((r) => ({
      batchId: r.batchId,
      outcome: r.outcome,
      revertBatchId: r.revertBatchId,
      reason: r.reason,
    })),
  });
}

// ---------------------------------------------------------------------------
// GET /admin/users/:id/edits — admin が対象ユーザーの編集 batch 一覧を閲覧
// ---------------------------------------------------------------------------

interface AdminUserEditRow {
  id: number;
  op: string;
  source: string;
  summary: string | null;
  cloudkit_ok: number;
  reverted_at: number | null;
  created_at: number;
  record_type: string | null;
  record_name: string | null;
  op_count: number;
}

export async function handleGetAdminUserEdits<E extends RevertEnv>(
  request: Request,
  url: URL,
  env: E,
  deps: RevertDeps<E>,
  userId: string
): Promise<Response> {
  const { json, error } = deps;

  const user = await deps.getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);
  if (!(await deps.checkIsAdmin(env, user.uid))) return error("Forbidden", 403);

  const limit = clampInt(url.searchParams.get("limit"), 50, 1, 200);
  const offset = clampInt(url.searchParams.get("offset"), 0, 0, 1_000_000);
  const unrevertedOnly = url.searchParams.get("unreverted_only") === "true";

  const target = await env.DB.prepare(
    "SELECT id, display_name, is_banned FROM users WHERE id = ?"
  )
    .bind(userId)
    .first<{ id: string; display_name: string | null; is_banned: number }>();

  // 対象は実編集 (source='app') のみ。revert 操作 (source='revert') は表示・集計から除外。
  const revertedClause = unrevertedOnly ? " AND eb.reverted_at IS NULL" : "";
  const sql = `
    SELECT
      eb.id, eb.op, eb.source, eb.summary, eb.cloudkit_ok, eb.reverted_at, eb.created_at,
      (SELECT h.record_type FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_type,
      (SELECT h.record_name FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_name,
      (SELECT COUNT(*) FROM edit_history h WHERE h.batch_id = eb.id) AS op_count
    FROM edit_batch eb
    WHERE eb.editor_id = ? AND eb.cloudkit_ok = 1 AND eb.source = 'app'${revertedClause}
    ORDER BY eb.id DESC
    LIMIT ? OFFSET ?
  `;
  const { results } = await env.DB.prepare(sql)
    .bind(userId, limit, offset)
    .all<AdminUserEditRow>();

  const totals = await env.DB.prepare(
    `SELECT
       COUNT(*) AS total,
       SUM(CASE WHEN reverted_at IS NULL THEN 1 ELSE 0 END) AS unreverted
     FROM edit_batch
     WHERE editor_id = ? AND cloudkit_ok = 1 AND source = 'app'`
  )
    .bind(userId)
    .first<{ total: number; unreverted: number }>();

  // レスポンスキーは確定契約により camelCase (batchId/recordType/opCount 等)。
  return json({
    user: {
      uid: userId,
      displayName: target?.display_name ?? null,
      isBanned: !!target?.is_banned,
    },
    total: Number(totals?.total ?? 0),
    unreverted: Number(totals?.unreverted ?? 0),
    edits: (results ?? []).map((r) => ({
      batchId: r.id,
      op: r.op,
      source: r.source,
      summary: r.summary,
      recordType: r.record_type,
      recordName: r.record_name,
      opCount: r.op_count,
      reverted: r.reverted_at != null,
      revertedAt: r.reverted_at,
      createdAt: r.created_at,
    })),
  });
}

function clampInt(s: string | null, fallback: number, min: number, max: number): number {
  const n = s ? parseInt(s, 10) : NaN;
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(n, min), max);
}
