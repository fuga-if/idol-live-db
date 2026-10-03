// routes/parts.ts — 歌詞行のパート分け (誰が歌うか) の保存 (PUT /songs/:song_id/parts)。
//
// 行に歌唱者のアイドル id の並び (`singers`) を持たせる。lines_json の行に入り、歌詞の応答
// (buildLyricsPayload) の singers に載る。読み出し専用の口は作らない。
//
// ⚠️ 歌詞本文は書き換えられない (ボディは行 ID とアイドル id だけ)。応答にも本文を返さない。
//    コール・タイミングと同じく、ログインしていれば誰でも書ける (edit 枠)。
// ⚠️ PUT は曲全体の全置換。ボディに無い行のパートは消える。

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import { parseLines, NO_STORE } from "./lyrics";
import type { LyricLineRow } from "./lyrics";
import type { RouteContext } from "./context";
import { decodePathParam, requireActiveUser } from "./guards";

/** 1 行に付けられる歌唱者の上限 (全体曲でも 1 行に 52 人は来ない)。 */
export const MAX_SINGERS_PER_LINE = 60;
const MAX_ID_LEN = 100;

export type PartsResult = { ok: true; parts: Map<string, string[]> } | { ok: false; error: string };

/** ボディ `{ lines: [{ id, singers: [idol_id] }] }` を検証する。知らない行 id は 400。 */
export function validatePartsBody(body: unknown, knownIds: ReadonlySet<string>): PartsResult {
  if (!body || typeof body !== "object") return { ok: false, error: "body must be an object" };
  const { lines } = body as Record<string, unknown>;
  if (!Array.isArray(lines)) return { ok: false, error: "lines must be an array" };
  if (lines.length > knownIds.size) return { ok: false, error: "too many lines" };
  const parts = new Map<string, string[]>();
  for (const raw of lines) {
    if (!raw || typeof raw !== "object") return { ok: false, error: "line must be an object" };
    const { id, singers } = raw as Record<string, unknown>;
    if (typeof id !== "string" || !knownIds.has(id)) return { ok: false, error: "unknown line id" };
    if (parts.has(id)) return { ok: false, error: "duplicate line id" };
    if (!Array.isArray(singers) || singers.length > MAX_SINGERS_PER_LINE) {
      return { ok: false, error: "singers must be an array" };
    }
    const ids: string[] = [];
    for (const s of singers) {
      if (typeof s !== "string" || !s || s.length > MAX_ID_LEN || /[\u0000-\u001f]/.test(s)) {
        return { ok: false, error: "singer id is invalid" };
      }
      if (!ids.includes(s)) ids.push(s);
    }
    parts.set(id, ids);
  }
  return { ok: true, parts };
}

export async function handleLyricParts(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error, rateLimitResponse } = ctx;
  const match = path.match(/^\/songs\/([^/]+)\/parts$/);
  if (!match || request.method !== "PUT") return null;

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

  const existing = parseLines(header.lines_json);
  const result = validatePartsBody(await request.json().catch(() => null), new Set(existing.map((l) => l.id)));
  if (!result.ok) return error(result.error, 400);

  const rl = await checkRateLimit(env.DB, authUser.uid, "edit");
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const nextLines: LyricLineRow[] = existing.map((line) => {
    const { singers: _old, ...rest } = line;
    const singers = result.parts.get(line.id) ?? [];
    return singers.length ? { ...rest, singers } : rest;
  });
  const nextJson = JSON.stringify(nextLines);
  if (nextJson !== header.lines_json) {
    await env.DB.prepare("UPDATE song_lyrics SET lines_json = ? WHERE song_id = ?").bind(nextJson, songId).run();
  }
  return json({ songId, lines: nextLines.map((l) => ({ id: l.id, singers: l.singers ?? [] })) }, 200, NO_STORE);
}
