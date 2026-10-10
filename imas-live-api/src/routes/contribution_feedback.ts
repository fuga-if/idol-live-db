// routes/contribution_feedback.ts — データを入れた人への手応えと、公演ページの奥付の入口。
// 本体は contribution_feedback.ts。ここは道順だけ。

import {
  handleGetMyFeedback, handleGetShowCredits, handlePostCreditOptIn, handlePostShowViews,
} from "../contribution_feedback";
import type { RouteContext } from "./context";
import { decodePathParam } from "./guards";

export async function handleContributionFeedback(ctx: RouteContext): Promise<Response | null> {
  const { request, path } = ctx;

  if (path === "/me/feedback" && request.method === "GET") return handleGetMyFeedback(ctx);
  if (path === "/shows/views" && request.method === "POST") return handlePostShowViews(ctx);
  if (path === "/users/me/credit" && request.method === "POST") return handlePostCreditOptIn(ctx);

  const credits = path.match(/^\/shows\/([^/]+)\/credits$/);
  if (credits && request.method === "GET") {
    const showId = decodePathParam(ctx, credits[1], "show_id");
    if (showId instanceof Response) return showId;
    return handleGetShowCredits(ctx, showId);
  }
  return null;
}
