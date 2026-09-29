// discord.ts — Discord (と GitHub OAuth) の API 呼び出しと、署名の検証。
//
// Bot の操作 (メンバー追加・ロール付与・メッセージ投稿) は Bot トークン、
// 本人確認は OAuth のアクセストークンで行う。常駐する Bot (Gateway 接続) は持たない:
// スラッシュコマンドは Interactions Endpoint (HTTP) で受け、通知は cron から REST で投げる。

import type { Env } from "./env";

const DISCORD_API = "https://discord.com/api/v10";

/** ロール受け取りに要る値が全部そろっているか。欠けていれば口ごと 503 にする。 */
export function isDiscordLinkConfigured(env: Env): boolean {
  return !!(
    env.DISCORD_APPLICATION_ID &&
    env.DISCORD_CLIENT_SECRET &&
    env.DISCORD_BOT_TOKEN &&
    env.DISCORD_GUILD_ID &&
    env.DISCORD_DATA_ROLE_ID
  );
}

export function isGithubLinkConfigured(env: Env): boolean {
  return !!(
    env.GITHUB_OAUTH_CLIENT_ID &&
    env.GITHUB_OAUTH_CLIENT_SECRET &&
    env.DISCORD_BOT_TOKEN &&
    env.DISCORD_GUILD_ID &&
    env.DISCORD_CONTRIBUTOR_ROLE_ID
  );
}

/** OAuth の state。推測できない 32 バイトを base64url で。 */
export function randomState(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function botHeaders(env: Env, json = false): Record<string, string> {
  const h: Record<string, string> = { Authorization: `Bot ${env.DISCORD_BOT_TOKEN}` };
  if (json) h["Content-Type"] = "application/json";
  return h;
}

/** 認可コードをアクセストークンに換える。失敗は null。 */
export async function exchangeDiscordCode(env: Env, code: string, redirectUri: string): Promise<string | null> {
  const res = await fetch(`${DISCORD_API}/oauth2/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectUri,
      client_id: env.DISCORD_APPLICATION_ID!,
      client_secret: env.DISCORD_CLIENT_SECRET!,
    }),
  });
  // GitHub は失敗も 200 + { error } で返す (シークレット違いは incorrect_client_credentials)。
  const body = res.ok ? ((await res.json().catch(() => ({}))) as { access_token?: unknown; error?: unknown }) : {};
  if (typeof body.access_token === "string") return body.access_token;
  console.warn(JSON.stringify({ event: "github_oauth_failed", step: "token", status: res.status, error: body.error ?? null }));
  return null;
}

export async function fetchDiscordUserId(accessToken: string): Promise<string | null> {
  const res = await fetch(`${DISCORD_API}/users/@me`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) return null;
  const body = (await res.json()) as { id?: unknown };
  return typeof body.id === "string" ? body.id : null;
}

/** サーバーに参加させる (参加済みなら何もしない)。guilds.join スコープのトークンが要る。 */
export async function addGuildMember(env: Env, discordUserId: string, accessToken: string): Promise<boolean> {
  const res = await fetch(`${DISCORD_API}/guilds/${env.DISCORD_GUILD_ID}/members/${discordUserId}`, {
    method: "PUT",
    headers: botHeaders(env, true),
    body: JSON.stringify({ access_token: accessToken }),
  });
  // 201 = 参加させた、204 = もう参加していた。
  return res.status === 201 || res.status === 204;
}

/** ロールを付ける。付いていれば何もしない (Discord 側で冪等)。サーバーにいない人は false。 */
export async function addGuildMemberRole(env: Env, discordUserId: string, roleId: string): Promise<boolean> {
  const res = await fetch(
    `${DISCORD_API}/guilds/${env.DISCORD_GUILD_ID}/members/${discordUserId}/roles/${roleId}`,
    { method: "PUT", headers: botHeaders(env) }
  );
  return res.status === 204;
}

/** チャンネルにメッセージを投げる (Bot として)。 */
export async function postChannelMessage(env: Env, channelId: string, message: unknown): Promise<boolean> {
  const res = await fetch(`${DISCORD_API}/channels/${channelId}/messages`, {
    method: "POST",
    headers: botHeaders(env, true),
    body: JSON.stringify(message),
  });
  return res.ok;
}

// ---------------------------------------------------------------------------
// GitHub (コントリビューターの確認)
// ---------------------------------------------------------------------------

const GITHUB_HEADERS = { Accept: "application/vnd.github+json", "User-Agent": "imas-live-api" };

export async function exchangeGithubCode(env: Env, code: string, redirectUri: string): Promise<string | null> {
  const res = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { ...GITHUB_HEADERS, Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: env.GITHUB_OAUTH_CLIENT_ID!,
      client_secret: env.GITHUB_OAUTH_CLIENT_SECRET!,
      code,
      redirect_uri: redirectUri,
    }),
  });
  // GitHub は失敗も 200 + { error } で返す (シークレット違いは incorrect_client_credentials)。
  const body = res.ok ? ((await res.json().catch(() => ({}))) as { access_token?: unknown; error?: unknown }) : {};
  if (typeof body.access_token === "string") return body.access_token;
  console.warn(JSON.stringify({ event: "github_oauth_failed", step: "token", status: res.status, error: body.error ?? null }));
  return null;
}

export async function fetchGithubLogin(accessToken: string): Promise<string | null> {
  const res = await fetch("https://api.github.com/user", {
    headers: { ...GITHUB_HEADERS, Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    console.warn(JSON.stringify({ event: "github_oauth_failed", step: "user", status: res.status }));
    return null;
  }
  const body = (await res.json()) as { login?: unknown };
  return typeof body.login === "string" ? body.login : null;
}

/** そのリポジトリにマージ済みの PR が何件あるか。調べられなければ null。 */
export async function countMergedPullRequests(
  env: Env,
  accessToken: string,
  login: string
): Promise<number | null> {
  const repo = env.GITHUB_REPO || "fuga-if/idol-live-db";
  const q = `repo:${repo} is:pr is:merged author:${login}`;
  const res = await fetch(`https://api.github.com/search/issues?per_page=1&q=${encodeURIComponent(q)}`, {
    headers: { ...GITHUB_HEADERS, Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    console.warn(JSON.stringify({ event: "github_oauth_failed", step: "search", status: res.status }));
    return null;
  }
  const body = (await res.json()) as { total_count?: unknown };
  return typeof body.total_count === "number" ? body.total_count : null;
}

// ---------------------------------------------------------------------------
// Interactions の署名 (Ed25519)
// ---------------------------------------------------------------------------

function hexToBytes(hex: string): Uint8Array | null {
  if (!/^(?:[0-9a-f]{2})+$/i.test(hex)) return null;
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.slice(i * 2, i * 2 + 2), 16);
  return out;
}

/**
 * Discord が署名した Interaction か。署名は timestamp + 生のボディに対する Ed25519。
 * 不正な値・鍵なしは false (例外にしない)。
 */
export async function verifyDiscordSignature(
  publicKeyHex: string,
  signatureHex: string,
  timestamp: string,
  body: string
): Promise<boolean> {
  const key = hexToBytes(publicKeyHex);
  const sig = hexToBytes(signatureHex);
  if (!key || !sig) return false;
  try {
    const cryptoKey = await crypto.subtle.importKey("raw", key, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify("Ed25519", cryptoKey, sig, new TextEncoder().encode(timestamp + body));
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// 結果ページ (OAuth から戻ってきたブラウザに出す)
// ---------------------------------------------------------------------------

export function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * OAuth のあとに出す 1 枚のページ。見た目は Universal Links のフォールバック
 * (routes/app_links.ts) と揃える。script は持たない (CSP で default-src 'none')。
 */
export function renderResultPage(opts: {
  heading: string;
  message: string;
  button?: { label: string; href: string };
  status?: number;
}): Response {
  const button = opts.button
    ? `<a class="btn primary" href="${escapeHtml(opts.button.href)}">${escapeHtml(opts.button.label)}</a>`
    : "";
  const html = `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${escapeHtml(opts.heading)} | アイドルライブDB</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif;
    margin: 0; padding: 32px 20px; text-align: center;
    background: #fafafa; color: #1a1a1a;
  }
  @media (prefers-color-scheme: dark) {
    body { background: #111; color: #eee; }
    .card { background: #1d1d1f !important; }
  }
  .card {
    max-width: 480px; margin: 0 auto; background: #fff;
    border-radius: 20px; padding: 32px 24px;
    box-shadow: 0 2px 16px rgba(0,0,0,.08);
  }
  h1 { font-size: 20px; line-height: 1.4; margin: 0 0 12px; }
  p { color: #888; font-size: 15px; line-height: 1.6; margin: 0; }
  .btn {
    display: block; margin: 24px auto 0; max-width: 320px;
    padding: 14px 24px; border-radius: 14px; text-decoration: none;
    font-weight: 600; font-size: 16px;
  }
  .primary { background: #5865f2; color: #fff; }
</style>
</head>
<body>
  <div class="card">
    <h1>${escapeHtml(opts.heading)}</h1>
    <p>${escapeHtml(opts.message)}</p>
    ${button}
  </div>
</body>
</html>`;
  return new Response(html, {
    status: opts.status ?? 200,
    headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" },
  });
}
