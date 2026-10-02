// routes/lyric_likes.ts — 歌詞行の「ここ好き」(PUT / DELETE /songs/:song_id/lyric-likes/:line_id)。
//
// 人数は song_lyrics.likes_json に {行ID: 人数} で持ち、歌詞の応答 (buildLyricsPayload) の
// likeCount に載る。読み出し専用の口は作らない (歌詞の取得 1 回の読み取りに相乗りする)。
//
// 自分がどの行を好きと言ったかは端末が持つ (user_marks の lyricLikes)。サーバから
// 「自分の分」を引く口も作らない — 引くたびに D1 の読み取りが増えるため。
//
// ⚠️ 応答に歌詞本文を返さない (行 ID と人数だけ)。

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import { parseLines, parseLikeCounts, NO_STORE } from "./lyrics";
import type { RouteContext } from "./context";
import { decodePathParam, requireActiveUser } from "./guards";

/** 行 ID の形 (ll_<uuid> 等)。JSON パスに入れるので記号は通さない。 */
const LINE_ID = /^[A-Za-z0-9_-]{1,80}$/;

/** その行の人数を数え直して likes_json に書く文。加減算にしないので重複・取りこぼしでずれない。 */
export function recountStatement(db: D1Database, songId: string, lineId: string): D1PreparedStatement {
  return db
    .prepare(
      `UPDATE song_lyrics
          SET likes_json = json_set(COALESCE(NULLIF(likes_json, ''), '{}'), '$.' || json_quote(?),
                (SELECT COUNT(*) FROM lyric_line_likes WHERE song_id = ? AND line_id = ?))
        WHERE song_id = ?`
    )
    .bind(lineId, songId, lineId, songId);
}

export async function handleLyricLikes(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;

  const match = path.match(/^\/songs\/([^/]+)\/lyric-likes\/([^/]+)$/);
  if (!match || (request.method !== "PUT" && request.method !== "DELETE")) return null;

  const authUser = await getAuthUser(request, env);
  if (!authUser) return error("Unauthorized", 401);
  const inactive = await requireActiveUser(ctx, authUser);
  if (inactive) return inactive;

  const songId = decodePathParam(ctx, match[1], "song_id");
  if (songId instanceof Response) return songId;
  if (!songId || songId.length > 200) return error("invalid song_id", 400);
  const lineId = decodePathParam(ctx, match[2], "line_id");
  if (lineId instanceof Response) return lineId;
  if (!lineId || !LINE_ID.test(lineId)) return error("invalid line_id", 400);

  const header = await env.DB.prepare("SELECT status, lines_json FROM song_lyrics WHERE song_id = ?")
    .bind(songId)
    .first<{ status: string; lines_json: string | null }>();
  if (!header || header.status !== "published") return error("lyrics not found", 404);
  if (!parseLines(header.lines_json).some((l) => l.id === lineId)) return error("line not found", 404);

  const rl = await checkRateLimit(env.DB, authUser.uid, "lyric_like");
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const liked = request.method === "PUT";
  const write = liked
    ? env.DB.prepare(
        "INSERT OR IGNORE INTO lyric_line_likes (song_id, line_id, user_id) VALUES (?, ?, ?)"
      ).bind(songId, lineId, authUser.uid)
    : env.DB.prepare(
        "DELETE FROM lyric_line_likes WHERE song_id = ? AND line_id = ? AND user_id = ?"
      ).bind(songId, lineId, authUser.uid);
  await env.DB.batch([write, recountStatement(env.DB, songId, lineId)]);

  const after = await env.DB.prepare("SELECT likes_json FROM song_lyrics WHERE song_id = ?")
    .bind(songId)
    .first<{ likes_json: string | null }>();
  const count = parseLikeCounts(after?.likes_json ?? null)[lineId] ?? 0;
  return json({ songId, lineId, liked, likeCount: count }, 200, NO_STORE);
}

/**
 * 退会時に本人の「ここ好き」を消して人数を数え直す文 (DELETE /users/me の batch に入れる)。
 * 数え直しは「本人以外」で数えるので、行を消す文より前に置いてよい。
 */
export function lyricLikesAccountDeletionStatements(db: D1Database, uid: string): D1PreparedStatement[] {
  return [
    db
      .prepare(
        `UPDATE song_lyrics
            SET likes_json = COALESCE((
              SELECT json_group_object(line_id, c) FROM (
                SELECT line_id, COUNT(*) AS c FROM lyric_line_likes
                 WHERE song_id = song_lyrics.song_id AND user_id != ?
                 GROUP BY line_id)), '{}')
          WHERE song_id IN (SELECT DISTINCT song_id FROM lyric_line_likes WHERE user_id = ?)`
      )
      .bind(uid, uid),
    db.prepare("DELETE FROM lyric_line_likes WHERE user_id = ?").bind(uid),
  ];
}
