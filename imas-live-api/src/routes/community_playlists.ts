// routes/community_playlists.ts — みんなのプレイリスト (ユーザー投稿)。
//
// 端末のプレイリストを「公開する」と 1 行できる。載せるのはタイトル・ひとこと・曲 id の並びだけ。
// 曲の実在は確かめない (song_id は不透明キー。CloudKit にあって D1 に無い新曲でも入れられるように)。
// 作者名は返さない (お題と同じく、自分のものかどうかだけ)。
//
//   GET    /playlists            一覧 (新しく更新された順・公開キャッシュ)
//   GET    /playlists/:id        1 つ (公開キャッシュ)
//   GET    /me/playlists         自分が公開したもの (要ログイン)
//   POST   /playlists            公開する (要ログイン・playlist 枠)
//   PUT    /playlists/:id        中身を差し替える (作者だけ・playlist 枠)
//   DELETE /playlists/:id        取り下げる (作者かモデレーター)

import { getAuthUser } from "../auth";
import { checkRateLimit } from "../rate_limit";
import { checkIsAdmin, upsertUser } from "../users";
import { parsePositiveInt } from "../validation";
import type { RouteContext } from "./context";
import { decodePathParam, readJsonBody, requireActiveUser } from "./guards";

export const MAX_TITLE_LEN = 40;
export const MAX_DESCRIPTION_LEN = 200;
export const MAX_SONGS = 200;
const MAX_ID_LEN = 100;
/** 一覧の 1 枚に載せる曲 id (ジャケを並べる分だけ)。全曲は 1 つ取りで。 */
const PREVIEW_SONGS = 4;
/** 一覧・1 つ取りのエッジキャッシュ。公開・取り下げは数分遅れて見える。 */
const PUBLIC_CACHE = { "Cache-Control": "public, max-age=300" };

export type PlaylistInput = { title: string; description: string | null; songIds: string[] };

/** 本文 `{ title, description?, songIds }` を確かめる。曲 id の重複は先のものだけ残す。 */
export function validatePlaylistBody(body: Record<string, unknown>): { ok: true; value: PlaylistInput } | { ok: false; error: string } {
  const title = typeof body.title === "string" ? body.title.trim() : "";
  if (!title) return { ok: false, error: "title is required" };
  if ([...title].length > MAX_TITLE_LEN) return { ok: false, error: `title must be ${MAX_TITLE_LEN} characters or less` };
  let description: string | null = null;
  if (body.description !== undefined && body.description !== null) {
    if (typeof body.description !== "string") return { ok: false, error: "description must be a string" };
    const trimmed = body.description.trim();
    if ([...trimmed].length > MAX_DESCRIPTION_LEN) {
      return { ok: false, error: `description must be ${MAX_DESCRIPTION_LEN} characters or less` };
    }
    description = trimmed || null;
  }
  const raw = body.songIds ?? body.song_ids;
  if (!Array.isArray(raw) || raw.length === 0) return { ok: false, error: "songIds must be a non-empty array" };
  if (raw.length > MAX_SONGS) return { ok: false, error: `songIds must be ${MAX_SONGS} or less` };
  const songIds: string[] = [];
  for (const id of raw) {
    if (typeof id !== "string" || !id || id.length > MAX_ID_LEN || /[\u0000-\u001f]/.test(id)) {
      return { ok: false, error: "song id is invalid" };
    }
    if (!songIds.includes(id)) songIds.push(id);
  }
  return { ok: true, value: { title, description, songIds } };
}

type Row = {
  id: string;
  created_by: string;
  title: string;
  description: string | null;
  song_ids_json: string;
  song_count: number;
  created_at: string;
  updated_at: string;
};

function songIdsOf(row: Row): string[] {
  try {
    const ids = JSON.parse(row.song_ids_json);
    return Array.isArray(ids) ? ids.filter((x): x is string => typeof x === "string") : [];
  } catch {
    return [];
  }
}

function present(row: Row, opts: { full: boolean; viewer?: string }) {
  const ids = songIdsOf(row);
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    songIds: opts.full ? ids : ids.slice(0, PREVIEW_SONGS),
    songCount: row.song_count,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    ...(opts.viewer !== undefined ? { isOwn: row.created_by === opts.viewer } : {}),
  };
}

const COLUMNS = "id, created_by, title, description, song_ids_json, song_count, created_at, updated_at";

/** 1 つ取りのエッジキャッシュを捨てる (この PoP の分だけ。他は max-age で切れる)。 */
function purgeDetail(ctx: RouteContext, id: string) {
  const url = new URL(`/playlists/${encodeURIComponent(id)}`, ctx.url);
  ctx.waitUntil?.(caches.default.delete(new Request(url.toString(), { method: "GET" })));
}

export async function handleCommunityPlaylists(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, url, json, error, rateLimitResponse } = ctx;

  if (path === "/playlists" && request.method === "GET") {
    const limit = parsePositiveInt(url.searchParams.get("limit"), 30, 50);
    // 続きは「最後の行の updated_at と id」で指す (offset は後ろほど読みが増える)。
    const before = url.searchParams.get("before");
    const [beforeAt, beforeId] = before ? before.split("|") : [null, null];
    const { results } = beforeAt && beforeId
      ? await env.DB.prepare(
          `SELECT ${COLUMNS} FROM community_playlists
           WHERE status = 'active' AND (updated_at < ? OR (updated_at = ? AND id < ?))
           ORDER BY updated_at DESC, id DESC LIMIT ?`
        ).bind(beforeAt, beforeAt, beforeId, limit).all<Row>()
      : await env.DB.prepare(
          `SELECT ${COLUMNS} FROM community_playlists WHERE status = 'active'
           ORDER BY updated_at DESC, id DESC LIMIT ?`
        ).bind(limit).all<Row>();
    const rows = results ?? [];
    const last = rows[rows.length - 1];
    return json(
      {
        playlists: rows.map((r) => present(r, { full: false })),
        next: rows.length === limit && last ? `${last.updated_at}|${last.id}` : null,
      },
      200,
      PUBLIC_CACHE
    );
  }

  if (path === "/me/playlists" && request.method === "GET") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    const { results } = await env.DB.prepare(
      `SELECT ${COLUMNS} FROM community_playlists WHERE created_by = ? AND status = 'active'
       ORDER BY updated_at DESC LIMIT ?`
    ).bind(user.uid, MAX_SONGS).all<Row>();
    return json({ playlists: (results ?? []).map((r) => present(r, { full: true, viewer: user.uid })) });
  }

  if (path === "/playlists" && request.method === "POST") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    const [inactive, rl] = await Promise.all([
      requireActiveUser(ctx, user),
      checkRateLimit(env.DB, user.uid, "playlist"),
    ]);
    if (inactive) return inactive;
    if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);
    const body = await readJsonBody(ctx);
    if (body instanceof Response) return body;
    const checked = validatePlaylistBody(body);
    if (!checked.ok) return error(checked.error);
    await upsertUser(env, user.uid);
    const id = crypto.randomUUID();
    const { title, description, songIds } = checked.value;
    const created = await env.DB.prepare(
      `INSERT INTO community_playlists (id, created_by, title, description, song_ids_json, song_count)
       VALUES (?, ?, ?, ?, ?, ?) RETURNING ${COLUMNS}`
    ).bind(id, user.uid, title, description, JSON.stringify(songIds), songIds.length).first<Row>();
    return json(present(created!, { full: true, viewer: user.uid }), 201);
  }

  const match = path.match(/^\/playlists\/([^/]+)$/);
  if (!match) return null;
  const id = decodePathParam(ctx, match[1], "playlist_id");
  if (id instanceof Response) return id;

  if (request.method === "GET") {
    const row = await env.DB.prepare(
      `SELECT ${COLUMNS} FROM community_playlists WHERE id = ? AND status = 'active'`
    ).bind(id).first<Row>();
    if (!row) return error("Playlist not found", 404);
    return json(present(row, { full: true }), 200, PUBLIC_CACHE);
  }

  if (request.method === "PUT") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    const [inactive, rl] = await Promise.all([
      requireActiveUser(ctx, user),
      checkRateLimit(env.DB, user.uid, "playlist"),
    ]);
    if (inactive) return inactive;
    if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);
    const body = await readJsonBody(ctx);
    if (body instanceof Response) return body;
    const checked = validatePlaylistBody(body);
    if (!checked.ok) return error(checked.error);
    const { title, description, songIds } = checked.value;
    const updated = await env.DB.prepare(
      `UPDATE community_playlists
       SET title = ?, description = ?, song_ids_json = ?, song_count = ?, updated_at = datetime('now')
       WHERE id = ? AND created_by = ? AND status = 'active' RETURNING ${COLUMNS}`
    ).bind(title, description, JSON.stringify(songIds), songIds.length, id, user.uid).first<Row>();
    if (!updated) return error("Playlist not found", 404);
    purgeDetail(ctx, id);
    return json(present(updated, { full: true, viewer: user.uid }));
  }

  if (request.method === "DELETE") {
    const user = await getAuthUser(request, env);
    if (!user) return error("Unauthorized", 401);
    const row = await env.DB.prepare(
      "SELECT created_by FROM community_playlists WHERE id = ? AND status = 'active'"
    ).bind(id).first<{ created_by: string }>();
    if (!row) return error("Playlist not found", 404);
    if (row.created_by !== user.uid && !(await checkIsAdmin(env, user.uid))) return error("Forbidden", 403);
    await env.DB.prepare(
      "UPDATE community_playlists SET status = 'removed', updated_at = datetime('now') WHERE id = ?"
    ).bind(id).run();
    purgeDetail(ctx, id);
    return json({ id, status: "removed" });
  }

  return null;
}
