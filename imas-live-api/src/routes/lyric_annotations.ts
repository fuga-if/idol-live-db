// routes/lyric_annotations.ts — コールガイド・歌詞のタイミング・パート分けがある曲の id を全件、ページで返す
// (GET /lyrics/annotations?after=<song_id>&limit=<n>)。
//
// アプリは一度全件を取って端末に「この曲はコールあり / タイミングあり」の印として覚え、
// 曲一覧の絞り込みはその印で行う (絞り込みのたびに通信しない)。時々取り直す。
//
// ⚠️ 返すのは曲 id と 3 つの真偽だけ。歌詞本文・コール本文・時刻を足さないこと
//    (認証不要・エッジキャッシュに載る口なので、足すと断片が共有キャッシュに載る)。
//
// ページは song_id の昇順で `after` の次から。`next` が null なら最後のページ。
// キャッシュキーは URL なので、ページごとにエッジに載る (max-age=600)。

import type { RouteContext } from "./context";

export const ANNOTATIONS_DEFAULT_LIMIT = 1000;
export const ANNOTATIONS_MAX_LIMIT = 2000;

export async function handleLyricAnnotations(ctx: RouteContext): Promise<Response | null> {
  const { request, env, url, path, json, error } = ctx;
  if (path !== "/lyrics/annotations" || request.method !== "GET") return null;

  const after = url.searchParams.get("after") ?? "";
  if (after.length > 200) return error("after too long", 400);
  const rawLimit = Number(url.searchParams.get("limit") ?? ANNOTATIONS_DEFAULT_LIMIT);
  if (!Number.isInteger(rawLimit) || rawLimit < 1) return error("limit must be a positive integer", 400);
  const limit = Math.min(rawLimit, ANNOTATIONS_MAX_LIMIT);

  // 1 件多く読んで、次のページがあるかを知る。
  const rows = await env.DB.prepare(
    `SELECT song_id, MAX(c) AS calls, MAX(t) AS timings, MAX(p) AS parts FROM (
        SELECT song_id, 1 AS c, 0 AS t, 0 AS p FROM song_call_stats WHERE call_lines > 0
        UNION ALL
        SELECT song_id, 0 AS c, 1 AS t, 0 AS p FROM song_timing_stats WHERE timed_lines > 0
        UNION ALL
        SELECT song_id, 0 AS c, 0 AS t, 1 AS p FROM song_part_stats WHERE part_lines > 0
      )
      WHERE song_id > ?
      GROUP BY song_id
      ORDER BY song_id
      LIMIT ?`
  )
    .bind(after, limit + 1)
    .all<{ song_id: string; calls: number; timings: number; parts: number }>();
  const all = rows.results ?? [];
  const page = all.slice(0, limit);
  return json(
    {
      songs: page.map((r) => ({
        songId: r.song_id, calls: r.calls === 1, timings: r.timings === 1, parts: r.parts === 1,
      })),
      next: all.length > limit ? page[page.length - 1].song_id : null,
    },
    200,
    { "Cache-Control": "public, max-age=600" }
  );
}
