// discord_live_threads.ts — その日の公演ごとに、Discord の #ライブ実況・感想 にスレッドを立てる。
//
// 日次 cron (15:17 UTC = 00:17 JST) から呼ぶ。今日 (JST) の日付の Show を CloudKit から引き
// (Show.date は QUERYABLE)、公演ごとに公開スレッドを作って最初の投稿に公演ページのリンクを置く。
// 同じ日に 2 回立てないよう、立て終えた日付 (YYYYMMDD) を discord_digest_cursors の
// source = 'live_threads' に持つ。途中で失敗したらその日の分は次の cron では再試行しない
// (重複スレッドの方が困るため。失敗はログに残る)。

import { cloudKitQuery } from "./cloudkit";
import type { Env } from "./env";

const WEB_BASE = "https://idollivedb.fugaapp.site";
const DISCORD_API = "https://discord.com/api/v10";
const CURSOR = "live_threads";
/** 1 日に立てるスレッドの上限 (フェス等で公演が多い日の暴走よけ)。 */
const THREAD_LIMIT = 10;

type LiveEnv = Pick<Env, "DB"> & Partial<Env>;

interface TodayShow {
  id: string;
  name: string;
  startTime: string | null;
  venue: string | null;
  sortOrder: number;
}

/** JST の今日を "YYYY-MM-DD" で。 */
export function jstToday(now = Date.now()): string {
  return new Date(now + 9 * 3600 * 1000).toISOString().slice(0, 10);
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

export async function createLiveThreads(env: LiveEnv, now = Date.now()): Promise<void> {
  const channelId = env.DISCORD_LIVE_CHANNEL_ID;
  if (!env.DISCORD_BOT_TOKEN || !channelId || !env.CLOUDKIT_KEY_ID || !env.CLOUDKIT_PRIVATE_KEY) return;

  const today = jstToday(now);
  const dayKey = Number(today.replaceAll("-", ""));
  const done = await env.DB.prepare("SELECT last_rowid FROM discord_digest_cursors WHERE source = ?")
    .bind(CURSOR)
    .first<{ last_rowid: number }>();
  if (done && Number(done.last_rowid) >= dayKey) return;

  const res = await cloudKitQuery("Show", "date", today, env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
  if (!res.ok) throw new Error(`live threads: ${res.error}`);

  const shows: TodayShow[] = (res.records ?? [])
    .map((r) => ({
      id: r.recordName,
      name: str(r.fields.name?.value) ?? "",
      startTime: str(r.fields.startTime?.value),
      venue: str(r.fields.venue?.value),
      sortOrder: Number(r.fields.sortOrder?.value ?? 0),
    }))
    .filter((s) => s.name)
    .sort((a, b) => (a.startTime ?? "").localeCompare(b.startTime ?? "") || a.sortOrder - b.sortOrder)
    .slice(0, THREAD_LIMIT);

  // 先に「この日は済み」を書く。途中で落ちても同じ日に二重に立てない。
  await env.DB.prepare(
    `INSERT INTO discord_digest_cursors (source, last_rowid) VALUES (?, ?)
     ON CONFLICT(source) DO UPDATE SET last_rowid = excluded.last_rowid`
  )
    .bind(CURSOR, dayKey)
    .run();

  const headers = { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, "Content-Type": "application/json" };
  const [, m, d] = today.split("-").map(Number);
  for (const show of shows) {
    const title = `${m}/${d} ${show.name}`.slice(0, 100);
    const thread = await fetch(`${DISCORD_API}/channels/${channelId}/threads`, {
      method: "POST",
      headers,
      body: JSON.stringify({ name: title, type: 11, auto_archive_duration: 4320 }),
    });
    if (!thread.ok) throw new Error(`live threads: create ${thread.status}`);
    const { id } = (await thread.json()) as { id: string };
    const facts = [show.startTime ? `開演 ${show.startTime}` : null, show.venue].filter(Boolean).join("　");
    await fetch(`${DISCORD_API}/channels/${id}/messages`, {
      method: "POST",
      headers,
      body: JSON.stringify({
        content:
          `🎤 **${show.name}** の実況・感想スレッドです。${facts ? `\n${facts}` : ""}\n` +
          `セトリはこちら: <${WEB_BASE}/shows/${encodeURIComponent(show.id)}/>\n` +
          `配信・円盤前のネタバレは時期を守ってください。`,
        allowed_mentions: { parse: [] },
      }),
    });
  }
}
