// routes/edits.ts — オープン編集 (マスタの編集・フィード・Good・差し戻し・修正リクエスト) の入口。
//
//   GET    /edits                                 — 最近の編集のフィード (feed.ts)
//   GET    /me/edits                              — 自分の編集 (feed.ts)
//   POST   /edits/:batchId/good・DELETE 同         — 編集への Good (edit_good.ts)
//   POST   /edits/:batchId/revert                 — 1 batch の差し戻し (revert.ts)
//   POST   /edits                                 — マスタの編集 (edits.ts)
//   POST   /edit-requests                         — マスタの修正リクエスト (edit_requests.ts)
//   GET    /master/:recordType/:recordName/history — レコードの編集履歴 (edits.ts)
// 本体はそれぞれのモジュール。ここは道順だけ。

import { handleGetRecordHistory, handlePostEdits } from "../edits";
import { handleDeleteGood, handlePostGood } from "../edit_good";
import { handlePostEditRequests } from "../edit_requests";
import { handleGetFeed, handleGetMyEdits } from "../feed";
import { commitIpRateLimit } from "../rate_limit";
import { handlePostRevertBatch } from "../revert";
import type { RouteContext } from "./context";
import { decodePathParam, requireIpQuota } from "./guards";

/** 編集まわりのルート。どれでもなければ null。 */
export async function handleEdits(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path } = ctx;

  // ================================================================
  // 編集フィード + Good API (即時オープン編集の貢献可視化)
  //
  // 旧 submission/votes (承認投票) システムは即時オープン編集 (POST /edits) への
  // 移行と 0014 のテーブル DROP により完全撤去済み。Good は「承認」と切り離した
  // 感謝/人気指標として編集 batch 単位に付ける。
  // ================================================================

  // ----------------------------------------------------------------
  // GET /edits — 最近の編集フィード (匿名可。auth あれば has_user_good 付与)
  // ----------------------------------------------------------------
  if (path === "/edits" && request.method === "GET") {
    // 読み取りのみ。/search と同様 IP rate-limit (dryCheck → commit)。
    const feedRl = await requireIpQuota(ctx, "feed");
    if (feedRl instanceof Response) return feedRl;
    const res = await handleGetFeed(ctx);
    await commitIpRateLimit(env.DB, feedRl);
    return res;
  }

  // ----------------------------------------------------------------
  // GET /me/edits — 自分の編集 batch 一覧 (本人 revert 用, auth 必須)
  // ----------------------------------------------------------------
  if (path === "/me/edits" && request.method === "GET") {
    return handleGetMyEdits(ctx);
  }

  // ----------------------------------------------------------------
  // POST | DELETE /edits/:batchId/good — 編集への Good トグル (auth 必須)
  // ----------------------------------------------------------------
  const editGoodMatch = path.match(/^\/edits\/(\d+)\/good$/);
  if (editGoodMatch && request.method === "POST") {
    return handlePostGood(ctx, editGoodMatch[1]);
  }
  if (editGoodMatch && request.method === "DELETE") {
    return handleDeleteGood(ctx, editGoodMatch[1]);
  }

  // ----------------------------------------------------------------
  // POST /edits/:batchId/revert — 本人 (自分の batch) または admin が 1 batch を revert
  // ----------------------------------------------------------------
  const editRevertMatch = path.match(/^\/edits\/(\d+)\/revert$/);
  if (editRevertMatch && request.method === "POST") {
    return handlePostRevertBatch(ctx, editRevertMatch[1]);
  }

  // ----------------------------------------------------------------
  // POST /edits — マスタ create/update/delete (オープン編集, 1 リクエスト = 1 edit_batch)
  // ----------------------------------------------------------------
  if (path === "/edits" && request.method === "POST") {
    return handlePostEdits(ctx);
  }

  // ----------------------------------------------------------------
  // POST /edit-requests — マスタ修正リクエスト (GitHub issue 化, CloudKit に書かない)
  // ----------------------------------------------------------------
  if (path === "/edit-requests" && request.method === "POST") {
    return handlePostEditRequests(ctx);
  }

  // ----------------------------------------------------------------
  // GET /master/:recordType/:recordName/history — レコードの編集履歴
  // ----------------------------------------------------------------
  const masterHistoryMatch = path.match(/^\/master\/([^/]+)\/([^/]+)\/history$/);
  if (masterHistoryMatch && request.method === "GET") {
    const recordType = decodePathParam(ctx, masterHistoryMatch[1], "record_type");
    if (recordType instanceof Response) return recordType;
    const recordName = decodePathParam(ctx, masterHistoryMatch[2], "record_name");
    if (recordName instanceof Response) return recordName;
    return handleGetRecordHistory(ctx, recordType, recordName);
  }

  return null;
}
