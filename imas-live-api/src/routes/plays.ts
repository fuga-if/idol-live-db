// routes/plays.ts — 曲の再生回数 (試聴 / フル再生) と、みんなの集計の全曲の数。
//
//   POST /plays/batch          端末が貯めた回数をまとめて足す (1 時間に 1 回、端末ごとに 1 日の回数を制限)
//   GET  /community/song-stats 全曲のお気に入り・再生回数 (並べ方・ブランドの絞り込みは端末のコア)
//
// 曲名・ブランドは返さない (D1 に曲マスタは無い。端末のマスタが song_id から解決する)。
// 数の規則 (何秒で 1 回か・送る間隔・順位の出し方) は imas-core の play_counts.rs /
// community_ranking.rs が正。ここは足すのと、素の数を返すだけ。

import { checkRateLimit, commitIpRateLimit } from "../rate_limit";
import { validateOpaqueKey } from "../validation";
import type { RouteContext } from "./context";
import { readJsonBody, requireDeviceWrite } from "./guards";

/** 再生回数を数え始めた日 (画面の「○月○日から集計」)。 */
export const PLAYS_SINCE = "2026-10-20";

/** 1 回に受け付ける曲数 (imas-core play_counts::MAX_BATCH_SONGS と同じ)。 */
export const MAX_BATCH_SONGS = 500;

/** 1 曲・1 回の送信で受け付ける回数の上限 (壊れた値で桁あふれさせないための形の検査)。 */
const MAX_COUNT_PER_ENTRY = 100_000;

/** 全曲の数はエッジで 30 分持つ (端末からの通信ごとに D1 を読まない)。 */
export const SONG_STATS_CACHE_HEADERS: Record<string, string> = {
  "Cache-Control": "public, max-age=1800, stale-while-revalidate=3600",
};

const JST_OFFSET_MS = 9 * 3600 * 1000;

/** `nowMs` の JST の週の月曜 (`yyyy-MM-dd`)。imas-core community_ranking::week_of と同じ。 */
export function jstWeekOf(nowMs: number): string {
  const jst = new Date(nowMs + JST_OFFSET_MS);
  const daysFromMonday = (jst.getUTCDay() + 6) % 7;
  jst.setUTCDate(jst.getUTCDate() - daysFromMonday);
  return jst.toISOString().slice(0, 10);
}

function weekBefore(week: string): string {
  const d = new Date(`${week}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 7);
  return d.toISOString().slice(0, 10);
}

// 週が変わっていたら今週の数を前の週へ送ってから足す。SET の右辺はどれも更新前の行を読む。
const UPSERT_PLAYS_SQL = `
INSERT INTO song_play_counts
  (song_id, preview_count, full_count, week, week_preview, week_full, prev_week_preview, prev_week_full)
VALUES (?1, ?2, ?3, ?4, ?2, ?3, 0, 0)
ON CONFLICT(song_id) DO UPDATE SET
  preview_count = preview_count + excluded.preview_count,
  full_count = full_count + excluded.full_count,
  prev_week_preview = CASE WHEN week = excluded.week THEN prev_week_preview
                           WHEN week = ?5 THEN week_preview ELSE 0 END,
  prev_week_full = CASE WHEN week = excluded.week THEN prev_week_full
                        WHEN week = ?5 THEN week_full ELSE 0 END,
  week_preview = CASE WHEN week = excluded.week THEN week_preview + excluded.week_preview
                      ELSE excluded.week_preview END,
  week_full = CASE WHEN week = excluded.week THEN week_full + excluded.week_full
                   ELSE excluded.week_full END,
  week = excluded.week`;

function isCount(v: unknown): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= MAX_COUNT_PER_ENTRY;
}

/** 1 曲の数 (曲詳細の束ね用)。 */
export async function fetchSongCounts(
  db: D1Database,
  songId: string
): Promise<{ favorites: number; preview: number; full: number; plays_since: string }> {
  const [fav, plays] = await Promise.all([
    db.prepare("SELECT count FROM song_favorites WHERE song_id = ?").bind(songId).first<{ count: number }>(),
    db
      .prepare("SELECT preview_count, full_count FROM song_play_counts WHERE song_id = ?")
      .bind(songId)
      .first<{ preview_count: number; full_count: number }>(),
  ]);
  return {
    favorites: fav?.count ?? 0,
    preview: plays?.preview_count ?? 0,
    full: plays?.full_count ?? 0,
    plays_since: PLAYS_SINCE,
  };
}

export async function handlePlays(ctx: RouteContext): Promise<Response | null> {
  const { request, env, path, json, error } = ctx;

  if (path === "/plays/batch" && request.method === "POST") {
    const guard = await requireDeviceWrite(ctx);
    if (guard instanceof Response) return guard;
    const { deviceId, ipQuota } = guard;

    const body = await readJsonBody(ctx);
    if (body instanceof Response) return body;
    const { plays } = body;
    if (!Array.isArray(plays) || plays.length === 0) return error("plays must be a non-empty array");
    if (plays.length > MAX_BATCH_SONGS) return error(`plays must be ${MAX_BATCH_SONGS} items or less`);

    const merged = new Map<string, { preview: number; full: number }>();
    for (const item of plays) {
      const entry = (typeof item === "object" && item !== null ? item : {}) as Record<string, unknown>;
      const invalid = validateOpaqueKey(entry.song_id, "song_id");
      if (invalid !== null || typeof entry.song_id !== "string") return error(invalid ?? "song_id is required");
      const preview = entry.preview ?? 0;
      const full = entry.full ?? 0;
      if (!isCount(preview) || !isCount(full)) return error("preview and full must be non-negative integers");
      const prev = merged.get(entry.song_id) ?? { preview: 0, full: 0 };
      merged.set(entry.song_id, { preview: prev.preview + preview, full: prev.full + full });
    }

    // 端末ごとの 1 日の送信回数 (端末は 1 時間に 1 回しか送らないので、普通は当たらない)。
    const rl = await checkRateLimit(env.DB, `device:${deviceId}`, "play_batch");
    if (!rl.allowed) return ctx.rateLimitResponse(rl.used, rl.limit, rl.reset_at);

    const week = jstWeekOf(Date.now());
    const prevWeek = weekBefore(week);
    const stmts = [...merged]
      .filter(([, c]) => c.preview > 0 || c.full > 0)
      .map(([songId, c]) => env.DB.prepare(UPSERT_PLAYS_SQL).bind(songId, c.preview, c.full, week, prevWeek));
    if (stmts.length > 0) await env.DB.batch(stmts);

    await commitIpRateLimit(env.DB, ipQuota);
    return json({ accepted: stmts.length });
  }

  if (path === "/community/song-stats" && request.method === "GET") {
    const [plays, favorites] = await Promise.all([
      env.DB.prepare(
        `SELECT song_id, preview_count, full_count, week, week_preview, week_full,
                prev_week_preview, prev_week_full FROM song_play_counts`
      ).all<{
        song_id: string;
        preview_count: number;
        full_count: number;
        week: string;
        week_preview: number;
        week_full: number;
        prev_week_preview: number;
        prev_week_full: number;
      }>(),
      env.DB.prepare("SELECT song_id, count FROM song_favorites WHERE count > 0").all<{
        song_id: string;
        count: number;
      }>(),
    ]);
    const songs = new Map<string, Record<string, number | string>>();
    for (const p of plays.results) {
      songs.set(p.song_id, {
        song_id: p.song_id,
        favorites: 0,
        preview: p.preview_count,
        full: p.full_count,
        week: p.week,
        week_preview: p.week_preview,
        week_full: p.week_full,
        prev_week_preview: p.prev_week_preview,
        prev_week_full: p.prev_week_full,
      });
    }
    for (const f of favorites.results) {
      const s = songs.get(f.song_id);
      if (s) s.favorites = f.count;
      else songs.set(f.song_id, { song_id: f.song_id, favorites: f.count, preview: 0, full: 0 });
    }
    return json(
      {
        generated_at: Math.floor(Date.now() / 1000),
        plays_since: PLAYS_SINCE,
        songs: [...songs.values()],
      },
      200,
      SONG_STATS_CACHE_HEADERS
    );
  }

  return null;
}
