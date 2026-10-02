// routes/lyric_structure.ts — 歌詞の行をくっつける / 切り離す (POST /songs/:song_id/lyric-structure)。
//
// 文字は書き換えない (src/lyrics_structure.ts 冒頭)。ログイン + is_banned + "edit" 枠で通す
// (コールの保存と同じ)。応答に歌詞本文は返さない — アプリは保存後に曲詳細を取り直す。
//
// 検索用の body / body_norm と gram 索引は本文の改行・空白が変わるので一緒に直す
// (PUT /admin/lyrics と同じ作法)。

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import { updateGramIndex } from "../lyrics_index";
import { applyStructureOp, parseStructureOp } from "../lyrics_structure";
import { normalizeForSearch, parseLines, NO_STORE } from "./lyrics";
import type { LyricLineRow } from "./lyrics";
import type { RouteContext } from "./context";
import { decodePathParam, requireActiveUser } from "./guards";

/** 検索用の平文 (歌詞行だけを改行で繋ぐ。routes/lyrics.ts の PUT と同じ形)。 */
function searchBody(lines: LyricLineRow[]): string {
  return lines.filter((l) => l.kind === "lyric").map((l) => l.text).join("\n");
}

export async function handleLyricStructure(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;

  const match = path.match(/^\/songs\/([^/]+)\/lyric-structure$/);
  if (!match || request.method !== "POST") return null;

  const authUser = await getAuthUser(request, env);
  if (!authUser) return error("Unauthorized", 401);
  const inactive = await requireActiveUser(ctx, authUser);
  if (inactive) return inactive;

  const songId = decodePathParam(ctx, match[1], "song_id");
  if (songId instanceof Response) return songId;
  if (!songId || songId.length > 200) return error("invalid song_id", 400);

  const header = await env.DB.prepare("SELECT status, lines_json FROM song_lyrics WHERE song_id = ?")
    .bind(songId)
    .first<{ status: string; lines_json: string | null }>();
  if (!header || header.status !== "published") return error("lyrics not found", 404);

  const op = parseStructureOp(await request.json().catch(() => null));
  if (typeof op === "string") return error(op, 400);
  const existing = parseLines(header.lines_json);
  const result = applyStructureOp(existing, op, () => "ll_" + crypto.randomUUID());
  if (!result.ok) return error(result.error, 400);

  const rl = await checkRateLimit(env.DB, authUser.uid, "edit");
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const body = searchBody(result.lines);
  const bodyNorm = normalizeForSearch(body);
  await env.DB.prepare(
    "UPDATE song_lyrics SET lines_json = ?, body = ?, body_norm = ?, updated_at = datetime('now') WHERE song_id = ?"
  )
    .bind(JSON.stringify(result.lines), body, bodyNorm, songId)
    .run();

  // 索引は副次データ。落ちても保存は成功として返す (PUT /admin/lyrics と同じ方針)。
  try {
    await updateGramIndex(env, songId, normalizeForSearch(searchBody(existing)), bodyNorm);
  } catch (err) {
    console.error("lyrics_gram_index_update_failed", songId, err);
  }

  return json({ songId, lineCount: result.lines.length }, 200, NO_STORE);
}
