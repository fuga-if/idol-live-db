// feed.ts — 最近の編集フィード (オープン編集の相互監視 + 貢献可視化の中心)。
//
//   GET /edits?brand_id=&record_type=&editor_id=&page=&limit=   最近の編集 batch 一覧 (Good 数付き)
//   GET /me/edits?page=&limit=                                  自分の編集 batch 一覧 (本人 revert 用)
//
// edit_batch を新しい順に引き、editor (display_name のみ。メールは非露出) と
// Good 数 (edit_good を batch_id で COUNT) を載せる。1 batch = 1 ユーザー操作 (Phase 1) なので
// フィードの行も batch 単位。cloudkit_ok=1 (CloudKit 反映済み) の batch のみ表示する
// (cloudkit_ok=0 = 未反映/失敗の幽霊 batch はフィードに出さない。RedTeam Critical 二相対策)。

// edit_batch JOIN で 1 行に畳む際の代表 record_type/record_name は edit_history の先頭行から取る。
// summary は edit_batch.summary (サーバ機械生成) をそのまま使う。

export interface FeedEnv {
  DB: D1Database;
}

// 具象 Env (APPLE_BUNDLE_ID 等を持つ) と型整合させるため env 型を generic <E extends FeedEnv> で貫通させる
// (edits.ts の EditsDeps と同じパターン)。
export interface FeedDeps<E extends FeedEnv> {
  /** Bearer から認証ユーザーを得る (未認証 null)。匿名でも閲覧可、自分の Good 状態付与にのみ使用。 */
  getAuthUser: (request: Request, env: E) => Promise<{ uid: string; email?: string } | null>;
  json: (data: unknown, status?: number) => Response;
  error: (message: string, status?: number) => Response;
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/**
 * フィードの editor 表示名をメール露出しないようマスクする。
 * オープン編集経路の upsertUser(uid, email) でメールが display_name に入りうるため
 * (RedTeam: 編集者匿名性 / メール非露出)。
 *   foo@example.com → "foo***" (ローカル部先頭1文字 + ***)。空/null → "匿名"。
 */
export function maskDisplayName(name: string | null): string {
  if (!name) return "匿名";
  if (!EMAIL_RE.test(name)) return name;
  const local = name.split("@")[0];
  const head = local.slice(0, 1) || "*";
  return `${head}***`;
}

interface FeedRow {
  id: number;
  editor_id: string;
  op: string;
  summary: string | null;
  source: string;
  reverts_batch_id: number | null;
  created_at: number;
  reverted_at: number | null;
  editor_name: string | null;
  editor_avatar: string | null;
  editor_banned: number;
  record_type: string | null;
  record_name: string | null;
  good_count: number;
  has_user_good: number;
}

function parseFeedPaging(url: URL): { limit: number; offset: number; page: number } {
  const page = clampInt(url.searchParams.get("page"), 1, 1, 100000);
  const limit = clampInt(url.searchParams.get("limit"), 20, 1, 50);
  return { limit, offset: (page - 1) * limit, page };
}

function clampInt(s: string | null, fallback: number, min: number, max: number): number {
  const n = s ? parseInt(s, 10) : NaN;
  if (!Number.isFinite(n)) return fallback;
  return Math.min(Math.max(n, min), max);
}

/**
 * FeedRow を API レスポンス形へ整形。
 *
 * 確定契約 §1: editor_id (生の uid) は返さない。サーバが viewer の uid と editor_id を比較した
 * isOwnEdit(bool) だけを返す (編集者匿名性。「自分の編集か」の判定のみクライアントに許す)。
 * display_name はメール混入をマスク。レスポンスキーは全て camelCase 直返し
 * (iOS は convertFromSnakeCase に依存せず素の camelCase を decode する)。
 */
function toFeedItem(r: FeedRow, viewerUid: string) {
  return {
    batchId: r.id,
    editorDisplayName: maskDisplayName(r.editor_name),
    editorAvatarUrl: r.editor_avatar,
    editorBanned: !!r.editor_banned,
    isOwnEdit: viewerUid !== "" && r.editor_id === viewerUid,
    op: r.op,
    source: r.source,
    revertsBatchId: r.reverts_batch_id,
    recordType: r.record_type,
    recordName: r.record_name,
    summary: r.summary,
    goodCount: r.good_count,
    hasUserGood: r.has_user_good === 1,
    reverted: r.reverted_at != null,
    createdAt: r.created_at,
  };
}

// ---------------------------------------------------------------------------
// GET /edits — 最近の編集フィード
// ---------------------------------------------------------------------------

export async function handleGetFeed<E extends FeedEnv>(
  request: Request,
  url: URL,
  env: E,
  deps: FeedDeps<E>
): Promise<Response> {
  const { json } = deps;
  const { limit, offset, page } = parseFeedPaging(url);

  // 任意フィルタ
  const recordType = url.searchParams.get("record_type");
  const editorId = url.searchParams.get("editor_id");
  const brandId = url.searchParams.get("brand_id");

  // 認証は任意。あれば has_user_good を付与。
  const authUser = await deps.getAuthUser(request, env);
  const uid = authUser?.uid ?? "";

  // 各 batch の代表 record_type / record_name は edit_history の最小 id (= 最初の op) を採用。
  // record_type / brand_id フィルタは edit_history 側に EXISTS で効かせる。
  const conditions: string[] = ["eb.cloudkit_ok = 1"];
  const params: unknown[] = [];

  if (recordType) {
    conditions.push(
      "EXISTS (SELECT 1 FROM edit_history h WHERE h.batch_id = eb.id AND h.record_type = ?)"
    );
    params.push(recordType);
  }
  if (editorId) {
    conditions.push("eb.editor_id = ?");
    params.push(editorId);
  }
  if (brandId) {
    // edit_history.after_json / before_json は CK フィールド (camelCase) を JSON 文字列で持つ。
    // brandId フィールドを持つ編集 (Event/Idol/Song の brandId) を JSON 抽出でフィルタ。
    conditions.push(
      `EXISTS (SELECT 1 FROM edit_history h WHERE h.batch_id = eb.id
         AND (json_extract(h.after_json, '$.brandId') = ?
              OR json_extract(h.before_json, '$.brandId') = ?))`
    );
    params.push(brandId, brandId);
  }

  const where = "WHERE " + conditions.join(" AND ");

  const sql = `
    SELECT
      eb.id, eb.editor_id, eb.op, eb.summary, eb.source,
      eb.reverts_batch_id, eb.created_at, eb.reverted_at,
      u.display_name AS editor_name,
      u.avatar_url   AS editor_avatar,
      COALESCE(u.is_banned, 0) AS editor_banned,
      (SELECT h.record_type FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_type,
      (SELECT h.record_name FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_name,
      (SELECT COUNT(*) FROM edit_good g WHERE g.batch_id = eb.id) AS good_count,
      (SELECT COUNT(*) FROM edit_good g WHERE g.batch_id = eb.id AND g.user_id = ?) AS has_user_good
    FROM edit_batch eb
    LEFT JOIN users u ON u.id = eb.editor_id
    ${where}
    ORDER BY eb.created_at DESC
    LIMIT ? OFFSET ?
  `;

  const { results } = await env.DB.prepare(sql)
    .bind(uid, ...params, limit, offset)
    .all<FeedRow>();

  const countRow = await env.DB.prepare(
    `SELECT COUNT(*) AS total FROM edit_batch eb ${where}`
  )
    .bind(...params)
    .first<{ total: number }>();

  return json({
    items: (results ?? []).map((r) => toFeedItem(r, uid)),
    total: countRow?.total ?? 0,
    page,
    limit,
  });
}

// ---------------------------------------------------------------------------
// GET /me/edits — 自分の編集 batch 一覧 (本人 revert 用)
// ---------------------------------------------------------------------------

export async function handleGetMyEdits<E extends FeedEnv>(
  request: Request,
  url: URL,
  env: E,
  deps: FeedDeps<E>
): Promise<Response> {
  const { json, error } = deps;
  const authUser = await deps.getAuthUser(request, env);
  if (!authUser) return error("Unauthorized", 401);

  const { limit, offset, page } = parseFeedPaging(url);

  const sql = `
    SELECT
      eb.id, eb.editor_id, eb.op, eb.summary, eb.source,
      eb.reverts_batch_id, eb.created_at, eb.reverted_at,
      u.display_name AS editor_name,
      u.avatar_url   AS editor_avatar,
      COALESCE(u.is_banned, 0) AS editor_banned,
      (SELECT h.record_type FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_type,
      (SELECT h.record_name FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_name,
      (SELECT COUNT(*) FROM edit_good g WHERE g.batch_id = eb.id) AS good_count,
      (SELECT COUNT(*) FROM edit_good g WHERE g.batch_id = eb.id AND g.user_id = ?) AS has_user_good
    FROM edit_batch eb
    LEFT JOIN users u ON u.id = eb.editor_id
    WHERE eb.editor_id = ? AND eb.cloudkit_ok = 1
    ORDER BY eb.created_at DESC
    LIMIT ? OFFSET ?
  `;

  const { results } = await env.DB.prepare(sql)
    .bind(authUser.uid, authUser.uid, limit, offset)
    .all<FeedRow>();

  const countRow = await env.DB.prepare(
    "SELECT COUNT(*) AS total FROM edit_batch WHERE editor_id = ? AND cloudkit_ok = 1"
  )
    .bind(authUser.uid)
    .first<{ total: number }>();

  return json({
    // /me/edits は全件が本人の編集なので isOwnEdit は常に true (viewer=自分)。
    items: (results ?? []).map((r) => toFeedItem(r, authUser.uid)),
    total: countRow?.total ?? 0,
    page,
    limit,
  });
}
