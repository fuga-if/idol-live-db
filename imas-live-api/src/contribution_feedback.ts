// contribution_feedback.ts — データを入れた人に手応えを返す仕組み。
//
//   GET  /me/feedback?since=<ms>   自分の編集に付いた Good (新着つき) と、自分が入れたセトリの先週の閲覧数
//   POST /shows/views              公演ページを見た (端末側で 1 週 1 公演 1 回に畳んだもの)
//   GET  /shows/:id/credits        公演ページ末尾の奥付 (セトリ入力・歌唱者の入力をした人の表示名)
//   POST /users/me/credit          奥付に名前を載せるか (本人のオプトイン。既定は載せない)
//
// 対象は edit_batch の source='app' (利用者がアプリから入れた編集) だけ。歌詞の投稿は
// lyric_submissions にあって edit_batch に入らないので、構造上どれにも出ない (歌詞を煽らない)。
//
// 閲覧数は端末 ID の行を持たず、(公演, 週) の人数だけを積む。重複は端末が週ごとに畳む。
// 1 端末 1 週 1 公演 = 1 行の upsert なので、書き込みは「その週に開かれた公演の数」で頭打ちになる。

import { getAuthUser } from "./auth";
import { maskDisplayName } from "./feed";
import { checkRateLimit, commitIpRateLimit } from "./rate_limit";
import type { RouteContext } from "./routes/context";
import { readJsonBody, requireActiveUser, requireDeviceId, requireIpQuota } from "./routes/guards";
import { validateOpaqueKey } from "./validation";

const DAY_MS = 86_400_000;
const JST_OFFSET_MS = 9 * 3_600_000;

/** 1 回の POST /shows/views で受ける公演の数の上限 (アプリは 1 公演ずつ送る)。 */
export const MAX_VIEW_SHOW_IDS = 3;
/** 閲覧の書き込みの IP ごとの上限。キャリアの NAT で大勢が同じ IP でも足りる幅にする。 */
const VIEW_IP_LIMITS = { perMinute: 30, perDay: 2000 };
/** Good の集計に使う、自分の編集の新しい順の上限 (古い編集まで毎回読まない)。 */
const FEEDBACK_RECENT_BATCHES = 200;
/** 奥付に並べる名前の上限 (役割ごと)。超えた分は人数だけ返す。 */
export const MAX_CREDIT_NAMES = 12;
/** Good の新着の一覧に返す編集の数。 */
const MAX_FEEDBACK_GOODS = 20;
/** 閲覧数を残す週の数 (日次 cron でこれより古い週を消す)。 */
export const SHOW_VIEW_WEEKS_KEPT = 8;

/** JST の月曜始まりの週の初日 ('YYYY-MM-DD')。 */
export function jstWeekStart(nowMs: number): string {
  const jst = new Date(nowMs + JST_OFFSET_MS);
  // getUTCDay: 0=日 … 6=土。月曜までさかのぼる日数。
  const back = (jst.getUTCDay() + 6) % 7;
  return new Date(jst.getTime() - back * DAY_MS).toISOString().slice(0, 10);
}

/** 公演 ID の形 (sh_ で始まる不透明キー)。違えば null。 */
function asShowId(v: unknown): string | null {
  if (typeof v !== "string" || validateOpaqueKey(v, "show_id") !== null) return null;
  return v.startsWith("sh_") ? v : null;
}

// ---------------------------------------------------------------------------
// GET /me/feedback
// ---------------------------------------------------------------------------

interface GoodRow {
  id: number;
  summary: string | null;
  record_type: string | null;
  record_name: string | null;
  good_count: number;
  new_good_count: number;
  latest_good_at: number;
}

export async function handleGetMyFeedback(ctx: RouteContext): Promise<Response> {
  const { request, url, env, json, error } = ctx;
  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const sinceRaw = Number(url.searchParams.get("since"));
  const since = Number.isFinite(sinceRaw) && sinceRaw > 0 ? Math.floor(sinceRaw) : 0;
  const lastWeek = jstWeekStart(Date.now() - 7 * DAY_MS);

  const [goods, reach] = await Promise.all([
    env.DB.prepare(
      `SELECT eb.id, eb.summary,
              (SELECT h.record_type FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_type,
              (SELECT h.record_name FROM edit_history h WHERE h.batch_id = eb.id ORDER BY h.id LIMIT 1) AS record_name,
              COUNT(*) AS good_count,
              SUM(CASE WHEN g.created_at > ? THEN 1 ELSE 0 END) AS new_good_count,
              MAX(g.created_at) AS latest_good_at
         FROM edit_batch eb
         JOIN edit_good g ON g.batch_id = eb.id
        WHERE eb.id IN (
                SELECT id FROM edit_batch
                 WHERE editor_id = ? AND source = 'app' AND cloudkit_ok = 1
                 ORDER BY created_at DESC LIMIT ?)
        GROUP BY eb.id
        ORDER BY latest_good_at DESC
        LIMIT ?`
    )
      .bind(since, user.uid, FEEDBACK_RECENT_BATCHES, MAX_FEEDBACK_GOODS)
      .all<GoodRow>(),
    // 自分が入れた (取り消されていない) セトリの公演の、先週の閲覧数の合計。
    // CROSS JOIN で edit_batch (editor 索引) から引かせる。普通の JOIN だと planner が
    // idx_edit_history_record (record_type だけ) から入り、全員の ShowSetlist 行を読む。
    env.DB.prepare(
      `SELECT COALESCE(SUM(v.viewers), 0) AS viewers, COUNT(*) AS shows
         FROM show_views_weekly v
        WHERE v.week = ?
          AND v.show_id IN (
            SELECT h.record_name
              FROM edit_batch eb
              CROSS JOIN edit_history h ON h.batch_id = eb.id
             WHERE eb.editor_id = ? AND eb.source = 'app' AND eb.cloudkit_ok = 1
               AND eb.reverted_at IS NULL AND h.record_type = 'ShowSetlist')`
    )
      .bind(lastWeek, user.uid)
      .first<{ viewers: number; shows: number }>(),
  ]);

  const items = (goods.results ?? []).map((r) => ({
    batchId: r.id,
    summary: r.summary,
    recordType: r.record_type,
    recordName: r.record_name,
    goodCount: Number(r.good_count) || 0,
    newGoodCount: Number(r.new_good_count) || 0,
    latestGoodAt: Number(r.latest_good_at) || 0,
  }));
  return json({
    goods: items,
    newGoodTotal: items.reduce((n, g) => n + g.newGoodCount, 0),
    setlistReach: {
      week: lastWeek,
      viewers: Number(reach?.viewers) || 0,
      shows: Number(reach?.shows) || 0,
    },
  });
}

// ---------------------------------------------------------------------------
// POST /shows/views
// ---------------------------------------------------------------------------

export async function handlePostShowViews(ctx: RouteContext): Promise<Response> {
  const { env, json, error } = ctx;
  const deviceId = requireDeviceId(ctx);
  if (deviceId instanceof Response) return deviceId;
  const ipQuota = await requireIpQuota(ctx, "community", VIEW_IP_LIMITS);
  if (ipQuota instanceof Response) return ipQuota;

  const body = await readJsonBody(ctx, "show_ids is required");
  if (body instanceof Response) return body;
  const raw = body.show_ids ?? body.showIds;
  if (!Array.isArray(raw) || raw.length === 0) return error("show_ids is required");
  if (raw.length > MAX_VIEW_SHOW_IDS) return error(`show_ids too many (max ${MAX_VIEW_SHOW_IDS})`);
  const ids = new Set<string>();
  for (const v of raw) {
    const id = asShowId(v);
    if (!id) return error("invalid show_id");
    ids.add(id);
  }

  const week = jstWeekStart(Date.now());
  await env.DB.batch(
    [...ids].map((id) =>
      env.DB.prepare(
        `INSERT INTO show_views_weekly (week, show_id, viewers) VALUES (?, ?, 1)
           ON CONFLICT (week, show_id) DO UPDATE SET viewers = viewers + 1`
      ).bind(week, id)
    )
  );
  await commitIpRateLimit(env.DB, ipQuota);
  return json({ ok: true, week, counted: ids.size });
}

// ---------------------------------------------------------------------------
// GET /shows/:id/credits
// ---------------------------------------------------------------------------

interface CreditRow {
  name: string | null;
  opt_in: number;
  banned: number;
  first_at: number;
  did_items: number;
  did_performers: number;
}

interface CreditRole {
  /** 載せてよい人の表示名 (最初に入れた順)。 */
  names: string[];
  /** この役割に関わった人の総数 (名前を出さない人も含む)。 */
  total: number;
}

/** BAN した人は名前も人数も出さない。 */
function toRole(rows: CreditRow[]): CreditRole {
  const active = rows.filter((r) => r.banned === 0);
  const names = active
    .filter((r) => r.opt_in === 1 && r.name)
    .map((r) => maskDisplayName(r.name))
    .slice(0, MAX_CREDIT_NAMES);
  return { names, total: active.length };
}

export async function handleGetShowCredits(ctx: RouteContext, showIdRaw: string): Promise<Response> {
  const { env, json, error } = ctx;
  const showId = asShowId(showIdRaw);
  if (!showId) return error("invalid show_id");

  // セトリの編集は必ず ShowSetlist (record_name = 公演 ID) の行を持つ (edits.ts の不変条件)。
  // idx_edit_history_record で公演の行だけを引き、同じ batch に曲 (SetlistItem) と
  // 歌唱者 (SetlistPerformer) のどちらの操作があったかで役割を分ける。
  const { results } = await env.DB.prepare(
    `SELECT u.display_name AS name,
            COALESCE(u.credit_opt_in, 0) AS opt_in,
            COALESCE(u.is_banned, 0) AS banned,
            MIN(eb.created_at) AS first_at,
            MAX(EXISTS (SELECT 1 FROM edit_history i WHERE i.batch_id = eb.id AND i.record_type = 'SetlistItem')) AS did_items,
            MAX(EXISTS (SELECT 1 FROM edit_history p WHERE p.batch_id = eb.id AND p.record_type = 'SetlistPerformer')) AS did_performers
       FROM edit_history h
       JOIN edit_batch eb ON eb.id = h.batch_id
       JOIN users u ON u.id = eb.editor_id
      WHERE h.record_type = 'ShowSetlist' AND h.record_name = ?
        AND eb.source = 'app' AND eb.cloudkit_ok = 1 AND eb.reverted_at IS NULL
      GROUP BY eb.editor_id
      ORDER BY first_at`
  )
    .bind(showId)
    .all<CreditRow>();

  const rows = (results ?? []).map((r) => ({
    ...r,
    opt_in: Number(r.opt_in),
    banned: Number(r.banned),
  }));
  return json(
    {
      showId,
      setlist: toRole(rows.filter((r) => Number(r.did_items) === 1)),
      performers: toRole(rows.filter((r) => Number(r.did_performers) === 1)),
    },
    200,
    // 公演ページを開くたびに来るのでエッジで賄う。名前の出し入れ・BAN は最大 10 分遅れて反映される。
    { "Cache-Control": "public, max-age=600" }
  );
}

// ---------------------------------------------------------------------------
// POST /users/me/credit
// ---------------------------------------------------------------------------

export async function handlePostCreditOptIn(ctx: RouteContext): Promise<Response> {
  const { request, env, json, error, rateLimitResponse } = ctx;
  const user = await getAuthUser(request, env);
  if (!user) return error("Unauthorized", 401);

  const body = await readJsonBody(ctx, "credit_opt_in is required");
  if (body instanceof Response) return body;
  const raw = body.credit_opt_in ?? body.creditOptIn;
  if (typeof raw !== "boolean") return error("credit_opt_in must be boolean");

  const [inactive, rl] = await Promise.all([
    requireActiveUser(ctx, user),
    checkRateLimit(env.DB, user.uid, "credit"),
  ]);
  if (inactive) return inactive;
  if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

  const updated = await env.DB.prepare("UPDATE users SET credit_opt_in = ? WHERE id = ?")
    .bind(raw ? 1 : 0, user.uid)
    .run();
  if (!updated.meta.changes) return error("user not found", 404);
  return json({ creditOptIn: raw });
}
