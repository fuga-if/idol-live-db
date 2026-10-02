// routes/timings.ts — 歌詞行の再生位置の保存 (PUT /songs/:song_id/timings)。
//
// 読み出し口は作らない。再生位置は歌詞行の startMs として、既存の GET /songs/:id/lyrics と
// GET /songs/:id/detail の応答にそのまま乗る (buildLyricsPayload)。
//
// ⚠️ この経路で歌詞本文は書き換えられない。ボディは行 ID と startMs だけで、本文は
//    D1 の既存行が唯一の正。コール (routes/calls.ts) と同じく、ログインしていれば誰でも書ける。
//
// ⚠️ 応答に歌詞本文を返さない (行 ID と startMs だけ)。本文を返すと歌詞の読み取りとして
//    数える必要が出るうえ、クライアントは手元に本文を持っているので要らない。

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import { validateTimingsBody } from "../lyrics_timings";
import { parseLines, NO_STORE } from "./lyrics";
import type { LyricLineRow } from "./lyrics";
import type { RouteContext } from "./context";
import { decodePathParam, requireActiveUser } from "./guards";

export async function handleLyricsTimings(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;

  const match = path.match(/^\/songs\/([^/]+)\/timings$/);
  if (!match || request.method !== "PUT") return null;

  const authUser = await getAuthUser(request, env);
  if (!authUser) return error("Unauthorized", 401);
  const inactive = await requireActiveUser(ctx, authUser);
  if (inactive) return inactive;

  const songId = decodePathParam(ctx, match[1], "song_id");
  if (songId instanceof Response) return songId;
  if (!songId || songId.length > 200) return error("invalid song_id", 400);

  const header = await env.DB.prepare(
    "SELECT status, lines_json FROM song_lyrics WHERE song_id = ?"
  )
    .bind(songId)
    .first<{ status: string; lines_json: string | null }>();
  // 未公開 (draft) は歌詞の無い曲と同じ扱い (GET と同じ規則)。
  if (!header || header.status !== "published") return error("lyrics not found", 404);

  const existing = parseLines(header.lines_json);
  const body = await request.json().catch(() => null);
  const callIds = new Set(existing.flatMap((l) => (l.calls ?? []).map((c) => c.id)));
  const result = validateTimingsBody(body, new Set(existing.map((l) => l.id)), callIds);
  if (!result.ok) return error(result.error, 400);

  // コール・タグ・マスタ編集と共有の "edit" 枠。検証を済ませてから消費する。
  const rl = await checkRateLimit(env.DB, authUser.uid, "edit");
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const nextLines: LyricLineRow[] = existing.map((line) => {
    // migration 0027 が書いた行はキーが startMs。新しい値は start_ms に寄せ、古いキーは落とす
    // (残すと buildLyricsPayload の `start_ms ?? startMs` で null に戻したつもりの値が蘇る)。
    const { startMs: _legacy, ...rest } = line;
    const calls = result.callTimings
      ? (line.calls ?? []).map((call) => {
          // ボディに無いコールは記録なしに戻す (行と同じく全置換)。
          const { startMs: _old, ...callRest } = call;
          const ms = result.callTimings!.get(call.id) ?? null;
          return ms === null ? callRest : { ...callRest, startMs: ms };
        })
      : line.calls;
    // 被せの指定はボディに layer があった行だけ書き換える (古いアプリは送らない)。
    const { layer: oldLayer, ...base } = rest;
    const layer = result.layers.has(line.id) ? result.layers.get(line.id) : oldLayer;
    return {
      ...base,
      start_ms: result.timings.get(line.id) ?? null,
      ...(layer ? { layer } : {}),
      ...(calls ? { calls } : {}),
    };
  });
  const nextJson = JSON.stringify(nextLines);
  if (nextJson !== header.lines_json) {
    // updated_at は動かさない。歌詞の更新時刻は本文・コールの変化を表す。
    await env.DB.prepare("UPDATE song_lyrics SET lines_json = ? WHERE song_id = ?")
      .bind(nextJson, songId)
      .run();
  }

  return json(
    {
      songId,
      lines: nextLines.map((l) => ({ id: l.id, startMs: l.start_ms })),
      calls: nextLines.flatMap((l) => (l.calls ?? []).map((c) => ({ id: c.id, startMs: c.startMs ?? null }))),
    },
    200,
    NO_STORE
  );
}
