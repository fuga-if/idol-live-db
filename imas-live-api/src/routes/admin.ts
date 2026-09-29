// routes/admin.ts — モデレーター (admin) の操作。
//
//   POST /admin/ban            — ユーザーを BAN し、その人が付けた Good を外す
//   POST /admin/revert-user    — 1 ユーザーの編集をまとめて差し戻す (revert.ts)
//   GET  /admin/users/:id/edits — 対象ユーザーの編集の一覧 (revert.ts)
// 歌詞の投入 (/admin/lyrics/*) は routes/lyrics.ts。

import { getAuthUser } from "../auth";
import { handleGetAdminUserEdits, handlePostAdminRevertUser } from "../revert";
import { checkIsAdmin } from "../users";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody } from "./guards";

/** /admin/ban・/admin/revert-user・/admin/users/:id/edits。どれでもなければ null。 */
export async function handleAdmin(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error } = ctx;

  // ----------------------------------------------------------------
  // POST /admin/ban — ユーザーを BAN (即時オープン編集を遮断)
  // ----------------------------------------------------------------
  //
  // 編集の巻き戻しは別途 POST /admin/revert-user (本人/admin revert 領域) が担う。
  // ここでは is_banned=1 に加え、BAN 対象が「他人の編集に付けた Good」を撤去する
  // (荒らしアカウントによる Good 水増しを巻き戻す。RedTeam edge_case)。
  // contribution_count は編集件数 (受け取った Good ではない) なので Good 撤去では変えない。
  if (path === "/admin/ban" && request.method === "POST") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    if (!(await checkIsAdmin(env, user.uid)))
      return error("Forbidden", 403);

    const body = await readJsonBody(ctx);
    if (body instanceof Response) return body;
    const targetUserId = body.user_id;
    if (!targetUserId) return error("user_id required");

    await env.DB.batch([
      env.DB.prepare("UPDATE users SET is_banned = 1 WHERE id = ?").bind(targetUserId),
      // BAN 対象が付けた Good を撤去 (受け手の goods_received は都度 COUNT 算出なので自動で減る)
      env.DB.prepare("DELETE FROM edit_good WHERE user_id = ?").bind(targetUserId),
    ]);

    return json({ banned: targetUserId });
  }

  // ----------------------------------------------------------------
  // POST /admin/revert-user — admin が 1 ユーザーの全編集を一括 revert (also_ban 任意)
  // ----------------------------------------------------------------
  if (path === "/admin/revert-user" && request.method === "POST") {
    return handlePostAdminRevertUser(ctx);
  }

  // ----------------------------------------------------------------
  // GET /admin/users/:id/edits — admin が対象ユーザーの編集 batch 一覧を閲覧
  // ----------------------------------------------------------------
  const adminUserEditsMatch = path.match(/^\/admin\/users\/([^/]+)\/edits$/);
  if (adminUserEditsMatch && request.method === "GET") {
    const targetUserId = decodePathParam(ctx, adminUserEditsMatch[1], "user_id");
    if (targetUserId instanceof Response) return targetUserId;
    return handleGetAdminUserEdits(ctx, targetUserId);
  }

  return null;
}
