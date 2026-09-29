// discord_releases.ts — アプリのリリースと開発中の変更を Discord に出す。
//
// postAppRelease (5 分 cron): App Store の公開情報 (iTunes lookup) を見て、新しいバージョンが
//   出ていたらバージョンと「新機能」の文面を #お知らせ に投稿して公開 (crosspost) する。
//   位置は discord_digest_cursors の source = 'app_release' に currentVersionReleaseDate (UNIX 秒)。
//   位置が無ければ今のバージョンを覚えるだけ (過去のリリースは流さない)。
//
// postDevWeekly (日次 cron): JST の月曜だけ、直近 7 日に develop に入ったコミットのうち
//   利用者に関係するもの (feat / fix / perf と Web の変更) を場所ごとにまとめて #開発中 に投稿する。
//   GitHub API は OAuth App の client_id / secret で認証する (Cloudflare の共有 IP で
//   未認証の 60 回/時の枠を食い合わないように)。同じ日に 2 回出さないよう source = 'dev_weekly'
//   に日付 (YYYYMMDD) を持つ。

import { jstToday } from "./discord_live_threads";
import type { Env } from "./env";

const DISCORD_API = "https://discord.com/api/v10";
const APP_STORE_ID = "6763342297";
const REPO = "fuga-if/idol-live-db";
const RELEASE_COLOR = 0x5865f2;
const DEV_COLOR = 0x2fb7e6;
/** 場所ごとに並べるコミットの上限。 */
const PER_AREA = 6;

type RelEnv = Pick<Env, "DB"> & Partial<Env>;

async function cursor(env: RelEnv, source: string): Promise<number | null> {
  const row = await env.DB.prepare("SELECT last_rowid FROM discord_digest_cursors WHERE source = ?")
    .bind(source)
    .first<{ last_rowid: number }>();
  return row ? Number(row.last_rowid) : null;
}

async function setCursor(env: RelEnv, source: string, value: number): Promise<void> {
  await env.DB.prepare(
    `INSERT INTO discord_digest_cursors (source, last_rowid) VALUES (?, ?)
     ON CONFLICT(source) DO UPDATE SET last_rowid = excluded.last_rowid`
  )
    .bind(source, value)
    .run();
}

function botHeaders(env: RelEnv): Record<string, string> {
  return { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}`, "Content-Type": "application/json" };
}

/** 投稿してアナウンスチャンネルで公開する。投稿に失敗したら false。 */
async function postAndPublish(env: RelEnv, channelId: string, message: unknown): Promise<boolean> {
  const res = await fetch(`${DISCORD_API}/channels/${channelId}/messages`, {
    method: "POST",
    headers: botHeaders(env),
    body: JSON.stringify(message),
  });
  if (!res.ok) return false;
  const { id } = (await res.json().catch(() => ({}))) as { id?: string };
  if (id) {
    await fetch(`${DISCORD_API}/channels/${channelId}/messages/${id}/crosspost`, {
      method: "POST",
      headers: botHeaders(env),
    }).catch(() => undefined);
  }
  return true;
}

// ---------------------------------------------------------------------------
// App Store のリリース → #お知らせ
// ---------------------------------------------------------------------------

interface ItunesApp {
  version?: string;
  releaseNotes?: string;
  currentVersionReleaseDate?: string;
  trackViewUrl?: string;
  artworkUrl512?: string;
}

export async function postAppRelease(env: RelEnv): Promise<void> {
  const channelId = env.DISCORD_ANNOUNCE_CHANNEL_ID;
  if (!env.DISCORD_BOT_TOKEN || !channelId) return;

  // App Store 側の一時的な失敗は次の回に (5 分ごとなので、ここでは投げない)。
  const res = await fetch(`https://itunes.apple.com/lookup?id=${APP_STORE_ID}&country=jp`, {
    cf: { cacheTtl: 300 },
  } as RequestInit).catch(() => null);
  if (!res?.ok) return;
  const app = ((await res.json().catch(() => ({}))) as { results?: ItunesApp[] }).results?.[0];
  const released = app?.currentVersionReleaseDate ? Math.floor(Date.parse(app.currentVersionReleaseDate) / 1000) : NaN;
  if (!app?.version || !Number.isFinite(released)) return;

  const last = await cursor(env, "app_release");
  if (last === null) {
    await setCursor(env, "app_release", released);
    return;
  }
  if (released <= last) return;

  const notes = (app.releaseNotes ?? "").trim();
  const ok = await postAndPublish(env, channelId, {
    allowed_mentions: { parse: [] },
    embeds: [
      {
        title: `📱 iPhone 版 ${app.version} を公開しました`,
        ...(app.trackViewUrl ? { url: app.trackViewUrl } : {}),
        description: (notes || "App Store からアップデートできます。").slice(0, 4000),
        color: RELEASE_COLOR,
        ...(app.artworkUrl512 ? { thumbnail: { url: app.artworkUrl512 } } : {}),
      },
    ],
  });
  if (ok) await setCursor(env, "app_release", released);
}

// ---------------------------------------------------------------------------
// develop に入った変更 → #開発中 (毎週月曜)
// ---------------------------------------------------------------------------

const AREAS: Array<[string, RegExp]> = [
  ["📱 iPhone", /^(feat|fix|perf)\(ios\)/i],
  ["🤖 Android", /^(feat|fix|perf)\(android\)/i],
  ["🌐 Web", /^(web|(feat|fix|perf)\(web\))/i],
  ["☁️ サーバー", /^(worker|api|(feat|fix|perf)\((worker|api)\))/i],
  ["🧩 アプリ共通", /^(feat|fix|perf)(\(core\))?[:：!]/i],
];

/** コミットの 1 行目から、利用者向けの場所と本文を取り出す。対象外なら null。 */
export function classifyCommit(subject: string): { area: string; text: string } | null {
  if (/^Merge /.test(subject)) return null;
  for (const [area, re] of AREAS) {
    if (re.test(subject)) {
      const text = subject.replace(/^[^:：]{1,24}[:：]\s*/, "").trim();
      return text ? { area, text } : null;
    }
  }
  return null;
}

export async function postDevWeekly(env: RelEnv, now = Date.now()): Promise<void> {
  const channelId = env.DISCORD_DEV_CHANNEL_ID;
  if (!env.DISCORD_BOT_TOKEN || !channelId) return;
  const today = jstToday(now);
  if (new Date(`${today}T00:00:00Z`).getUTCDay() !== 1) return; // 月曜だけ
  const dayKey = Number(today.replaceAll("-", ""));
  const last = await cursor(env, "dev_weekly");
  if (last !== null && last >= dayKey) return;

  const headers: Record<string, string> = {
    Accept: "application/vnd.github+json",
    "User-Agent": "imas-live-api",
  };
  if (env.GITHUB_OAUTH_CLIENT_ID && env.GITHUB_OAUTH_CLIENT_SECRET) {
    headers.Authorization = `Basic ${btoa(`${env.GITHUB_OAUTH_CLIENT_ID}:${env.GITHUB_OAUTH_CLIENT_SECRET}`)}`;
  }
  const since = new Date(now - 7 * 86400 * 1000).toISOString();
  const subjects: string[] = [];
  for (let page = 1; page <= 3; page++) {
    const res = await fetch(
      `https://api.github.com/repos/${REPO}/commits?sha=develop&since=${since}&per_page=100&page=${page}`,
      { headers }
    );
    if (!res.ok) throw new Error(`dev weekly: github ${res.status}`);
    const list = (await res.json()) as Array<{ commit?: { message?: string } }>;
    for (const c of list) subjects.push((c.commit?.message ?? "").split("\n")[0]);
    if (list.length < 100) break;
  }

  const byArea = new Map<string, string[]>();
  for (const s of subjects) {
    const hit = classifyCommit(s);
    if (!hit) continue;
    const list = byArea.get(hit.area) ?? [];
    if (!list.includes(hit.text)) list.push(hit.text);
    byArea.set(hit.area, list);
  }
  await setCursor(env, "dev_weekly", dayKey);
  if (byArea.size === 0) return;

  const fields = AREAS.map(([area]) => area)
    .filter((area) => byArea.has(area))
    .map((area) => {
      const items = byArea.get(area)!;
      const lines = items.slice(0, PER_AREA).map((t) => `・${t.length > 80 ? `${t.slice(0, 80)}…` : t}`);
      if (items.length > PER_AREA) lines.push(`ほか${items.length - PER_AREA}件`);
      return { name: `${area}（${items.length}件）`, value: lines.join("\n").slice(0, 1024) };
    });
  await postAndPublish(env, channelId, {
    allowed_mentions: { parse: [] },
    embeds: [
      {
        title: "🚧 今週の開発（次のリリースに入る予定のもの）",
        url: `https://github.com/${REPO}/commits/develop`,
        description: "develop に入った変更のうち、使う人に関係するものです。",
        color: DEV_COLOR,
        fields,
      },
    ],
  });
}
