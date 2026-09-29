// edit_good.ts — 編集 (貢献) への Good (感謝/拍手) トグル。
//
//   POST   /edits/:batchId/good   Good を付ける (idempotent。多重押下しても 1)
//   DELETE /edits/:batchId/good   Good を外す
//
// Good は「承認」と切り離した感謝/人気指標。1 ユーザー操作 = 1 edit_batch (Phase 1) なので
// Good も batch 単位で付ける。複合 PK (batch_id, user_id) で 1 アカウント 1 Good を物理排除。
//
// 貢献度の 2 指標は個別集計し合成しない (契約):
//   - 編集件数      = users.contribution_count (1 batch finalize で +1。Good では一切触らない)
//   - 受け取った Good = edit_good を editor 単位で COUNT (badges で都度算出)
// したがって Good toggle は edit_good 行の INSERT/DELETE のみで、CloudKit も
// contribution_count も触らない (D1 内で閉じる。RedTeam: Good は CloudKit 非依存なので batch で可)。
//
// 認可順序 (契約 + RedTeam):
//   (1) getAuthUser → 401
//   (2) users.is_banned → 403
//   (3) checkRateLimit(good) → 429
//   (4) edit_batch から editor_id 取得。無ければ 404 / cloudkit_ok=0 (未反映) なら 409 / editor===self なら 400
//   (5) INSERT OR IGNORE (POST) または DELETE (DELETE)
//   (6) COUNT(*) で goodCount 再算出して返す (レスポンスは { batchId, goodCount, gooded })

import { getAuthUser } from "./auth";
import { checkRateLimit } from "./rate_limit";
import type { RouteContext } from "./routes/context";
import { requireActiveUser } from "./routes/guards";
import { upsertUser } from "./users";

interface BatchRow {
  editor_id: string;
  cloudkit_ok: number;
}

/**
 * Good トグルの共通前段 (auth → ban → rate → batch 検証)。
 * 成功時は { user, batchId } を返し、失敗時は Response を返す (呼び出し側はそのまま return)。
 */
async function authorizeGood(
  ctx: RouteContext,
  batchIdRaw: string,
  enforceRateLimit: boolean
): Promise<{ uid: string; batchId: number } | Response> {
  const { request, env, error, rateLimitResponse } = ctx;

  // (1) auth
  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const batchId = parseInt(batchIdRaw, 10);
  if (!Number.isInteger(batchId) || batchId <= 0) return error("invalid batchId", 400);

  // (2)(3) ban + rate (取消にはレート制限をかけない: トグルの往復で枯渇させないため)
  const [inactive, rl] = await Promise.all([
    requireActiveUser(ctx, user),
    enforceRateLimit
      ? checkRateLimit(env.DB, user.uid, "good")
      : Promise.resolve(null),
  ]);
  if (inactive) return inactive;
  if (rl && !rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  // (4) batch 検証
  const batch = await env.DB.prepare(
    "SELECT editor_id, cloudkit_ok FROM edit_batch WHERE id = ?"
  )
    .bind(batchId)
    .first<BatchRow>();
  if (!batch) return error("edit batch not found", 404);
  // 未反映 (cloudkit_ok=0) の幽霊 batch には Good 不可 (フィードにも出ない)。
  if (!batch.cloudkit_ok) return error("edit not applied yet", 409);
  // 自己賞賛防止 (votes の自己投票禁止と同思想)。
  if (batch.editor_id === user.uid) return error("cannot good your own edit", 400);

  return { uid: user.uid, batchId };
}

/** batch の現在の Good 数を返す。 */
async function countGoods(db: D1Database, batchId: number): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) AS c FROM edit_good WHERE batch_id = ?")
    .bind(batchId)
    .first<{ c: number }>();
  return row?.c ?? 0;
}

// ---------------------------------------------------------------------------
// POST /edits/:batchId/good
// ---------------------------------------------------------------------------

export async function handlePostGood(ctx: RouteContext, batchIdRaw: string): Promise<Response> {
  const { env, json } = ctx;
  const auth = await authorizeGood(ctx, batchIdRaw, true);
  if (auth instanceof Response) return auth;

  // FK 孤児防止: edit_good.user_id が users(id) を参照するため行を保証する。
  await upsertUser(env, auth.uid);

  // (5) idempotent INSERT (複合 PK で多重 Good は no-op)
  await env.DB.prepare(
    "INSERT OR IGNORE INTO edit_good (batch_id, user_id, created_at) VALUES (?, ?, ?)"
  )
    .bind(auth.batchId, auth.uid, Date.now())
    .run();

  // (6) goodCount 再算出 (レスポンスキーは確定契約により camelCase)
  const goodCount = await countGoods(env.DB, auth.batchId);
  return json({ batchId: auth.batchId, goodCount, gooded: true });
}

// ---------------------------------------------------------------------------
// DELETE /edits/:batchId/good
// ---------------------------------------------------------------------------

export async function handleDeleteGood(ctx: RouteContext, batchIdRaw: string): Promise<Response> {
  const { env, json } = ctx;
  const auth = await authorizeGood(ctx, batchIdRaw, false);
  if (auth instanceof Response) return auth;

  // (5) DELETE (無ければ no-op)
  await env.DB.prepare(
    "DELETE FROM edit_good WHERE batch_id = ? AND user_id = ?"
  )
    .bind(auth.batchId, auth.uid)
    .run();

  // (6) goodCount 再算出 (レスポンスキーは確定契約により camelCase)
  const goodCount = await countGoods(env.DB, auth.batchId);
  return json({ batchId: auth.batchId, goodCount, gooded: false });
}
