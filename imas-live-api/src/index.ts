import { checkRateLimit } from "./rate_limit";
import { fetchBadges, calcTier } from "./badges";
import { handleScheduled } from "./apply";
import { cloudKitModify, cloudKitLookup, buildForceUpdate, buildSoftDelete, CloudKitOperation } from "./cloudkit";
import { handlePostEdits, handleGetRecordHistory } from "./edits";
import { handlePostEditRequests } from "./edit_requests";
import { handleGetFeed, handleGetMyEdits, maskDisplayName } from "./feed";
import { handlePostGood, handleDeleteGood } from "./edit_good";
import {
  handlePostRevertBatch,
  handlePostAdminRevertUser,
  handleGetAdminUserEdits,
} from "./revert";
import {
  verifyAttestation, verifyAssertion, verifyPlayIntegrity,
  mintAppToken, verifyAppToken, makeChallenge, checkChallenge,
  b64ToBytes, bytesToB64Url,
} from "./appattest";

interface Env {
  DB: D1Database;
  APPLE_BUNDLE_ID: string;
  CLOUDKIT_KEY_ID: string;
  CLOUDKIT_PRIVATE_KEY: string;
  ADMIN_USER_IDS?: string;
  ALLOWED_ORIGINS?: string;
  SESSION_JWT_SECRET?: string;
  // クローンただ乗り対策 (App Attest / Play Integrity)
  APP_ATTEST_MODE?: string;        // "off" | "monitor" | "enforce" (既定 monitor)
  APP_ATTEST_ALLOW_DEV?: string;   // "true" のときだけ dev attestation (appattestdevelop) を許可
  GOOGLE_SERVICE_ACCOUNT?: string; // Play Integrity 検証用 (Android)
  // マスタ修正リクエストの GitHub issue 化用 (secret: wrangler secret put GITHUB_TOKEN)。
  GITHUB_TOKEN?: string;
  GITHUB_REPO?: string;            // "owner/repo" 省略時 "fuga-if/idol-live-db"
}

const SESSION_JWT_ISSUER = "imas-live-db";
const SESSION_JWT_AUDIENCE = "imas-live-db-ios";
const SESSION_JWT_TTL_SECONDS = 60 * 60 * 24 * 365;

// ALLOWED_ORIGINS は wrangler.jsonc の vars で設定する。
// iOS ネイティブは Origin ヘッダを送らないため、空リストでも動作する。
// Web フロントエンドを追加する際はカンマ区切りで列挙すること。
const DEFAULT_ALLOWED_ORIGINS: string[] = [];

const CORS_BASE_HEADERS = {
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Device-Id",
  "Vary": "Origin",
};

function getAllowlist(env: Env): string[] {
  return env.ALLOWED_ORIGINS
    ? env.ALLOWED_ORIGINS.split(",").map((s) => s.trim()).filter(Boolean)
    : DEFAULT_ALLOWED_ORIGINS;
}

/** リクエストの Origin に応じた CORS ヘッダを返す。
 *  - allowlist に一致する Origin → その Origin をエコー
 *  - Origin なし → Access-Control-Allow-Origin ヘッダを付けない (iOS native 等)
 *  - 不一致 → 同上 (403 は checkOrigin で制御)
 */
function getCorsHeaders(request: Request, env: Env): Record<string, string> {
  const origin = request.headers.get("Origin");
  const base = { ...CORS_BASE_HEADERS };
  if (origin && getAllowlist(env).includes(origin)) {
    return { ...base, "Access-Control-Allow-Origin": origin };
  }
  return base;
}

function isWriteMethod(method: string): boolean {
  return method === "POST" || method === "PUT" || method === "DELETE";
}

/** 書き込み系メソッドで Origin が不正な場合 false を返す。
 *  - Origin なし (iOS native 等) → 書き込みも許可 (Apple JWT で認証済み)
 *  - Origin あり & allowlist 一致 → 許可
 *  - Origin あり & 不一致 → 拒否
 */
function checkOrigin(request: Request, env: Env): boolean {
  if (!isWriteMethod(request.method)) return true;
  const origin = request.headers.get("Origin");
  if (!origin) return true; // iOS URLSession は Origin を送らない
  return getAllowlist(env).includes(origin);
}

const IP_RATE_LIMIT_PER_MINUTE = 30;

// ---------------------------------------------------------------------------
// Input helpers
// ---------------------------------------------------------------------------

/**
 * Parse a query-string integer safely.
 * Returns defaultValue when the input is missing, empty, NaN or ≤ 0.
 * Caps the result at max.
 */
function parsePositiveInt(v: string | null, defaultValue: number, max: number = 1000): number {
  const n = parseInt(v ?? "");
  if (!Number.isFinite(n) || n < 1) return defaultValue;
  return Math.min(n, max);
}

/** Escape LIKE wildcards so user input is treated literally. */
function escapeLike(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/%/g, "\\%").replace(/_/g, "\\_");
}

/** チェックのみ（+1 しない）。成功時のみ commitIpRateLimit を呼ぶ。 */
async function dryCheckIpRateLimit(
  db: D1Database,
  ip: string
): Promise<{ allowed: boolean; count: number; bucket: number }> {
  const bucket = Math.floor(Date.now() / 1000 / 60);
  const row = await db
    .prepare("SELECT count FROM api_rate_limits WHERE ip = ? AND minute_bucket = ?")
    .bind(ip, bucket)
    .first<{ count: number }>();
  const count = row?.count ?? 0;
  return { allowed: count < IP_RATE_LIMIT_PER_MINUTE, count, bucket };
}

/** handler 成功直前にのみ呼ぶ（+1 コミット）。 */
async function commitIpRateLimit(
  db: D1Database,
  ip: string,
  bucket: number
): Promise<void> {
  await db
    .prepare(
      `INSERT INTO api_rate_limits (ip, minute_bucket, count)
       VALUES (?, ?, 1)
       ON CONFLICT(ip, minute_bucket) DO UPDATE SET count = count + 1`
    )
    .bind(ip, bucket)
    .run();
}

async function cleanOldRateLimitBuckets(db: D1Database): Promise<void> {
  const oneDayAgo = Math.floor(Date.now() / 1000 / 60) - 1440;
  await db
    .prepare("DELETE FROM api_rate_limits WHERE minute_bucket < ?")
    .bind(oneDayAgo)
    .run();
}

// REPORT_THRESHOLD はタグ通報 (POST /tags/:id/report) で使用。
// 投稿承認系の APPROVAL_THRESHOLD は submission 撤去 (0014) に伴い削除。
const REPORT_THRESHOLD = 3;

// ---------------------------------------------------------------------------
// Apple Sign In JWT verification
// ---------------------------------------------------------------------------

let cachedAppleKeys: { keys: JsonWebKey[]; fetchedAt: number } | null = null;

async function getApplePublicKeys(): Promise<JsonWebKey[]> {
  if (cachedAppleKeys && Date.now() - cachedAppleKeys.fetchedAt < 3600000) {
    return cachedAppleKeys.keys;
  }
  const res = await fetch("https://appleid.apple.com/auth/keys");
  const jwks = (await res.json()) as { keys: JsonWebKey[] };
  cachedAppleKeys = { keys: jwks.keys, fetchedAt: Date.now() };
  return jwks.keys;
}

function base64UrlDecode(str: string): Uint8Array {
  const b64 = str.replace(/-/g, "+").replace(/_/g, "/");
  const pad = b64.length % 4 === 0 ? "" : "=".repeat(4 - (b64.length % 4));
  const binary = atob(b64 + pad);
  return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function verifyAppleToken(
  token: string,
  bundleId: string
): Promise<{ uid: string; email?: string } | null> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const headerJson = JSON.parse(
      new TextDecoder().decode(base64UrlDecode(parts[0]))
    );
    const payload = JSON.parse(
      new TextDecoder().decode(base64UrlDecode(parts[1]))
    );

    // H10: 強化された JWT 検証
    if (headerJson.alg !== "RS256") return null;
    if (typeof payload.exp !== "number" || payload.exp < Date.now() / 1000) return null;
    if (typeof payload.iat !== "number" || payload.iat > Date.now() / 1000 + 60) return null;
    if (payload.iss !== "https://appleid.apple.com") return null;
    if (payload.aud !== bundleId) return null;

    const keys = await getApplePublicKeys();
    const key = keys.find((k: any) => k.kid === headerJson.kid);
    if (!key) return null;

    const cryptoKey = await crypto.subtle.importKey(
      "jwk",
      key,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false,
      ["verify"]
    );

    const signatureValid = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5",
      cryptoKey,
      base64UrlDecode(parts[2]),
      new TextEncoder().encode(parts[0] + "." + parts[1])
    );

    if (!signatureValid) return null;

    return { uid: payload.sub, email: payload.email };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Self-issued session JWT (HS256, 1 年)
// Apple identityToken (10 分) を毎リクエスト送る代わりに、 初回ログイン時に
// /auth/login で発行 → クライアントが Keychain で保持。
// ---------------------------------------------------------------------------

function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importHmacKey(secret: string, usage: KeyUsage[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usage
  );
}

async function signSessionToken(uid: string, secret: string): Promise<string> {
  if (secret.length < 32) {
    throw new Error("SESSION_JWT_SECRET must be at least 32 chars");
  }
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT" };
  const payload = {
    iss: SESSION_JWT_ISSUER,
    aud: SESSION_JWT_AUDIENCE,
    sub: uid,
    iat: now,
    exp: now + SESSION_JWT_TTL_SECONDS,
  };
  const enc = new TextEncoder();
  const headerB64 = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(enc.encode(JSON.stringify(payload)));
  const signingInput = `${headerB64}.${payloadB64}`;
  const key = await importHmacKey(secret, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(signingInput));
  return `${signingInput}.${base64UrlEncode(new Uint8Array(sig))}`;
}

async function verifySessionToken(
  token: string,
  secret: string
): Promise<{ uid: string } | null> {
  try {
    if (secret.length < 32) return null;
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const headerJson = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])));
    if (headerJson.alg !== "HS256" || headerJson.typ !== "JWT") return null;
    const enc = new TextEncoder();
    const key = await importHmacKey(secret, ["verify"]);
    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      base64UrlDecode(parts[2]),
      enc.encode(`${parts[0]}.${parts[1]}`)
    );
    if (!valid) return null;
    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));
    if (payload.iss !== SESSION_JWT_ISSUER) return null;
    // 確定契約 §5: aud 欠落トークンも reject (aud は必須。トークン用途固定で取り違えを防ぐ)。
    if (payload.aud !== SESSION_JWT_AUDIENCE) return null;
    const now = Date.now() / 1000;
    if (typeof payload.exp !== "number" || payload.exp < now) return null;
    if (typeof payload.iat === "number" && payload.iat > now + 60) return null;
    if (typeof payload.sub !== "string") return null;
    return { uid: payload.sub };
  } catch {
    return null;
  }
}

/** sliding refresh 用: 署名 + iss/aud が有効なら、exp 切れでも猶予内なら uid を返す。
 *  攻撃者が偽造できない (署名検証は通常どおり)。古すぎる (exp が猶予より前) トークンは拒否。 */
const REFRESH_GRACE_SECONDS = 60 * 60 * 24 * 90; // 期限切れ後90日まで再発行可
async function verifySessionTokenForRefresh(
  token: string,
  secret: string
): Promise<{ uid: string } | null> {
  try {
    if (secret.length < 32) return null;
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const headerJson = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])));
    if (headerJson.alg !== "HS256" || headerJson.typ !== "JWT") return null;
    const enc = new TextEncoder();
    const key = await importHmacKey(secret, ["verify"]);
    const valid = await crypto.subtle.verify(
      "HMAC", key, base64UrlDecode(parts[2]), enc.encode(`${parts[0]}.${parts[1]}`)
    );
    if (!valid) return null;
    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));
    if (payload.iss !== SESSION_JWT_ISSUER) return null;
    if (payload.aud !== SESSION_JWT_AUDIENCE) return null;
    if (typeof payload.sub !== "string") return null;
    const now = Date.now() / 1000;
    // exp は必須。期限切れは許容するが、猶予 (90日) を超えた古いトークンは拒否。
    if (typeof payload.exp !== "number") return null;
    if (payload.exp < now - REFRESH_GRACE_SECONDS) return null;
    if (typeof payload.iat === "number" && payload.iat > now + 60) return null;
    return { uid: payload.sub };
  } catch {
    return null;
  }
}

/** JWT の iss クレームだけ覗いて自前セッションか Apple か振り分ける。 */
function peekJwtIssuer(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));
    return typeof payload.iss === "string" ? payload.iss : null;
  } catch {
    return null;
  }
}

async function getAuthUser(
  request: Request,
  env: Env
): Promise<{ uid: string; email?: string } | null> {
  const auth = request.headers.get("Authorization");
  if (!auth?.startsWith("Bearer ")) return null;
  const token = auth.slice(7);
  const issuer = peekJwtIssuer(token);
  if (issuer === SESSION_JWT_ISSUER && env.SESSION_JWT_SECRET) {
    return verifySessionToken(token, env.SESSION_JWT_SECRET);
  }
  // Apple identityToken (10 分有効) を直接受け付ける移行期間互換。
  return verifyAppleToken(token, env.APPLE_BUNDLE_ID);
}

/** クローンただ乗り対策の対象 = 認証不要で開いているコミュニティ集計の read。 */
function isCommunityRead(path: string, method: string): boolean {
  if (method !== "GET") return false;
  // D1 固定無料枠に乗る集計 read を網羅する (CLAUDE.md 名指しの予想/いいね/ランキング含む)
  if (/^\/(polls|favorites|penlight|tags|master|leaderboard)(\/|$)/.test(path)) return true;
  if (/^\/songs\/[^/]+\/(tags|similar)$/.test(path)) return true;
  if (/^\/shows\/[^/]+\/(predictions|likes)$/.test(path)) return true;
  return false;
}

// ---------------------------------------------------------------------------
// Response helpers
// ---------------------------------------------------------------------------

// request/env を受け取るクロージャとして定義するため、fetch ハンドラ内で使う。
// ここではシグネチャだけ定義し、実装はハンドラ内の変数に委譲する。

function addRequestId(response: Response, requestId: string): Response {
  const newHeaders = new Headers(response.headers);
  newHeaders.set("X-Request-Id", requestId);
  return new Response(response.body, { status: response.status, headers: newHeaders });
}

function makeResponders(request: Request, env: Env) {
  const cors = getCorsHeaders(request, env);

  function json(data: unknown, status = 200, extraHeaders: Record<string, string> = {}): Response {
    return new Response(JSON.stringify(data), {
      status,
      headers: { "Content-Type": "application/json; charset=utf-8", ...cors, ...extraHeaders },
    });
  }

  function error(message: string, status = 400): Response {
    return json({ error: message }, status);
  }

  function rateLimitResponse(used: number, limit: number, resetAt: string): Response {
    const retryAfterSec = Math.ceil(
      (new Date(resetAt).getTime() - Date.now()) / 1000
    );
    return new Response(
      JSON.stringify({ error: "rate_limit_exceeded", limit, used, reset_at: resetAt }),
      {
        status: 429,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Retry-After": String(Math.max(retryAfterSec, 0)),
          ...cors,
        },
      }
    );
  }

  function rateLimitSimple(retryAfter = 60): Response {
    return new Response(
      JSON.stringify({ error: "rate_limit_exceeded" }),
      {
        status: 429,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Retry-After": String(retryAfter),
          ...cors,
        },
      }
    );
  }

  return { json, error, rateLimitResponse, rateLimitSimple, cors };
}

// ---------------------------------------------------------------------------
// Upsert user helper
// ---------------------------------------------------------------------------

async function upsertUser(env: Env, uid: string, name?: string, picture?: string) {
  // display_name は INSERT (初回ログインで行を作る) 時のみ設定し、CONFLICT では一切更新しない。
  // 既存ユーザーの表示名は POST /users/me でのみ変更する設計にする。これにより:
  //  - login: Apple は fullName を初回認可時しか返さず、2台目/再インストール後は name=undefined。
  //  - community 書き込み: 各ハンドラが upsertUser(uid, user.email) と email を name に渡している。
  // のどちらでも、ユーザーが POST /users/me で設定した display_name を毎回上書きする事故を防ぐ。
  // avatar_url は渡されたときだけ更新し、無ければ COALESCE で既存を温存する。
  await env.DB.prepare(
    `INSERT INTO users (id, display_name, avatar_url) VALUES (?, ?, ?)
     ON CONFLICT(id) DO UPDATE SET
       avatar_url = COALESCE(?, users.avatar_url),
       updated_at = datetime('now')`
  )
    .bind(uid, name || "匿名", picture ?? null, picture ?? null)
    .run();
}

// ---------------------------------------------------------------------------
// Universal Links (deeplink) helpers
// ---------------------------------------------------------------------------

/** iOS アプリの appID (TeamID.BundleID)。AASA で Universal Links を許可する対象。 */
const APPLE_APP_ID = "GQ3WP34LFW.com.fugaif.ImasLiveDB";

/** アイドルライブDB の App Store ページ (未インストールユーザーの誘導先)。 */
const APP_STORE_URL = "https://apps.apple.com/jp/app/id6763342297";
const APP_STORE_NUMERIC_ID = "6763342297";

/** HTML テキスト/属性値に埋め込む動的文字列のエスケープ (XSS 防止)。 */
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/**
 * Universal Links のブラウザフォールバックページ。
 * アプリ未インストール (またはデスクトップ) でリンクを開いた人向けに、
 * イベント/公演名 + アプリ紹介 + App Store 誘導を返す。
 * title が null (未知 ID) でも安全に静的文言へフォールバックする。
 */
function renderAppFallbackPage(opts: {
  kind: "events" | "shows";
  id: string;
  title: string | null;
  subtitle: string | null;
}): string {
  const { title } = opts;
  let heading: string;
  let description: string;
  if (title !== null) {
    heading = escapeHtml(title);
    description = `「${heading}」のセットリスト・出演情報をアプリでチェック`;
  } else {
    heading = opts.kind === "events" ? "イベントが見つかりません" : "公演が見つかりません";
    description = "アイマス全ブランドのライブ・セットリストデータベース";
  }
  const subtitleHtml = opts.subtitle
    ? `<p class="sub">${escapeHtml(opts.subtitle)}</p>`
    : "";
  // アプリインストール済みで Universal Links が発火しなかった場合の救済リンク (custom scheme)。
  const schemeUrl = escapeHtml(
    `imaslivedb://${opts.kind}/${encodeURIComponent(opts.id)}`
  );
  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="apple-itunes-app" content="app-id=${APP_STORE_NUMERIC_ID}">
<meta property="og:title" content="${heading} | アイドルライブDB">
<meta property="og:description" content="${description}">
<meta property="og:type" content="website">
<title>${heading} | アイドルライブDB</title>
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
  h1 { font-size: 20px; line-height: 1.4; margin: 0 0 8px; }
  .sub { color: #888; font-size: 14px; margin: 0 0 4px; }
  .app { color: #888; font-size: 13px; margin: 20px 0 12px; }
  .btn {
    display: block; margin: 12px auto 0; max-width: 320px;
    padding: 14px 24px; border-radius: 14px; text-decoration: none;
    font-weight: 600; font-size: 16px;
  }
  .primary { background: #e91e63; color: #fff; }
  .secondary { color: #e91e63; }
</style>
</head>
<body>
  <div class="card">
    <h1>${heading}</h1>
    ${subtitleHtml}
    <p class="app">アイドルライブDB — アイマス全ブランドのライブ・セットリストデータベース</p>
    <a class="btn primary" href="${APP_STORE_URL}">App Store でダウンロード</a>
    <a class="btn secondary" href="${schemeUrl}">アプリで開く</a>
  </div>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Main fetch handler
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const requestId = crypto.randomUUID();
    const { json, error, rateLimitResponse, rateLimitSimple, cors } = makeResponders(request, env);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: { ...CORS_BASE_HEADERS, ...cors, "X-Request-Id": requestId } });
    }

    if (!checkOrigin(request, env)) {
      return new Response(JSON.stringify({ error: "Forbidden: origin not allowed" }), {
        status: 403,
        headers: { "Content-Type": "application/json; charset=utf-8", "Vary": "Origin", "X-Request-Id": requestId },
      });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    // ----------------------------------------------------------------
    // エッジキャッシュ (Cache API)
    // ----------------------------------------------------------------
    // 公開GET (レスポンスに Cache-Control: public を返すエンドポイント) を Cloudflare
    // エッジで全端末横断キャッシュし、Worker 起動回数と D1 行読みを大幅に削減する。
    // - ユーザー依存エンドポイント (my_tag_ids / has_user_voted / my_vote_count 等) は
    //   意図的に Cache-Control を付けていないので自動的に対象外になる。
    // - 認証付きリクエストは絶対にキャッシュしない (個人データ漏洩防止)。
    // - キャッシュキーは URL のみ (device/app-token ヘッダに依存させない) で正規化する。
    const edgeCacheEligible = request.method === "GET" && !request.headers.get("Authorization");
    const cacheKey = new Request(url.toString(), { method: "GET" });
    if (edgeCacheEligible) {
      const cached = await caches.default.match(cacheKey);
      if (cached) {
        // 観測用: エッジキャッシュ命中を明示 (cf-cache-status は Cache API では出ないため)。
        const hit = new Response(cached.body, cached);
        hit.headers.set("X-Edge-Cache", "HIT");
        return hit;
      }
    }

    const handle = async (): Promise<Response> => {
    try {
      // ----------------------------------------------------------------
      // アプリ証明 (App Attest / Play Integrity) — クローンただ乗り対策
      // ----------------------------------------------------------------
      const attestMode = env.APP_ATTEST_MODE || "monitor";
      const secret = env.SESSION_JWT_SECRET;

      // /app/* は IP 単位レート制限 (クォータ枯渇による自爆 DoS 防止)
      if (path.startsWith("/app/")) {
        const ip = request.headers.get("cf-connecting-ip") || "unknown";
        const rl = await checkRateLimit(env.DB, "ip:" + ip, "app_attest");
        if (!rl.allowed) return error("rate limited", 429);
      }

      if (path === "/app/challenge" && request.method === "GET") {
        if (!secret) return error("server not configured", 500);
        return json({ challenge: bytesToB64Url(await makeChallenge(secret)) });
      }
      if (path === "/app/attest" && request.method === "POST") {
        if (!secret) return error("server not configured", 500);
        const body: any = await request.json().catch(() => null);
        if (!body?.keyId || !body?.attestation || !body?.challenge) return error("bad request", 400);
        const challenge = b64ToBytes(body.challenge);
        if (!(await checkChallenge(challenge, secret))) return error("bad challenge", 400);
        try {
          const { spki, counter } = await verifyAttestation(challenge, b64ToBytes(body.keyId), body.attestation, env.APP_ATTEST_ALLOW_DEV === "true");
          const now = Date.now();
          // OR IGNORE: 既存 keyId への再 attest (リプレイ) で counter を 0 に戻させない
          await env.DB.prepare(
            "INSERT OR IGNORE INTO app_attest_keys (key_id, public_key, counter, created_at, updated_at) VALUES (?,?,?,?,?)"
          ).bind(body.keyId, bytesToB64Url(spki), counter, now, now).run();
          return json({ appToken: await mintAppToken(body.keyId, secret) });
        } catch (e) {
          return error("attestation failed: " + (e as Error).message, 401);
        }
      }
      if (path === "/app/assert" && request.method === "POST") {
        if (!secret) return error("server not configured", 500);
        const body: any = await request.json().catch(() => null);
        if (!body?.keyId || !body?.assertion || !body?.challenge) return error("bad request", 400);
        const challenge = b64ToBytes(body.challenge);
        if (!(await checkChallenge(challenge, secret))) return error("bad challenge", 400);
        const row: any = await env.DB.prepare("SELECT public_key, counter FROM app_attest_keys WHERE key_id=?").bind(body.keyId).first();
        if (!row) return error("unknown key", 401);
        try {
          const newCounter = await verifyAssertion(challenge, body.assertion, b64ToBytes(row.public_key), row.counter as number);
          await env.DB.prepare("UPDATE app_attest_keys SET counter=?, updated_at=? WHERE key_id=?").bind(newCounter, Date.now(), body.keyId).run();
          return json({ appToken: await mintAppToken(body.keyId, secret) });
        } catch (e) {
          return error("assertion failed: " + (e as Error).message, 401);
        }
      }
      if (path === "/app/integrity" && request.method === "POST") {
        if (!secret || !env.GOOGLE_SERVICE_ACCOUNT) return error("server not configured", 500);
        const body: any = await request.json().catch(() => null);
        if (!body?.token || !body?.challenge) return error("bad request", 400);
        if (!(await checkChallenge(b64ToBytes(body.challenge), secret))) return error("bad challenge", 400);
        try {
          const ok = await verifyPlayIntegrity(body.token, body.challenge, env.GOOGLE_SERVICE_ACCOUNT);
          if (!ok) return error("integrity check failed", 401);
          return json({ appToken: await mintAppToken("android", secret) });
        } catch (e) {
          return error("integrity failed: " + (e as Error).message, 401);
        }
      }

      // コミュニティ集計 read のゲート (正規アプリ or ログイン済みのみ)
      if (attestMode !== "off" && isCommunityRead(path, request.method)) {
        const appTok = request.headers.get("X-App-Token");
        const genuine =
          (!!appTok && !!secret && (await verifyAppToken(appTok, secret))) ||
          (await getAuthUser(request, env)) !== null;
        if (!genuine) {
          if (attestMode === "enforce") return error("app attestation required", 401);
          console.log(`[appattest:monitor] ungated community read ${path}`);
        }
      }

      // ----------------------------------------------------------------
      // GET /
      // ----------------------------------------------------------------
      if (path === "/" || path === "") {
        return json({
          name: "imas-live-api",
          description: "THE IDOLM@STER Live Database API",
          endpoints: [
            "POST /auth/login",
            "GET /auth/me",
            "POST /admin/cloudkit/save",
            "POST /edits",
            "GET /edits?brand_id=&record_type=&editor_id=&page=1&limit=20",
            "GET /me/edits?page=1&limit=20",
            "POST /edits/:batchId/good",
            "DELETE /edits/:batchId/good",
            "POST /edits/:batchId/revert",
            "GET /master/:recordType/:recordName/history",
            "GET /users/:user_id/badges",
            "GET /leaderboard",
            "POST /admin/ban",
            "POST /admin/revert-user",
            "GET /admin/users/:id/edits",
            "GET /shows/:id/predictions",
            "POST /shows/:id/predictions",
            "DELETE /shows/:id/predictions/:songId",
            "GET /shows/:id/songs/:songId/performers",
            "POST /shows/:id/songs/:songId/performers",
            "DELETE /shows/:id/songs/:songId/performers/:idolId",
            "GET /shows/:id/likes",
            "POST /shows/:id/songs/:songId/like",
            "DELETE /shows/:id/songs/:songId/like",
            "GET /polls",
            "GET /polls/:id",
            "POST /polls",
            "POST /polls/:id/votes",
            "DELETE /polls/:id/votes/:entityId",
            "DELETE /polls/:id",
          ],
        });
      }

      // ----------------------------------------------------------------
      // GET /.well-known/apple-app-site-association — Universal Links 定義
      //   Apple CDN 要件: リダイレクトなし・Content-Type: application/json。
      // ----------------------------------------------------------------
      if (path === "/.well-known/apple-app-site-association" && request.method === "GET") {
        return new Response(
          JSON.stringify({
            applinks: {
              details: [
                {
                  appIDs: [APPLE_APP_ID],
                  // アプリが実際に処理できるパスだけに絞る (それ以外は素直にブラウザで開かせる)。
                  components: [{ "/": "/app/events/*" }, { "/": "/app/shows/*" }],
                },
              ],
            },
          }),
          {
            headers: {
              "Content-Type": "application/json",
              "Cache-Control": "public, max-age=3600",
              "X-Request-Id": requestId,
            },
          }
        );
      }

      // ----------------------------------------------------------------
      // GET /app/events/:id, /app/shows/:id — Universal Links フォールバック
      //   アプリ未インストールのブラウザアクセスに App Store 誘導 HTML を返す。
      //   (インストール済み端末では iOS がアプリを直接開くため通常表示されない)
      // ----------------------------------------------------------------
      const appLinkMatch = path.match(/^\/app\/(events|shows)\/([^/]+)$/);
      if (appLinkMatch && request.method === "GET") {
        const kind = appLinkMatch[1] as "events" | "shows";
        let id: string;
        try {
          id = decodeURIComponent(appLinkMatch[2]);
        } catch {
          // 不正な percent-encoding (%G0 等) は URIError → 500 にせず 404 ページを返す。
          return new Response(
            renderAppFallbackPage({ kind, id: appLinkMatch[2], title: null, subtitle: null }),
            {
              status: 404,
              headers: {
                "Content-Type": "text/html; charset=utf-8",
                "X-Request-Id": requestId,
              },
            }
          );
        }
        // 名前は CloudKit (唯一の正) を S2S lookup で直読みする。recordName = id。
        // 旧実装は Worker D1 の master ミラーを読んでいたが、ミラーは CloudKit と
        // 同期されず古くなるため廃止。lookup 失敗時は title=null の graceful degrade。
        let title: string | null = null;
        let subtitle: string | null = null;
        try {
          if (kind === "events") {
            const res = await cloudKitLookup([id], env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
            const fields = res.records?.get(id)?.fields;
            title = (fields?.name?.value as string | undefined) ?? null;
          } else {
            const res = await cloudKitLookup([id], env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
            const show = res.records?.get(id)?.fields;
            if (show) {
              const showName = (show.name?.value as string | undefined) ?? "";
              const date = (show.date?.value as string | undefined) ?? null;
              const venue = (show.venue?.value as string | undefined) ?? null;
              const eventId = show.eventId?.value as string | undefined;
              let eventName: string | null = null;
              if (eventId) {
                const evRes = await cloudKitLookup([eventId], env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
                eventName = (evRes.records?.get(eventId)?.fields?.name?.value as string | undefined) ?? null;
              }
              title = eventName && !showName.includes(eventName)
                ? `${eventName} ${showName}`
                : showName || null;
              subtitle = [date, venue].filter(Boolean).join(" ・ ") || null;
            }
          }
        } catch {
          // CloudKit 到達不可等 → title=null のまま誘導ページのみ返す。
          title = null;
        }
        return new Response(renderAppFallbackPage({ kind, id, title, subtitle }), {
          status: title !== null ? 200 : 404,
          headers: {
            "Content-Type": "text/html; charset=utf-8",
            "X-Request-Id": requestId,
          },
        });
      }

      // ----------------------------------------------------------------
      // POST /auth/login — Apple identityToken → 1 年有効 sessionToken
      // ----------------------------------------------------------------
      if (path === "/auth/login" && request.method === "POST") {
        if (!env.SESSION_JWT_SECRET) return error("SESSION_JWT_SECRET not configured", 500);
        // iOS の APIClient は JSONEncoder.keyEncodingStrategy = .convertToSnakeCase で
        // 全リクエストボディを snake_case 化して送る (identityToken → identity_token,
        // displayName → display_name)。この endpoint だけ camelCase を読んでいたため
        // iOS のログインは常に 400 となり、session token が一度も発行されず、Apple
        // identityToken を直接 Bearer (10分有効) に流用するフォールバックで誤魔化されていた。
        // snake_case を正として読む (旧 camelCase クライアントも後方互換で許容)。
        const body = (await request.json().catch(() => null)) as
          | { identity_token?: string; identityToken?: string; display_name?: string; displayName?: string }
          | null;
        const identityToken = body?.identity_token ?? body?.identityToken;
        const displayName = body?.display_name ?? body?.displayName;
        if (!identityToken) return error("identityToken required");
        const verified = await verifyAppleToken(identityToken, env.APPLE_BUNDLE_ID);
        if (!verified) return error("invalid identityToken", 401);
        await upsertUser(env, verified.uid, displayName);
        const sessionToken = await signSessionToken(verified.uid, env.SESSION_JWT_SECRET);
        const isAdmin = await checkIsAdmin(env, verified.uid);
        // 再ログイン時 Apple は fullName を初回認可時しか返さないため、クライアントは
        // 自前で表示名を復元できない。upsert 後の正準 display_name を返し、クライアントが
        // userName を即復元できるようにする (これが無いと再ログイン直後に表示名が空になる)。
        const dbRow = await env.DB.prepare("SELECT display_name FROM users WHERE id = ?")
          .bind(verified.uid)
          .first<{ display_name: string }>();
        return json({
          sessionToken,
          uid: verified.uid,
          email: verified.email,
          isAdmin,
          displayName: dbRow?.display_name ?? null,
          expiresIn: SESSION_JWT_TTL_SECONDS,
        });
      }

      // ----------------------------------------------------------------
      // POST /auth/refresh — 期限切れ間近/直後の sessionToken を Apple 再認証なしで再発行
      //   (sliding session)。署名が有効で猶予 (90日) 内なら新しい 1 年トークンを返す。
      // ----------------------------------------------------------------
      if (path === "/auth/refresh" && request.method === "POST") {
        if (!env.SESSION_JWT_SECRET) return error("SESSION_JWT_SECRET not configured", 500);
        const auth = request.headers.get("Authorization");
        if (!auth?.startsWith("Bearer ")) return error("Unauthorized", 401);
        const oldToken = auth.slice(7);
        // 自前セッショントークンのみ refresh 対象 (Apple identityToken は対象外)。
        if (peekJwtIssuer(oldToken) !== SESSION_JWT_ISSUER) return error("Unauthorized", 401);
        const verified = await verifySessionTokenForRefresh(oldToken, env.SESSION_JWT_SECRET);
        if (!verified) return error("Unauthorized", 401);
        const sessionToken = await signSessionToken(verified.uid, env.SESSION_JWT_SECRET);
        const isAdmin = await checkIsAdmin(env, verified.uid);
        return json({
          sessionToken,
          uid: verified.uid,
          isAdmin,
          expiresIn: SESSION_JWT_TTL_SECONDS,
        });
      }

      // ----------------------------------------------------------------
      // GET /auth/me
      // ----------------------------------------------------------------
      if (path === "/auth/me" && request.method === "GET") {
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);
        // 貢献度 2 指標 (確定契約。合成しない):
        //   editCount     = users.contribution_count (編集 batch 件数。finalize で +1)
        //   goodsReceived = 自分の編集が累計で受け取った Good 数 (edit_good を editor で都度 COUNT)
        const row = await env.DB.prepare(
          `SELECT u.id, u.display_name, u.avatar_url, u.is_admin, u.is_banned, u.contribution_count,
                  COALESCE((SELECT COUNT(*) FROM edit_good g
                            JOIN edit_batch eb ON eb.id = g.batch_id
                            WHERE eb.editor_id = u.id AND eb.source = 'app'), 0) AS goods_received
             FROM users u WHERE u.id = ?`
        )
          .bind(user.uid)
          .first<{
            id: string;
            display_name: string;
            avatar_url: string | null;
            is_admin: number;
            is_banned: number;
            contribution_count: number;
            goods_received: number;
          }>();
        const isAdmin = (await checkIsAdmin(env, user.uid)) || !!row?.is_admin;
        // editCount = source='app' の編集 batch 件数。contribution_count は finalizeEditBatch で
        // source='app' のみ +1 されるため同値 (revert/seed では加算しない=現状維持。確定契約 §3)。
        const editCount = row?.contribution_count ?? 0;
        return json({
          uid: user.uid,
          displayName: row?.display_name ?? null,
          avatarUrl: row?.avatar_url ?? null,
          isAdmin,
          isBanned: !!row?.is_banned,
          editCount,
          goodsReceived: row?.goods_received ?? 0,
        });
      }

      // ----------------------------------------------------------------
      // POST /users/me — 自分の表示名 (display_name) を更新
      //   メソッドは POST。この Worker の書き込みは POST/PUT/DELETE のみで、
      //   PATCH は isWriteMethod にも CORS Allow-Methods にも無い (= 未サポート)。
      //   既存の書き込み規約に合わせる。
      // ----------------------------------------------------------------
      if (path === "/users/me" && request.method === "POST") {
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        // 先にボディを検証する。checkRateLimit は原子的にカウンタを +1 するので、
        // 検証より前に走らせると空文字・型不正など 400 になるリクエストでも 1日20枠を
        // 消費し、ユーザーが表示名を変更できなくなる (自爆ロックアウト)。検証後に課金する。
        const body = (await request.json().catch(() => null)) as { display_name?: unknown } | null;
        const raw = body?.display_name;
        if (typeof raw !== "string") return error("display_name is required");
        const name = raw.trim();
        if (name.length === 0) return error("display_name must not be empty");
        // 長さは UTF-16 code unit ではなく Unicode code point で数える ([...name])。
        // 絵文字等を 2 文字とカウントして見た目40字未満を弾く誤判定を避ける。
        if ([...name].length > 40) return error("display_name too long (max 40)");

        const [dbUser, rl] = await Promise.all([
          env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
            .bind(user.uid)
            .first<{ is_banned: number }>(),
          checkRateLimit(env.DB, user.uid, "profile"),
        ]);
        if (dbUser?.is_banned) return error("Banned", 403);
        if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

        // upsertUser は使わない (display_name を email 等で上書きしうるため)。
        // 行は login 時に必ず作られているので plain UPDATE。INSERT...ON CONFLICT にすると、
        // 行が消えた (削除済みだがトークンだけ生きている) アカウントを display_name だけの
        // 不完全な行で復活させてしまうため、ここでは新規作成しない。0件更新なら 404。
        const updated = await env.DB.prepare(
          `UPDATE users SET display_name = ?, updated_at = datetime('now') WHERE id = ?`
        )
          .bind(name, user.uid)
          .run();
        if (!updated.meta.changes) return error("user not found", 404);

        return json({ displayName: name });
      }

      // ----------------------------------------------------------------
      // POST /admin/cloudkit/save — admin 限定の CK forceUpdate+delete
      // iOS 直書きでは「他人 (S2S) のレコードを更新不可」なのでサーバ経由で S2S 借用。
      // ----------------------------------------------------------------
      if (path === "/admin/cloudkit/save" && request.method === "POST") {
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);
        if (!(await checkIsAdmin(env, user.uid))) return error("Forbidden: admin only", 403);

        const rawBody = await request.text();
        if (rawBody.length > 2_000_000) return error("body too large (max 2MB)", 413);
        type SavePayload = {
          records?: Array<{ recordType: string; recordName: string; fields: Record<string, unknown> }>;
          deletes?: Array<{ recordType: string; recordName: string }>;
        };
        let body: SavePayload | null;
        try { body = JSON.parse(rawBody) as SavePayload; }
        catch { return error("invalid json body"); }
        if (!body) return error("invalid json body");

        const records = body.records ?? [];
        const deletes = body.deletes ?? [];
        if (records.length === 0 && deletes.length === 0) return error("records or deletes required");
        if (records.length + deletes.length > 1000) return error("too many operations (max 1000)", 413);
        for (const r of records) {
          for (const [k, v] of Object.entries(r.fields ?? {})) {
            if (typeof v === "string" && v.length > 50_000) {
              return error(`fields.${k} too long (max 50KB)`, 413);
            }
          }
        }

        const ALLOWED_TYPES = new Set([
          "Brand", "Idol", "IdolBrand",
          "Event", "Show", "ShowCast",
          "Song", "SongArtist", "ImasUnit", "UnitMember",
          "SetlistItem", "SetlistPerformer",
        ]);

        const ops: CloudKitOperation[] = [];
        for (const r of records) {
          if (!ALLOWED_TYPES.has(r.recordType)) return error(`recordType not allowed: ${r.recordType}`, 400);
          if (!r.recordName) return error("recordName required");
          ops.push(buildForceUpdate(r.recordType, r.recordName, r.fields ?? {}));
        }
        for (const d of deletes) {
          if (!ALLOWED_TYPES.has(d.recordType)) return error(`recordType not allowed: ${d.recordType}`, 400);
          if (!d.recordName) return error("recordName required for delete");
          // ハード削除 (forceDelete) は iOS 差分同期が観測できないため soft delete (deletedAt) を使う (契約 v2 #1)。
          ops.push(buildSoftDelete(d.recordType, d.recordName));
        }

        const chunkSize = 200;
        let successCount = 0;
        for (let i = 0; i < ops.length; i += chunkSize) {
          const chunk = ops.slice(i, i + chunkSize);
          const res = await cloudKitModify(chunk, env.CLOUDKIT_KEY_ID, env.CLOUDKIT_PRIVATE_KEY);
          if (!res.ok) return error(`cloudkit_error after ${successCount}/${ops.length}: ${res.error}`, 502);
          successCount += chunk.length;
        }
        return json({ ok: true, savedCount: records.length, deletedCount: deletes.length });
      }

      // ----------------------------------------------------------------
      // 旧 Web アプリ (imas-live-app) 専用の master JSON API はここにあったが撤去した。
      //   GET /brands /idols /idols/:id /songs /songs/:id /songs/:id/artists
      //       /events /events/:id /events/:id/shows /shows/:id/setlist
      //       /units/:id /units/:id/members /units/:id/songs /search /version
      //       /patch /stats /sql
      // 理由: Web アプリは停止 (503)、iOS はマスタを CloudKit 直 sync するため不使用。
      //   これらが読んでいた D1 master ミラーは CloudKit と同期されず陳腐化していた。
      //   唯一 D1 master を読んでいた /app/* フォールバックは CloudKit S2S 直読みへ移行済み。
      //   集計系コミュニティ (タグ/お気に入り/投票/ポール/ランキング) は master 非依存なので影響なし。
      // ----------------------------------------------------------------

      // ================================================================
      // 編集フィード + Good API (即時オープン編集の貢献可視化)
      //
      // 旧 submission/votes (承認投票) システムは即時オープン編集 (POST /edits) への
      // 移行と 0014 のテーブル DROP により完全撤去済み。Good は「承認」と切り離した
      // 感謝/人気指標として編集 batch 単位に付ける。
      // ================================================================

      // ----------------------------------------------------------------
      // GET /edits — 最近の編集フィード (匿名可。auth あれば has_user_good 付与)
      // ----------------------------------------------------------------
      if (path === "/edits" && request.method === "GET") {
        // 読み取りのみ。/search と同様 IP rate-limit (dryCheck → commit)。
        const feedIp = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const feedRl = await dryCheckIpRateLimit(env.DB, feedIp);
        if (!feedRl.allowed) return rateLimitSimple();
        const res = await handleGetFeed(request, url, env, { getAuthUser, json, error });
        await commitIpRateLimit(env.DB, feedIp, feedRl.bucket);
        return res;
      }

      // ----------------------------------------------------------------
      // GET /me/edits — 自分の編集 batch 一覧 (本人 revert 用, auth 必須)
      // ----------------------------------------------------------------
      if (path === "/me/edits" && request.method === "GET") {
        return handleGetMyEdits(request, url, env, { getAuthUser, json, error });
      }

      // ----------------------------------------------------------------
      // POST | DELETE /edits/:batchId/good — 編集への Good トグル (auth 必須)
      // ----------------------------------------------------------------
      const editGoodMatch = path.match(/^\/edits\/(\d+)\/good$/);
      if (editGoodMatch && request.method === "POST") {
        return handlePostGood(request, env, {
          getAuthUser,
          upsertUser,
          checkRateLimit,
          json,
          error,
          rateLimitResponse,
        }, editGoodMatch[1]);
      }
      if (editGoodMatch && request.method === "DELETE") {
        return handleDeleteGood(request, env, {
          getAuthUser,
          upsertUser,
          checkRateLimit,
          json,
          error,
          rateLimitResponse,
        }, editGoodMatch[1]);
      }

      // ----------------------------------------------------------------
      // POST /edits/:batchId/revert — 本人 (自分の batch) または admin が 1 batch を revert
      // ----------------------------------------------------------------
      const editRevertMatch = path.match(/^\/edits\/(\d+)\/revert$/);
      if (editRevertMatch && request.method === "POST") {
        return handlePostRevertBatch(
          request,
          env,
          { getAuthUser, checkIsAdmin, json, error },
          editRevertMatch[1]
        );
      }

      // ----------------------------------------------------------------
      // GET /users/:user_id/badges
      // ----------------------------------------------------------------
      const badgesMatch = path.match(/^\/users\/([^/]+)\/badges$/);
      if (badgesMatch && request.method === "GET") {
        const userId = decodeURIComponent(badgesMatch[1]);
        const badges = await fetchBadges(env.DB, userId);
        return json(badges);
      }

      // ----------------------------------------------------------------
      // GET /leaderboard — 貢献ランキング (バッジ tier 付き)
      //
      // 貢献度は 2 指標を個別集計し合成しない (確定契約)。レスポンスキーは camelCase:
      //   - editCount     = 編集件数 (cloudkit_ok=1 の edit_batch を finalize で +1。= contribution_count)
      //   - goodsReceived = 自分の編集が累計で受け取った Good 数 (edit_good を editor で集計)
      // tier は editCount を主指標とする (Good は sybil 水増し耐性が低いため)。
      // ----------------------------------------------------------------
      if (path === "/leaderboard" && request.method === "GET") {
        const { results } = await env.DB.prepare(
          `SELECT u.id, u.display_name, u.avatar_url, u.contribution_count,
                  COALESCE((SELECT COUNT(*) FROM edit_good g
                            JOIN edit_batch eb ON eb.id = g.batch_id
                            WHERE eb.editor_id = u.id AND eb.source = 'app'), 0) AS goods_received
           FROM users u
           WHERE u.is_banned = 0 AND u.contribution_count > 0
           ORDER BY u.contribution_count DESC LIMIT 20`
        ).all<{
          id: string;
          display_name: string;
          avatar_url: string | null;
          contribution_count: number;
          goods_received: number;
        }>();

        // editCount = source='app' 編集件数 (= contribution_count。確定契約 §3)。旧キー contributionCount は廃止。
        const leaderboard = results.map((u) => ({
          id: u.id,
          userId: u.id,
          displayName: maskDisplayName(u.display_name),
          avatarUrl: u.avatar_url,
          editCount: u.contribution_count,
          goodsReceived: u.goods_received,
          tier: calcTier(u.contribution_count),
        }));

        return json(leaderboard);
      }

      // ----------------------------------------------------------------
      // Admin endpoints
      // ----------------------------------------------------------------

      // POST /admin/ban — ユーザーを BAN (即時オープン編集を遮断)
      //
      // 編集の巻き戻しは別途 POST /admin/revert-user (本人/admin revert 領域) が担う。
      // ここでは is_banned=1 に加え、BAN 対象が「他人の編集に付けた Good」を撤去する
      // (荒らしアカウントによる Good 水増しを巻き戻す。RedTeam edge_case)。
      // contribution_count は編集件数 (受け取った Good ではない) なので Good 撤去では変えない。
      if (path === "/admin/ban" && request.method === "POST") {
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);
        if (!(await checkIsAdmin(env, user.uid)))
          return error("Forbidden", 403);

        const body = (await request.json()) as any;
        if (!body.user_id) return error("user_id required");
        const targetUserId = body.user_id as string;

        await env.DB.batch([
          env.DB.prepare("UPDATE users SET is_banned = 1 WHERE id = ?").bind(targetUserId),
          // BAN 対象が付けた Good を撤去 (受け手の goods_received は都度 COUNT 算出なので自動で減る)
          env.DB.prepare("DELETE FROM edit_good WHERE user_id = ?").bind(targetUserId),
        ]);

        return json({ banned: targetUserId });
      }

      // ----------------------------------------------------------------
      // POST /admin/revert-user — admin が 1 ユーザーの全編集を一括 revert (also_ban 任意)
      // ----------------------------------------------------------------
      if (path === "/admin/revert-user" && request.method === "POST") {
        return handlePostAdminRevertUser(request, env, { getAuthUser, checkIsAdmin, json, error });
      }

      // ----------------------------------------------------------------
      // GET /admin/users/:id/edits — admin が対象ユーザーの編集 batch 一覧を閲覧
      // ----------------------------------------------------------------
      const adminUserEditsMatch = path.match(/^\/admin\/users\/([^/]+)\/edits$/);
      if (adminUserEditsMatch && request.method === "GET") {
        const targetUserId = decodeURIComponent(adminUserEditsMatch[1]);
        return handleGetAdminUserEdits(
          request,
          url,
          env,
          { getAuthUser, checkIsAdmin, json, error },
          targetUserId
        );
      }

      // ================================================================
      // 予想セトリ API
      // ================================================================

      // ----------------------------------------------------------------
      // GET /me/predictions — 自分が投票した予想一覧 (auth必須)
      // ----------------------------------------------------------------
      // 曲メタ・公演メタは返さず show_id/song_id のみ。iOS が local カタログで解決する
      // (D1 songs ミラー非依存)。
      if (path === "/me/predictions" && request.method === "GET") {
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);
        const { results } = await env.DB.prepare(`
          SELECT spv.show_id, spv.song_id, sp.vote_count, spv.voted_at
          FROM setlist_prediction_votes spv
          LEFT JOIN setlist_predictions sp
            ON sp.show_id = spv.show_id AND sp.song_id = spv.song_id
          WHERE spv.user_id = ?
          ORDER BY spv.voted_at DESC
          LIMIT 200
        `).bind(user.uid).all();
        return json(results.map((r: any) => ({ ...r, vote_count: r.vote_count ?? 1 })));
      }

      // ----------------------------------------------------------------
      // GET /shows/:showId/predictions — 予想一覧 (auth optional)
      // ----------------------------------------------------------------
      // 公演単位の予想に統一 (旧 event-level 予想は 2026-05-28 クリーンスタートで全削除)
      const predictionsGetMatch = path.match(/^\/shows\/([^/]+)\/predictions$/);
      if (predictionsGetMatch && request.method === "GET") {
        const showId = decodeURIComponent(predictionsGetMatch[1]);
        const authUser = await getAuthUser(request, env);
        const uid = authUser?.uid ?? "";

        // 曲メタデータ (title/artwork 等) は返さない。song_id はカタログ非依存の不透明キーとして扱い、
        // 曲名・ジャケ写は iOS が local カタログ (CloudKit が正) から解決する。
        // D1 に songs ミラーを持たせて JOIN すると、新曲追加のたびにズレて取りこぼすため。
        const { results } = await env.DB.prepare(`
          SELECT
            sp.show_id,
            sp.song_id,
            sp.vote_count,
            sp.first_voted_by,
            sp.first_voted_at,
            CASE WHEN spv.user_id IS NOT NULL THEN 1 ELSE 0 END as has_user_voted
          FROM setlist_predictions sp
          LEFT JOIN setlist_prediction_votes spv
            ON spv.show_id = sp.show_id
            AND spv.song_id = sp.song_id
            AND spv.user_id = ?
          WHERE sp.show_id = ?
          ORDER BY sp.vote_count DESC, sp.first_voted_at ASC
        `)
          .bind(uid, showId)
          .all();

        return json(
          results.map((r: any) => ({
            ...r,
            has_user_voted: r.has_user_voted === 1,
          }))
        );
      }

      // ----------------------------------------------------------------
      // POST /shows/:showId/predictions — 投票 (auth必須)
      // ----------------------------------------------------------------
      const predictionsPostMatch = path.match(/^\/shows\/([^/]+)\/predictions$/);
      if (predictionsPostMatch && request.method === "POST") {
        const showId = decodeURIComponent(predictionsPostMatch[1]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const [dbUser, rl] = await Promise.all([
          env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
            .bind(user.uid)
            .first<{ is_banned: number }>(),
          checkRateLimit(env.DB, user.uid, "prediction"),
        ]);
        if (dbUser?.is_banned) return error("Banned", 403);
        if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

        await upsertUser(env, user.uid, user.email);

        const body = (await request.json()) as any;
        const { song_id } = body;
        if (!song_id) return error("song_id is required");

        // 曲存在チェックは行わない。song_id は不透明キーとして保存し、曲メタは iOS local が解決する。
        // (D1 songs ミラーで検証すると、CloudKit にあるが D1 に未同期の新曲が 404 になる)

        const existingVote = await env.DB.prepare(
          "SELECT 1 FROM setlist_prediction_votes WHERE show_id = ? AND song_id = ? AND user_id = ?"
        )
          .bind(showId, song_id, user.uid)
          .first();

        if (existingVote) {
          const current = await env.DB.prepare(
            "SELECT vote_count FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
          )
            .bind(showId, song_id)
            .first<{ vote_count: number }>();
          return json({ song_id, vote_count: current?.vote_count ?? 1, already_voted: true });
        }

        await env.DB.prepare(
          `INSERT INTO setlist_prediction_votes (show_id, song_id, user_id, voted_at)
           VALUES (?, ?, ?, datetime('now'))`
        )
          .bind(showId, song_id, user.uid)
          .run();

        const existing = await env.DB.prepare(
          "SELECT vote_count FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
        )
          .bind(showId, song_id)
          .first<{ vote_count: number }>();

        let voteCount: number;
        if (existing) {
          voteCount = (existing.vote_count ?? 0) + 1;
          await env.DB.prepare(
            "UPDATE setlist_predictions SET vote_count = ? WHERE show_id = ? AND song_id = ?"
          )
            .bind(voteCount, showId, song_id)
            .run();
        } else {
          voteCount = 1;
          await env.DB.prepare(
            `INSERT INTO setlist_predictions (show_id, song_id, vote_count, first_voted_by, first_voted_at)
             VALUES (?, ?, 1, ?, datetime('now'))`
          )
            .bind(showId, song_id, user.uid)
            .run();
        }

        return json({ song_id, vote_count: voteCount, already_voted: false }, 201);
      }

      // ----------------------------------------------------------------
      // DELETE /shows/:showId/predictions/:songId — 投票取消 (auth必須)
      // ----------------------------------------------------------------
      const predictionDeleteMatch = path.match(/^\/shows\/([^/]+)\/predictions\/([^/]+)$/);
      if (predictionDeleteMatch && request.method === "DELETE") {
        const showId = decodeURIComponent(predictionDeleteMatch[1]);
        const songId = decodeURIComponent(predictionDeleteMatch[2]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const vote = await env.DB.prepare(
          "SELECT 1 FROM setlist_prediction_votes WHERE show_id = ? AND song_id = ? AND user_id = ?"
        )
          .bind(showId, songId, user.uid)
          .first();

        if (!vote) {
          return json({ song_id: songId, vote_count: 0, not_voted: true });
        }

        await env.DB.prepare(
          "DELETE FROM setlist_prediction_votes WHERE show_id = ? AND song_id = ? AND user_id = ?"
        )
          .bind(showId, songId, user.uid)
          .run();

        const current = await env.DB.prepare(
          "SELECT vote_count FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
        )
          .bind(showId, songId)
          .first<{ vote_count: number }>();

        const newCount = (current?.vote_count ?? 1) - 1;

        if (newCount <= 0) {
          await env.DB.prepare(
            "DELETE FROM setlist_predictions WHERE show_id = ? AND song_id = ?"
          )
            .bind(showId, songId)
            .run();
        } else {
          await env.DB.prepare(
            "UPDATE setlist_predictions SET vote_count = ? WHERE show_id = ? AND song_id = ?"
          )
            .bind(newCount, showId, songId)
            .run();
        }

        return json({ song_id: songId, vote_count: Math.max(0, newCount) });
      }

      // ----------------------------------------------------------------
      // GET /shows/:showId/songs/:songId/performers — 出演者予想一覧 (auth optional)
      // ----------------------------------------------------------------
      // idol_id は不透明キー。名前/色の解決は iOS ローカル DB が担う (D1 join なし)。
      // has_user_voted を含む user 固有データなので Cache-Control は付けない。
      const performersGetMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/performers$/);
      if (performersGetMatch && request.method === "GET") {
        const showId = decodeURIComponent(performersGetMatch[1]);
        const songId = decodeURIComponent(performersGetMatch[2]);
        const authUser = await getAuthUser(request, env);
        const uid = authUser?.uid ?? "";

        const { results } = await env.DB.prepare(`
          SELECT
            spp.show_id,
            spp.song_id,
            spp.idol_id,
            spp.vote_count,
            spp.first_voted_by,
            spp.first_voted_at,
            CASE WHEN sppv.user_id IS NOT NULL THEN 1 ELSE 0 END as has_user_voted
          FROM setlist_performer_predictions spp
          LEFT JOIN setlist_performer_prediction_votes sppv
            ON sppv.show_id = spp.show_id
            AND sppv.song_id = spp.song_id
            AND sppv.idol_id = spp.idol_id
            AND sppv.user_id = ?
          WHERE spp.show_id = ? AND spp.song_id = ?
          ORDER BY spp.vote_count DESC, spp.first_voted_at ASC
        `)
          .bind(uid, showId, songId)
          .all();

        return json(
          results.map((r: any) => ({
            ...r,
            has_user_voted: r.has_user_voted === 1,
          }))
        );
      }

      // ----------------------------------------------------------------
      // POST /shows/:showId/songs/:songId/performers — 出演者予想投票 (auth必須)
      // ----------------------------------------------------------------
      // 1曲あたり同一 user の投票上限は 8 人 (ユニット曲・全体曲対応のため複数選択許可)。
      const performersPostMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/performers$/);
      if (performersPostMatch && request.method === "POST") {
        const showId = decodeURIComponent(performersPostMatch[1]);
        const songId = decodeURIComponent(performersPostMatch[2]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const dbUser = await env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
          .bind(user.uid)
          .first<{ is_banned: number }>();
        if (dbUser?.is_banned) return error("Banned", 403);

        const body = (await request.json()) as any;
        const { idol_id } = body;
        if (!idol_id) return error("idol_id is required");

        // idol_id は不透明キーとして保存 — 実在検証は行わない (既存 setlist 予想と同方針)。

        // 冪等チェック: 既に投票済みなら集計を増やさず・レートも消費せず即返す。
        const existingVote = await env.DB.prepare(
          "SELECT 1 FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND idol_id = ? AND user_id = ?"
        )
          .bind(showId, songId, idol_id, user.uid)
          .first();

        if (existingVote) {
          const current = await env.DB.prepare(
            "SELECT vote_count FROM setlist_performer_predictions WHERE show_id = ? AND song_id = ? AND idol_id = ?"
          )
            .bind(showId, songId, idol_id)
            .first<{ vote_count: number }>();
          return json({ idol_id, vote_count: current?.vote_count ?? 1, already_voted: true });
        }

        // 新規投票のときだけレートを消費する。
        const rl = await checkRateLimit(env.DB, user.uid, "performer_prediction");
        if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

        await upsertUser(env, user.uid, user.email);

        // 1曲あたりの投票数上限チェック (8人まで)
        const userVoteCount = await env.DB.prepare(
          "SELECT COUNT(*) as cnt FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND user_id = ?"
        )
          .bind(showId, songId, user.uid)
          .first<{ cnt: number }>();

        if ((userVoteCount?.cnt ?? 0) >= 8) {
          return error("Too many votes: max 8 performers per song", 422);
        }

        // votes INSERT + 集計の原子 upsert を batch で実行。
        // first_voted_by/at は INSERT 時のみ入り、ON CONFLICT 側では触らない (最初の投票者を保持)。
        const insertVote = env.DB.prepare(
          `INSERT INTO setlist_performer_prediction_votes (show_id, song_id, idol_id, user_id, voted_at)
           VALUES (?, ?, ?, ?, datetime('now'))`
        ).bind(showId, songId, idol_id, user.uid);
        const upsertCount = env.DB.prepare(
          `INSERT INTO setlist_performer_predictions (show_id, song_id, idol_id, vote_count, first_voted_by, first_voted_at)
           VALUES (?, ?, ?, 1, ?, datetime('now'))
           ON CONFLICT(show_id, song_id, idol_id) DO UPDATE SET vote_count = vote_count + 1
           RETURNING vote_count`
        ).bind(showId, songId, idol_id, user.uid);
        const [, countResult] = await env.DB.batch<{ vote_count: number }>([
          insertVote,
          upsertCount,
        ]);
        const voteCount = countResult.results[0]?.vote_count ?? 1;

        return json({ idol_id, vote_count: voteCount, already_voted: false }, 201);
      }

      // ----------------------------------------------------------------
      // DELETE /shows/:showId/songs/:songId/performers/:idolId — 出演者予想取消 (auth必須)
      // ----------------------------------------------------------------
      const performersDeleteMatch = path.match(
        /^\/shows\/([^/]+)\/songs\/([^/]+)\/performers\/([^/]+)$/
      );
      if (performersDeleteMatch && request.method === "DELETE") {
        const showId = decodeURIComponent(performersDeleteMatch[1]);
        const songId = decodeURIComponent(performersDeleteMatch[2]);
        const idolId = decodeURIComponent(performersDeleteMatch[3]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const vote = await env.DB.prepare(
          "SELECT 1 FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND idol_id = ? AND user_id = ?"
        )
          .bind(showId, songId, idolId, user.uid)
          .first();

        if (!vote) {
          return json({ idol_id: idolId, vote_count: 0, not_voted: true });
        }

        // votes DELETE + 集計の原子デクリメント (MAX で負値防止) を batch で実行。
        const deleteVote = env.DB.prepare(
          "DELETE FROM setlist_performer_prediction_votes WHERE show_id = ? AND song_id = ? AND idol_id = ? AND user_id = ?"
        ).bind(showId, songId, idolId, user.uid);
        const decrementCount = env.DB.prepare(
          `UPDATE setlist_performer_predictions SET vote_count = MAX(0, vote_count - 1)
           WHERE show_id = ? AND song_id = ? AND idol_id = ?
           RETURNING vote_count`
        ).bind(showId, songId, idolId);
        const [, countResult] = await env.DB.batch<{ vote_count: number }>([
          deleteVote,
          decrementCount,
        ]);
        const newCount = countResult.results[0]?.vote_count ?? 0;

        // 0 になったら集計行を削除 (既存挙動を維持)。
        if (newCount <= 0) {
          await env.DB.prepare(
            "DELETE FROM setlist_performer_predictions WHERE show_id = ? AND song_id = ? AND idol_id = ?"
          )
            .bind(showId, songId, idolId)
            .run();
        }

        return json({ idol_id: idolId, vote_count: newCount });
      }

      // ----------------------------------------------------------------
      // GET /shows/:showId/likes — セトリ post-vote 集計 + 自分の like 状態
      // ----------------------------------------------------------------
      // ライブ後にユーザが「この曲良かった」と複数選択する star toggle 用。
      // 集計は count(*) で都度算出 (低トラフィック前提)。
      const likesGetMatch = path.match(/^\/shows\/([^/]+)\/likes$/);
      if (likesGetMatch && request.method === "GET") {
        const showId = decodeURIComponent(likesGetMatch[1]);
        const authUser = await getAuthUser(request, env);
        const uid = authUser?.uid ?? "";

        const { results } = await env.DB.prepare(`
          SELECT
            l.song_id,
            COUNT(*) AS like_count,
            MAX(CASE WHEN l.user_id = ? THEN 1 ELSE 0 END) AS has_user_liked
          FROM setlist_song_likes l
          WHERE l.show_id = ?
          GROUP BY l.song_id
        `)
          .bind(uid, showId)
          .all();

        return json(
          results.map((r: any) => ({
            song_id: r.song_id,
            like_count: r.like_count,
            has_user_liked: r.has_user_liked === 1,
          }))
        );
      }

      // ----------------------------------------------------------------
      // POST /shows/:showId/songs/:songId/like — like 登録 (auth必須、 idempotent)
      // ----------------------------------------------------------------
      const likePostMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/like$/);
      if (likePostMatch && request.method === "POST") {
        const showId = decodeURIComponent(likePostMatch[1]);
        const songId = decodeURIComponent(likePostMatch[2]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const dbUser = await env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
          .bind(user.uid)
          .first<{ is_banned: number }>();
        if (dbUser?.is_banned) return error("Banned", 403);

        await upsertUser(env, user.uid, user.email);

        await env.DB.prepare(
          `INSERT OR IGNORE INTO setlist_song_likes (show_id, song_id, user_id, liked_at)
           VALUES (?, ?, ?, datetime('now'))`
        )
          .bind(showId, songId, user.uid)
          .run();

        const count = await env.DB.prepare(
          "SELECT COUNT(*) AS c FROM setlist_song_likes WHERE show_id = ? AND song_id = ?"
        )
          .bind(showId, songId)
          .first<{ c: number }>();

        return json({ song_id: songId, like_count: count?.c ?? 1, liked: true });
      }

      // ----------------------------------------------------------------
      // DELETE /shows/:showId/songs/:songId/like — like 解除
      // ----------------------------------------------------------------
      const likeDeleteMatch = path.match(/^\/shows\/([^/]+)\/songs\/([^/]+)\/like$/);
      if (likeDeleteMatch && request.method === "DELETE") {
        const showId = decodeURIComponent(likeDeleteMatch[1]);
        const songId = decodeURIComponent(likeDeleteMatch[2]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        await env.DB.prepare(
          "DELETE FROM setlist_song_likes WHERE show_id = ? AND song_id = ? AND user_id = ?"
        )
          .bind(showId, songId, user.uid)
          .run();

        const count = await env.DB.prepare(
          "SELECT COUNT(*) AS c FROM setlist_song_likes WHERE show_id = ? AND song_id = ?"
        )
          .bind(showId, songId)
          .first<{ c: number }>();

        return json({ song_id: songId, like_count: count?.c ?? 0, liked: false });
      }

      // ================================================================
      // みんなの投票 (Community Theme Polls) API
      // ================================================================

      // ----------------------------------------------------------------
      // GET /polls?status=active|past&limit&offset — 投票一覧 (auth任意)
      // ----------------------------------------------------------------
      // active = status='active' AND ends_at > now
      // past   = status='active' AND ends_at <= now
      if (path === "/polls" && request.method === "GET") {
        const authUser = await getAuthUser(request, env);
        const uid = authUser?.uid ?? "";
        const statusParam = url.searchParams.get("status") ?? "active";
        const limit = parsePositiveInt(url.searchParams.get("limit"), 20, 100);
        const offset = parsePositiveInt(url.searchParams.get("offset"), 0, Number.MAX_SAFE_INTEGER);

        const isActive = statusParam !== "past";
        const timeCondition = isActive ? "ends_at > datetime('now')" : "ends_at <= datetime('now')";
        const orderBy = isActive ? "ends_at ASC" : "ends_at DESC";

        // 日付は iOS デコーダ (.secondsSince1970) に合わせ epoch 秒の数値で返す
        const { results } = await env.DB.prepare(`
          SELECT
            p.id,
            p.title,
            p.description,
            p.target_type,
            p.created_by,
            CAST(strftime('%s', p.created_at) AS INTEGER) AS created_at,
            CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
            p.status,
            COALESCE(SUM(pe.vote_count), 0) AS total_votes,
            COUNT(pe.entity_id) AS entry_count,
            (SELECT COUNT(*) FROM poll_votes pv WHERE pv.poll_id = p.id AND pv.user_id = ?) AS my_vote_count
          FROM polls p
          LEFT JOIN poll_entries pe ON pe.poll_id = p.id
          WHERE p.status = 'active' AND ${timeCondition}
          GROUP BY p.id
          ORDER BY ${orderBy}
          LIMIT ? OFFSET ?
        `)
          .bind(uid, limit, offset)
          .all();

        return json(
          results.map((r: any) => ({
            id: r.id,
            title: r.title,
            description: r.description,
            target_type: r.target_type,
            created_by: r.created_by,
            created_at: r.created_at,
            ends_at: r.ends_at,
            status: r.status,
            total_votes: r.total_votes,
            entry_count: r.entry_count,
            my_vote_count: r.my_vote_count,
          }))
        );
      }

      // ----------------------------------------------------------------
      // GET /polls/results — 終了したお題の結果(優勝者) 一覧 (公開・殿堂用)
      //   ※ /polls/:id より前に置く (results が :id に食われないように)
      // ----------------------------------------------------------------
      if (path === "/polls/results" && request.method === "GET") {
        const { results } = await env.DB.prepare(
          `SELECT poll_id, title, target_type, ends_at, entity_id, vote_count
             FROM (
               SELECT p.id AS poll_id, p.title, p.target_type,
                      CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
                      pe.entity_id, pe.vote_count,
                      RANK() OVER (PARTITION BY p.id ORDER BY pe.vote_count DESC) AS rnk
                 FROM polls p
                 JOIN poll_entries pe ON pe.poll_id = p.id
                WHERE p.status = 'active'
                  AND p.ends_at < datetime('now')
                  AND pe.vote_count > 0
             )
            WHERE rnk = 1
            ORDER BY ends_at DESC
            LIMIT 50`
        ).all();
        // 同点1位は複数行返るので poll_id 単位で先頭のみ採用。
        const seen = new Set<string>();
        const winners = (results as any[]).filter((r) => {
          if (seen.has(r.poll_id)) return false;
          seen.add(r.poll_id);
          return true;
        });
        return json(winners, 200, { "Cache-Control": "public, max-age=300" });
      }

      // ----------------------------------------------------------------
      // GET /polls/achievements/:entityId — その曲/アイドルが終了お題で取った順位 (上位3位まで)
      // ----------------------------------------------------------------
      const pollAchvMatch = path.match(/^\/polls\/achievements\/([^/]+)$/);
      if (pollAchvMatch && request.method === "GET") {
        const entityId = decodeURIComponent(pollAchvMatch[1]);
        const { results } = await env.DB.prepare(
          `SELECT poll_id, title, target_type, ends_at, vote_count, rnk
             FROM (
               SELECT p.id AS poll_id, p.title, p.target_type,
                      CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
                      pe.entity_id, pe.vote_count,
                      RANK() OVER (PARTITION BY p.id ORDER BY pe.vote_count DESC) AS rnk
                 FROM polls p
                 JOIN poll_entries pe ON pe.poll_id = p.id
                WHERE p.status = 'active'
                  AND p.ends_at < datetime('now')
                  AND pe.vote_count > 0
             )
            WHERE entity_id = ? AND rnk <= 3
            ORDER BY rnk ASC, ends_at DESC
            LIMIT 20`
        ).bind(entityId).all();
        return json(results, 200, { "Cache-Control": "public, max-age=300" });
      }

      // ----------------------------------------------------------------
      // GET /polls/:id — 投票詳細 (auth任意)
      // ----------------------------------------------------------------
      const pollGetMatch = path.match(/^\/polls\/([^/]+)$/);
      if (pollGetMatch && request.method === "GET") {
        const pollId = decodeURIComponent(pollGetMatch[1]);
        const authUser = await getAuthUser(request, env);
        const uid = authUser?.uid ?? "";

        const poll = await env.DB.prepare(`
          SELECT
            p.id,
            p.title,
            p.description,
            p.target_type,
            p.created_by,
            CAST(strftime('%s', p.created_at) AS INTEGER) AS created_at,
            CAST(strftime('%s', p.ends_at) AS INTEGER) AS ends_at,
            p.status,
            COALESCE(SUM(pe.vote_count), 0) AS total_votes,
            COUNT(pe.entity_id) AS entry_count
          FROM polls p
          LEFT JOIN poll_entries pe ON pe.poll_id = p.id
          WHERE p.id = ?
          GROUP BY p.id
        `)
          .bind(pollId)
          .first<any>();

        if (!poll) return error("Poll not found", 404);

        const { results: entries } = await env.DB.prepare(`
          SELECT
            pe.entity_id,
            pe.vote_count,
            CASE WHEN pv.user_id IS NOT NULL THEN 1 ELSE 0 END AS has_user_voted
          FROM poll_entries pe
          LEFT JOIN poll_votes pv
            ON pv.poll_id = pe.poll_id
            AND pv.entity_id = pe.entity_id
            AND pv.user_id = ?
          WHERE pe.poll_id = ?
          ORDER BY pe.vote_count DESC, pe.first_voted_at ASC
        `)
          .bind(uid, pollId)
          .all<any>();

        const myVoteRow = await env.DB.prepare(
          "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
        )
          .bind(pollId, uid)
          .first<{ c: number }>();

        return json({
          poll: {
            id: poll.id,
            title: poll.title,
            description: poll.description,
            target_type: poll.target_type,
            created_by: poll.created_by,
            created_at: poll.created_at,
            ends_at: poll.ends_at,
            status: poll.status,
            total_votes: poll.total_votes,
            entry_count: poll.entry_count,
          },
          entries: entries.map((e: any) => ({
            entity_id: e.entity_id,
            vote_count: e.vote_count,
            has_user_voted: e.has_user_voted === 1,
          })),
          my_vote_count: myVoteRow?.c ?? 0,
        });
      }

      // ----------------------------------------------------------------
      // POST /polls — お題作成 (auth必須・rate limit "poll")
      // ----------------------------------------------------------------
      if (path === "/polls" && request.method === "POST") {
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const [dbUser, rl] = await Promise.all([
          env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
            .bind(user.uid)
            .first<{ is_banned: number }>(),
          checkRateLimit(env.DB, user.uid, "poll"),
        ]);
        if (dbUser?.is_banned) return error("Banned", 403);
        if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

        await upsertUser(env, user.uid, user.email);

        const body = (await request.json()) as any;
        const { title, description, target_type, days } = body;

        if (!title || typeof title !== "string" || title.trim().length === 0) {
          return error("title is required");
        }
        if (title.trim().length > 80) {
          return error("title must be 80 characters or less");
        }
        if (description !== undefined && description !== null) {
          if (typeof description !== "string" || description.length > 280) {
            return error("description must be 280 characters or less");
          }
        }
        if (!target_type || (target_type !== "song" && target_type !== "idol")) {
          return error("target_type must be 'song' or 'idol'");
        }

        const daysNum = typeof days === "number" ? Math.min(Math.max(1, Math.floor(days)), 30) : 14;
        const pollId = crypto.randomUUID();
        const now = new Date();
        const endsAt = new Date(now.getTime() + daysNum * 24 * 60 * 60 * 1000);
        const endsAtStr = endsAt.toISOString().replace("T", " ").replace(/\.\d{3}Z$/, "");

        await env.DB.prepare(
          `INSERT INTO polls (id, title, description, target_type, created_by, ends_at)
           VALUES (?, ?, ?, ?, ?, ?)`
        )
          .bind(pollId, title.trim(), description ?? null, target_type, user.uid, endsAtStr)
          .run();

        const created = await env.DB.prepare(
          `SELECT id, title, description, target_type, created_by,
                  CAST(strftime('%s', created_at) AS INTEGER) AS created_at,
                  CAST(strftime('%s', ends_at) AS INTEGER) AS ends_at,
                  status
           FROM polls WHERE id = ?`
        )
          .bind(pollId)
          .first<any>();

        return json(
          {
            id: created.id,
            title: created.title,
            description: created.description,
            target_type: created.target_type,
            created_by: created.created_by,
            created_at: created.created_at,
            ends_at: created.ends_at,
            status: created.status,
            total_votes: 0,
            entry_count: 0,
          },
          201
        );
      }

      // ----------------------------------------------------------------
      // POST /polls/:id/votes — 投票 (auth必須・rate limit "poll_vote")
      // ----------------------------------------------------------------
      const pollVotePostMatch = path.match(/^\/polls\/([^/]+)\/votes$/);
      if (pollVotePostMatch && request.method === "POST") {
        const pollId = decodeURIComponent(pollVotePostMatch[1]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const [dbUser, rl] = await Promise.all([
          env.DB.prepare("SELECT is_banned FROM users WHERE id = ?")
            .bind(user.uid)
            .first<{ is_banned: number }>(),
          checkRateLimit(env.DB, user.uid, "poll_vote"),
        ]);
        if (dbUser?.is_banned) return error("Banned", 403);
        if (!rl.allowed) return rateLimitResponse(rl.used, rl.limit, rl.reset_at);

        await upsertUser(env, user.uid, user.email);

        const body = (await request.json()) as any;
        const { entity_id } = body;
        if (!entity_id) return error("entity_id is required");

        // poll 存在確認 + active チェック
        const poll = await env.DB.prepare(
          "SELECT id, status, ends_at FROM polls WHERE id = ?"
        )
          .bind(pollId)
          .first<{ id: string; status: string; ends_at: string }>();

        if (!poll) return error("Poll not found", 404);
        if (poll.status !== "active") {
          return error("Poll is not active", 409);
        }
        // ends_at は SQLite の datetime 文字列 "YYYY-MM-DD HH:MM:SS" または ISO
        const endsAtMs = new Date(poll.ends_at.replace(" ", "T") + (poll.ends_at.includes("T") ? "" : "Z")).getTime();
        if (Date.now() > endsAtMs) {
          return error("Poll has ended", 409);
        }

        // 3票上限チェック
        const myVoteRow = await env.DB.prepare(
          "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
        )
          .bind(pollId, user.uid)
          .first<{ c: number }>();
        const myVoteCount = myVoteRow?.c ?? 0;
        if (myVoteCount >= 3) {
          return error("vote limit", 409);
        }

        // 二重投票チェック（PK 制約でも弾かれるが先に返す）
        const existing = await env.DB.prepare(
          "SELECT 1 FROM poll_votes WHERE poll_id = ? AND entity_id = ? AND user_id = ?"
        )
          .bind(pollId, entity_id, user.uid)
          .first();
        if (existing) {
          const entry = await env.DB.prepare(
            "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
          )
            .bind(pollId, entity_id)
            .first<{ vote_count: number }>();
          return json({ entity_id, vote_count: entry?.vote_count ?? 0, my_vote_count: myVoteCount }, 200);
        }

        // 投票レコード追加
        await env.DB.prepare(
          `INSERT INTO poll_votes (poll_id, entity_id, user_id, voted_at)
           VALUES (?, ?, ?, datetime('now'))`
        )
          .bind(pollId, entity_id, user.uid)
          .run();

        // poll_entries upsert
        const entryExists = await env.DB.prepare(
          "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
        )
          .bind(pollId, entity_id)
          .first<{ vote_count: number }>();

        let newVoteCount: number;
        if (entryExists) {
          newVoteCount = (entryExists.vote_count ?? 0) + 1;
          await env.DB.prepare(
            "UPDATE poll_entries SET vote_count = ? WHERE poll_id = ? AND entity_id = ?"
          )
            .bind(newVoteCount, pollId, entity_id)
            .run();
        } else {
          newVoteCount = 1;
          await env.DB.prepare(
            `INSERT INTO poll_entries (poll_id, entity_id, vote_count, first_voted_by, first_voted_at)
             VALUES (?, ?, 1, ?, datetime('now'))`
          )
            .bind(pollId, entity_id, user.uid)
            .run();
        }

        return json({ entity_id, vote_count: newVoteCount, my_vote_count: myVoteCount + 1 }, 201);
      }

      // ----------------------------------------------------------------
      // DELETE /polls/:id/votes/:entityId — 投票取消 (auth必須)
      // ----------------------------------------------------------------
      const pollVoteDeleteMatch = path.match(/^\/polls\/([^/]+)\/votes\/([^/]+)$/);
      if (pollVoteDeleteMatch && request.method === "DELETE") {
        const pollId = decodeURIComponent(pollVoteDeleteMatch[1]);
        const entityId = decodeURIComponent(pollVoteDeleteMatch[2]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const vote = await env.DB.prepare(
          "SELECT 1 FROM poll_votes WHERE poll_id = ? AND entity_id = ? AND user_id = ?"
        )
          .bind(pollId, entityId, user.uid)
          .first();

        if (!vote) {
          const entry = await env.DB.prepare(
            "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
          )
            .bind(pollId, entityId)
            .first<{ vote_count: number }>();
          const myVoteRow = await env.DB.prepare(
            "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
          )
            .bind(pollId, user.uid)
            .first<{ c: number }>();
          return json({ entity_id: entityId, vote_count: entry?.vote_count ?? 0, my_vote_count: myVoteRow?.c ?? 0 });
        }

        await env.DB.prepare(
          "DELETE FROM poll_votes WHERE poll_id = ? AND entity_id = ? AND user_id = ?"
        )
          .bind(pollId, entityId, user.uid)
          .run();

        const currentEntry = await env.DB.prepare(
          "SELECT vote_count FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
        )
          .bind(pollId, entityId)
          .first<{ vote_count: number }>();

        const newCount = (currentEntry?.vote_count ?? 1) - 1;

        if (newCount <= 0) {
          await env.DB.prepare(
            "DELETE FROM poll_entries WHERE poll_id = ? AND entity_id = ?"
          )
            .bind(pollId, entityId)
            .run();
        } else {
          await env.DB.prepare(
            "UPDATE poll_entries SET vote_count = ? WHERE poll_id = ? AND entity_id = ?"
          )
            .bind(newCount, pollId, entityId)
            .run();
        }

        const myVoteRow = await env.DB.prepare(
          "SELECT COUNT(*) AS c FROM poll_votes WHERE poll_id = ? AND user_id = ?"
        )
          .bind(pollId, user.uid)
          .first<{ c: number }>();

        return json({ entity_id: entityId, vote_count: Math.max(0, newCount), my_vote_count: myVoteRow?.c ?? 0 });
      }

      // ----------------------------------------------------------------
      // DELETE /polls/:id — お題削除（作成者本人 or admin → status='removed'）
      // ----------------------------------------------------------------
      const pollDeleteMatch = path.match(/^\/polls\/([^/]+)$/);
      if (pollDeleteMatch && request.method === "DELETE") {
        const pollId = decodeURIComponent(pollDeleteMatch[1]);
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);

        const poll = await env.DB.prepare(
          "SELECT id, created_by, status FROM polls WHERE id = ?"
        )
          .bind(pollId)
          .first<{ id: string; created_by: string; status: string }>();

        if (!poll) return error("Poll not found", 404);

        const isAdmin = await checkIsAdmin(env, user.uid);
        if (poll.created_by !== user.uid && !isAdmin) {
          return error("Forbidden", 403);
        }

        await env.DB.prepare("UPDATE polls SET status = 'removed' WHERE id = ?")
          .bind(pollId)
          .run();

        return json({ id: pollId, status: "removed" });
      }

      // ================================================================
      // コミュニティ集計 API
      // ================================================================

      // ----------------------------------------------------------------
      // POST /favorites/toggle — お気に入り登録/解除
      // ----------------------------------------------------------------
      if (path === "/favorites/toggle" && request.method === "POST") {
        const deviceId = request.headers.get("X-Device-Id");
        if (!deviceId) return error("X-Device-Id header is required");

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const ipDry = await dryCheckIpRateLimit(env.DB, ip);
        if (!ipDry.allowed) {
          return rateLimitSimple();
        }

        const body = (await request.json()) as any;
        const { song_id, value } = body;
        if (!song_id) return error("song_id is required");
        if (typeof value !== "boolean") return error("value must be boolean");

        if (value) {
          // お気に入り追加: device upsert + count++ を batch
          const insertDevice = env.DB.prepare(
            `INSERT OR IGNORE INTO device_song_favorite (device_id, song_id, created_at) VALUES (?, ?, ?)`
          ).bind(deviceId, song_id, Math.floor(Date.now() / 1000));
          const upsertCount = env.DB.prepare(
            `INSERT INTO song_favorites (song_id, count) VALUES (?, 1)
             ON CONFLICT(song_id) DO UPDATE SET count = count + 1`
          ).bind(song_id);
          await env.DB.batch([insertDevice, upsertCount]);
        } else {
          // お気に入り解除: device delete + count-- を batch (count は MAX(0,...) で防御)
          const deleteDevice = env.DB.prepare(
            "DELETE FROM device_song_favorite WHERE device_id = ? AND song_id = ?"
          ).bind(deviceId, song_id);
          const decrementCount = env.DB.prepare(
            `UPDATE song_favorites SET count = MAX(0, count - 1) WHERE song_id = ?`
          ).bind(song_id);
          await env.DB.batch([deleteDevice, decrementCount]);
        }

        const row = await env.DB.prepare(
          "SELECT count FROM song_favorites WHERE song_id = ?"
        )
          .bind(song_id)
          .first<{ count: number }>();

        await commitIpRateLimit(env.DB, ip, ipDry.bucket);
        return json({ song_id, count: row?.count ?? 0 });
      }

      // ----------------------------------------------------------------
      // GET /favorites/ranking — お気に入りランキング
      // ----------------------------------------------------------------
      if (path === "/favorites/ranking" && request.method === "GET") {
        // コミュニティ集計 (song_id, count) のみ返す。曲名・ブランド・ジャケ写は返さない。
        // D1 の songs はコードから書かれない陳腐化ミラーで、新曲が JOIN で脱落する/
        // s.artist カラムが存在せずクエリ自体が壊れるため、ミラー依存を撤去した。
        // ブランド絞り込みと曲メタ解決は iOS local カタログ側で行う (予想機能と同方針)。
        const limit = parsePositiveInt(url.searchParams.get("limit"), 200, 1000);

        const { results } = await env.DB.prepare(
          `SELECT song_id, count FROM song_favorites
           ORDER BY count DESC LIMIT ?`
        )
          .bind(limit)
          .all();
        // ランキングはコミュニティ集計 (song_id, count) のみでユーザー非依存。
        // 画面を開くたびに叩かれるが順位変動は緩やかなので、エッジで全ユーザ共有
        // キャッシュ (max-age 60s + SWR 300s)。集計なので多少の鮮度落ちは許容。
        return json(results, 200, {
          "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
        });
      }

      // ----------------------------------------------------------------
      // GET /penlight/palette — パレット一覧
      // ----------------------------------------------------------------
      if (path === "/penlight/palette" && request.method === "GET") {
        const { results } = await env.DB.prepare(
          "SELECT * FROM penlight_palette ORDER BY sort_order"
        ).all();
        return json(results);
      }

      // ----------------------------------------------------------------
      // POST /penlight/vote — ペンライト色セット投票
      // ----------------------------------------------------------------
      if (path === "/penlight/vote" && request.method === "POST") {
        const deviceId = request.headers.get("X-Device-Id");
        if (!deviceId) return error("X-Device-Id header is required");

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const ipDry = await dryCheckIpRateLimit(env.DB, ip);
        if (!ipDry.allowed) {
          return rateLimitSimple();
        }

        const body = (await request.json()) as any;
        const { song_id, colors } = body;
        if (!song_id) return error("song_id is required");
        if (!Array.isArray(colors) || colors.length === 0) return error("colors must be a non-empty array");

        const colorSetKey = [...colors].sort().join("-");

        // 既存投票を確認して差し替え
        const existing = await env.DB.prepare(
          "SELECT color_set_key FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
        )
          .bind(deviceId, song_id)
          .first<{ color_set_key: string }>();

        const stmts: D1PreparedStatement[] = [];

        if (existing && existing.color_set_key !== colorSetKey) {
          // 旧セットを -1 (MAX(0,...) で防御) + 0以下なら削除
          stmts.push(
            env.DB.prepare(
              `UPDATE penlight_color_set_votes SET count = MAX(0, count - 1)
               WHERE song_id = ? AND color_set_key = ?`
            ).bind(song_id, existing.color_set_key),
            env.DB.prepare(
              `DELETE FROM penlight_color_set_votes WHERE song_id = ? AND color_set_key = ? AND count <= 0`
            ).bind(song_id, existing.color_set_key)
          );
        }

        if (!existing || existing.color_set_key !== colorSetKey) {
          // 新セットを +1
          stmts.push(
            env.DB.prepare(
              `INSERT INTO penlight_color_set_votes (song_id, color_set_key, count) VALUES (?, ?, 1)
               ON CONFLICT(song_id, color_set_key) DO UPDATE SET count = count + 1`
            ).bind(song_id, colorSetKey)
          );
        }

        // 端末投票レコードをupsert
        stmts.push(
          env.DB.prepare(
            `INSERT INTO device_song_penlight (device_id, song_id, color_set_key, created_at)
             VALUES (?, ?, ?, ?)
             ON CONFLICT(device_id, song_id) DO UPDATE SET color_set_key = excluded.color_set_key, created_at = excluded.created_at`
          ).bind(deviceId, song_id, colorSetKey, Math.floor(Date.now() / 1000))
        );

        if (stmts.length > 0) await env.DB.batch(stmts);

        const row = await env.DB.prepare(
          "SELECT count FROM penlight_color_set_votes WHERE song_id = ? AND color_set_key = ?"
        )
          .bind(song_id, colorSetKey)
          .first<{ count: number }>();

        await commitIpRateLimit(env.DB, ip, ipDry.bucket);
        return json({ song_id, color_set_key: colorSetKey, count: row?.count ?? 1 });
      }

      // ----------------------------------------------------------------
      // DELETE /penlight/vote — 投票取消
      // ----------------------------------------------------------------
      if (path === "/penlight/vote" && request.method === "DELETE") {
        const deviceId = request.headers.get("X-Device-Id");
        if (!deviceId) return error("X-Device-Id header is required");

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const ipDry = await dryCheckIpRateLimit(env.DB, ip);
        if (!ipDry.allowed) {
          return rateLimitSimple();
        }

        const songId = url.searchParams.get("song_id");
        if (!songId) return error("song_id is required");

        const existing = await env.DB.prepare(
          "SELECT color_set_key FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
        )
          .bind(deviceId, songId)
          .first<{ color_set_key: string }>();

        if (!existing) return json({ song_id: songId, cancelled: false });

        // count-1 / 0以下で DELETE / device削除 を batch で原子化
        await env.DB.batch([
          env.DB.prepare(
            `UPDATE penlight_color_set_votes SET count = MAX(0, count - 1)
             WHERE song_id = ? AND color_set_key = ?`
          ).bind(songId, existing.color_set_key),
          env.DB.prepare(
            `DELETE FROM penlight_color_set_votes WHERE song_id = ? AND color_set_key = ? AND count <= 0`
          ).bind(songId, existing.color_set_key),
          env.DB.prepare(
            "DELETE FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
          ).bind(deviceId, songId),
        ]);

        await commitIpRateLimit(env.DB, ip, ipDry.bucket);
        return json({ song_id: songId, cancelled: true });
      }

      // ----------------------------------------------------------------
      // GET /penlight/votes/:song_id — 投票結果
      // ----------------------------------------------------------------
      const penlightVotesMatch = path.match(/^\/penlight\/votes\/([^/]+)$/);
      if (penlightVotesMatch && request.method === "GET") {
        const songId = decodeURIComponent(penlightVotesMatch[1]);
        const deviceId = request.headers.get("X-Device-Id");

        const { results: topSets } = await env.DB.prepare(
          `SELECT color_set_key, count FROM penlight_color_set_votes
           WHERE song_id = ? ORDER BY count DESC LIMIT 5`
        )
          .bind(songId)
          .all<{ color_set_key: string; count: number }>();

        const totalRow = await env.DB.prepare(
          `SELECT SUM(count) as total FROM penlight_color_set_votes WHERE song_id = ?`
        )
          .bind(songId)
          .first<{ total: number }>();

        let myVote: { color_set_key: string; colors: string[] } | null = null;
        if (deviceId) {
          const myRow = await env.DB.prepare(
            "SELECT color_set_key FROM device_song_penlight WHERE device_id = ? AND song_id = ?"
          )
            .bind(deviceId, songId)
            .first<{ color_set_key: string }>();
          if (myRow) {
            myVote = {
              color_set_key: myRow.color_set_key,
              colors: myRow.color_set_key.split("-"),
            };
          }
        }

        const top_sets = topSets.map((row) => ({
          key: row.color_set_key,
          colors: row.color_set_key.split("-"),
          count: row.count,
        }));

        return json({
          top_sets,
          total_votes: totalRow?.total ?? 0,
          my_vote: myVote,
        });
      }

      // ================================================================
      // ユーザータグ API
      // ================================================================

      // ----------------------------------------------------------------
      // POST /tags — タグ新規作成
      // ----------------------------------------------------------------
      if (path === "/tags" && request.method === "POST") {
        const deviceId = request.headers.get("X-Device-Id");
        if (!deviceId) return error("X-Device-Id header is required");

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const ipDry = await dryCheckIpRateLimit(env.DB, ip);
        if (!ipDry.allowed) {
          return rateLimitSimple();
        }

        const body = (await request.json()) as any;
        let { name, description, category, color } = body as {
          name: string;
          description?: string;
          category?: string;
          color?: string;
        };

        if (!name || typeof name !== "string") return error("name is required");
        name = name.trim();
        if (name.length < 1 || name.length > 30) return error("name must be 1-30 characters");

        // 同名チェック
        const existingByName = await env.DB.prepare("SELECT * FROM tags WHERE name = ?").bind(name).first();
        if (existingByName) return json({ tag: existingByName, created: false }, 409);

        // レート制限: 当日10件まで (INSERT OR IGNORE で初期化 → UPDATE で加算、quota check と quota increment を batch)
        const dateYmd = new Date().toISOString().slice(0, 10);
        await env.DB.prepare(
          `INSERT OR IGNORE INTO device_tag_create_quota (device_id, date_ymd, count) VALUES (?, ?, 0)`
        ).bind(deviceId, dateYmd).run();
        const quotaRow = await env.DB.prepare(
          "SELECT count FROM device_tag_create_quota WHERE device_id = ? AND date_ymd = ?"
        ).bind(deviceId, dateYmd).first<{ count: number }>();
        if ((quotaRow?.count ?? 0) >= 10) return error("Daily tag creation limit reached", 429);

        const candidateId = await resolveSlug(env.DB, name);
        const now = Math.floor(Date.now() / 1000);

        // tag INSERT + quota++ を batch で原子化 (race condition 解消)
        await env.DB.batch([
          env.DB.prepare(
            `INSERT INTO tags (id, name, description, category, color, created_by, created_at, updated_at, is_official, status)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 'active')`
          ).bind(candidateId, name, description ?? null, category ?? null, color ?? null, deviceId, now, now),
          env.DB.prepare(
            `UPDATE device_tag_create_quota SET count = count + 1
             WHERE device_id = ? AND date_ymd = ?`
          ).bind(deviceId, dateYmd),
        ]);

        const tag = await env.DB.prepare("SELECT * FROM tags WHERE id = ?").bind(candidateId).first();
        await commitIpRateLimit(env.DB, ip, ipDry.bucket);
        return json({ tag, created: true }, 201);
      }

      // ----------------------------------------------------------------
      // GET /tags — タグ一覧検索
      // ----------------------------------------------------------------
      if (path === "/tags" && request.method === "GET") {
        const search = url.searchParams.get("search") || "";
        const category = url.searchParams.get("category") || "";
        const sort = url.searchParams.get("sort") || "popular";
        const limit = parsePositiveInt(url.searchParams.get("limit"), 50, 100);
        const offset = Math.min(10000, Math.max(0, parseInt(url.searchParams.get("offset") || "0") || 0));

        const params: unknown[] = [];
        const conditions: string[] = ["t.status != 'removed'"];

        if (search) {
          conditions.push("t.name LIKE ? ESCAPE '\\'");
          params.push(`%${escapeLike(search)}%`);
        }
        if (category) {
          conditions.push("t.category = ?");
          params.push(category);
        }

        const where = conditions.length ? "WHERE " + conditions.join(" AND ") : "";

        let orderBy = "ORDER BY t.name ASC";
        if (sort === "popular") orderBy = "ORDER BY COALESCE(total_uses, 0) DESC";
        else if (sort === "recent") orderBy = "ORDER BY t.created_at DESC";

        const sql = `
          SELECT t.id, t.name, SUBSTR(t.description, 1, 40) as description_preview,
                 t.category, t.color, t.created_at,
                 COALESCE(SUM(st.vote_count), 0) as total_uses
          FROM tags t
          LEFT JOIN song_tags st ON st.tag_id = t.id
          ${where}
          GROUP BY t.id
          ${orderBy}
          LIMIT ? OFFSET ?
        `;
        params.push(limit, offset);

        const { results } = await env.DB.prepare(sql).bind(...params).all();

        const countSql = `SELECT COUNT(*) as cnt FROM tags t ${where}`;
        const countRow = await env.DB.prepare(countSql).bind(...params.slice(0, params.length - 2)).first<{ cnt: number }>();

        // タグ一覧はユーザー非依存・変化が緩やかなので短期キャッシュを許可
        // (タグ追加 UI の再オープン高速化。max-age 60s + SWR 300s)。
        return json({ tags: results, total: countRow?.cnt ?? 0 }, 200, {
          "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
        });
      }

      // ----------------------------------------------------------------
      // GET /tags/:id — タグ詳細
      // ----------------------------------------------------------------
      const tagDetailMatch = path.match(/^\/tags\/([^/]+)$/);
      if (tagDetailMatch && request.method === "GET") {
        const tagId = decodeURIComponent(tagDetailMatch[1]);
        const tag = await env.DB.prepare("SELECT * FROM tags WHERE id = ?").bind(tagId).first();
        if (!tag) return error("Tag not found", 404);

        // タグが付いた全曲を票数降順で返す (旧 LIMIT 50 だと 150 曲付いたタグでも
        // 50 曲しか返らず、絞り込み一覧・曲数バッジが欠落していた)。
        const { results: songs } = await env.DB.prepare(
          `SELECT song_id, vote_count FROM song_tags WHERE tag_id = ? ORDER BY vote_count DESC LIMIT 1000`
        ).bind(tagId).all();

        // タグ詳細はユーザー非依存・変化が緩やか。エッジ (Cloudflare) で全ユーザ共有
        // キャッシュして D1 負荷を削減 (max-age 5分 + SWR 30分。自分のタグ付けは
        // クライアント側キャッシュが即無効化するので、この程度の鮮度で十分)。
        return json({ tag, songs }, 200, {
          "Cache-Control": "public, max-age=300, stale-while-revalidate=1800",
        });
      }

      // ----------------------------------------------------------------
      // PUT /tags/:id — タグ情報更新
      // ----------------------------------------------------------------
      if (tagDetailMatch && request.method === "PUT") {
        const tagId = decodeURIComponent(tagDetailMatch![1]);
        // 認証必須化: X-Device-Id だけでは誰でも他人タグを書換できた
        const authUser = await getAuthUser(request, env);
        if (!authUser) return error("Unauthorized", 401);
        const deviceId = request.headers.get("X-Device-Id") || authUser.uid;

        const tag = await env.DB.prepare("SELECT * FROM tags WHERE id = ?").bind(tagId).first<{
          id: string; description: string | null; status: string;
        }>();
        if (!tag) return error("Tag not found", 404);
        if (tag.status === "removed") return error("Tag has been removed", 403);

        const body = (await request.json()) as any;
        const { description, category, color } = body as {
          description?: string;
          category?: string;
          color?: string;
        };
        const now = Math.floor(Date.now() / 1000);

        // 説明文変更なら履歴保存 (before + after 両方記録)
        if (description !== undefined && description !== tag.description) {
          await env.DB.prepare(
            `INSERT INTO tag_description_history (tag_id, description, description_before, edited_by, edited_at)
             VALUES (?, ?, ?, ?, ?)`
          ).bind(tagId, description ?? null, tag.description ?? null, deviceId, now).run();
        }

        const updates: string[] = ["updated_by = ?", "updated_at = ?"];
        const vals: unknown[] = [deviceId, now];

        if (description !== undefined) { updates.push("description = ?"); vals.push(description); }
        if (category !== undefined) { updates.push("category = ?"); vals.push(category); }
        if (color !== undefined) { updates.push("color = ?"); vals.push(color); }

        vals.push(tagId);
        await env.DB.prepare(`UPDATE tags SET ${updates.join(", ")} WHERE id = ?`).bind(...vals).run();

        const updated = await env.DB.prepare("SELECT * FROM tags WHERE id = ?").bind(tagId).first();
        return json({ tag: updated });
      }

      // ----------------------------------------------------------------
      // GET /tags/:id/history — 編集履歴
      // ----------------------------------------------------------------
      const tagHistoryMatch = path.match(/^\/tags\/([^/]+)\/history$/);
      if (tagHistoryMatch && request.method === "GET") {
        const tagId = decodeURIComponent(tagHistoryMatch[1]);
        const { results } = await env.DB.prepare(
          `SELECT id, tag_id,
                  description AS description_after,
                  description_before,
                  edited_by, edited_at
           FROM tag_description_history
           WHERE tag_id = ? ORDER BY edited_at DESC LIMIT 30`
        ).bind(tagId).all();
        return json(results);
      }

      // ----------------------------------------------------------------
      // POST /tags/:id/report — タグ通報
      // ----------------------------------------------------------------
      const tagReportMatch = path.match(/^\/tags\/([^/]+)\/report$/);
      if (tagReportMatch && request.method === "POST") {
        const tagId = decodeURIComponent(tagReportMatch[1]);
        const deviceId = request.headers.get("X-Device-Id");
        if (!deviceId) return error("X-Device-Id header is required");

        // IP 単位の rate-limit: 複数デバイス回しで 1 タグを連続通報する spam を弾く。
        // device 単位の per-day 制限 (下記 already_reported) は二重防御として残す。
        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const ipDry = await dryCheckIpRateLimit(env.DB, ip);
        if (!ipDry.allowed) {
          return rateLimitSimple();
        }

        const tag = await env.DB.prepare("SELECT id FROM tags WHERE id = ?").bind(tagId).first();
        if (!tag) return error("Tag not found", 404);

        const today = new Date().toISOString().slice(0, 10);
        const alreadyReported = await env.DB.prepare(
          `SELECT 1 FROM tag_reports WHERE tag_id = ? AND reported_by = ? AND DATE(reported_at, 'unixepoch') = ?`
        ).bind(tagId, deviceId, today).first();
        if (alreadyReported) return error("Already reported today", 429);

        const body = (await request.json()) as any;
        const now = Math.floor(Date.now() / 1000);
        await env.DB.prepare(
          `INSERT INTO tag_reports (tag_id, reported_by, reason, reported_at) VALUES (?, ?, ?, ?)`
        ).bind(tagId, deviceId, body.reason ?? null, now).run();

        const reportCount = await env.DB.prepare(
          "SELECT COUNT(*) as cnt FROM tag_reports WHERE tag_id = ?"
        ).bind(tagId).first<{ cnt: number }>();
        const total = reportCount?.cnt ?? 1;

        if (total >= REPORT_THRESHOLD) {
          await env.DB.prepare(
            "UPDATE tags SET status = 'under_review' WHERE id = ? AND status = 'active'"
          ).bind(tagId).run();
        }

        await commitIpRateLimit(env.DB, ip, ipDry.bucket);
        return json({ ok: true, total_reports: total });
      }

      // ----------------------------------------------------------------
      // POST /songs/:song_id/tags — 曲にタグを付ける
      // ----------------------------------------------------------------
      const songTagsPostMatch = path.match(/^\/songs\/([^/]+)\/tags$/);
      if (songTagsPostMatch && request.method === "POST") {
        const songId = decodeURIComponent(songTagsPostMatch[1]);
        const deviceId = request.headers.get("X-Device-Id");
        if (!deviceId) return error("X-Device-Id header is required");

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const ipDry = await dryCheckIpRateLimit(env.DB, ip);
        if (!ipDry.allowed) {
          return rateLimitSimple();
        }

        const body = (await request.json()) as any;
        const tagIds = body.tag_ids as string[];
        if (!Array.isArray(tagIds) || tagIds.length === 0) return error("tag_ids must be a non-empty array");

        const now = Math.floor(Date.now() / 1000);
        const appliedTagIds: string[] = [];

        for (const tagId of tagIds) {
          const tag = await env.DB.prepare("SELECT id FROM tags WHERE id = ? AND status != 'removed'").bind(tagId).first();
          if (!tag) continue;

          // device upsert + vote_count++ を batch で原子化
          const [deviceResult] = await env.DB.batch([
            env.DB.prepare(
              `INSERT OR IGNORE INTO device_song_tag (device_id, song_id, tag_id, created_at) VALUES (?, ?, ?, ?)`
            ).bind(deviceId, songId, tagId, now),
            env.DB.prepare(
              `INSERT INTO song_tags (song_id, tag_id, vote_count) VALUES (?, ?, 1)
               ON CONFLICT(song_id, tag_id) DO UPDATE SET vote_count = vote_count + 1`
            ).bind(songId, tagId),
          ]);

          if (deviceResult.meta.changes > 0) {
            appliedTagIds.push(tagId);
          }
        }

        await commitIpRateLimit(env.DB, ip, ipDry.bucket);
        return json({ song_id: songId, applied_tag_ids: appliedTagIds });
      }

      // ----------------------------------------------------------------
      // DELETE /songs/:song_id/tags/:tag_id — タグを外す
      // ----------------------------------------------------------------
      const songTagDeleteMatch = path.match(/^\/songs\/([^/]+)\/tags\/([^/]+)$/);
      if (songTagDeleteMatch && request.method === "DELETE") {
        const songId = decodeURIComponent(songTagDeleteMatch[1]);
        const tagId = decodeURIComponent(songTagDeleteMatch[2]);
        const deviceId = request.headers.get("X-Device-Id");
        if (!deviceId) return error("X-Device-Id header is required");

        const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const ipDry = await dryCheckIpRateLimit(env.DB, ip);
        if (!ipDry.allowed) {
          return rateLimitSimple();
        }

        // device削除 + vote_count-1 (MAX(0,...)) + 0以下なら song_tags 削除 を batch で原子化
        const [deleted] = await env.DB.batch([
          env.DB.prepare(
            "DELETE FROM device_song_tag WHERE device_id = ? AND song_id = ? AND tag_id = ?"
          ).bind(deviceId, songId, tagId),
          env.DB.prepare(
            `UPDATE song_tags SET vote_count = MAX(0, vote_count - 1) WHERE song_id = ? AND tag_id = ?`
          ).bind(songId, tagId),
          env.DB.prepare(
            `DELETE FROM song_tags WHERE song_id = ? AND tag_id = ? AND vote_count <= 0`
          ).bind(songId, tagId),
        ]);

        await commitIpRateLimit(env.DB, ip, ipDry.bucket);
        return json({ song_id: songId, tag_id: tagId, removed: deleted.meta.changes > 0 });
      }

      // ----------------------------------------------------------------
      // GET /songs/:song_id/tags — 曲のタグ一覧
      // ----------------------------------------------------------------
      const songTagsGetMatch = path.match(/^\/songs\/([^/]+)\/tags$/);
      if (songTagsGetMatch && request.method === "GET") {
        const songId = decodeURIComponent(songTagsGetMatch[1]);
        const deviceId = request.headers.get("X-Device-Id");

        const { results: tags } = await env.DB.prepare(
          `SELECT t.id, t.name, t.color, t.category, st.vote_count
           FROM song_tags st
           JOIN tags t ON t.id = st.tag_id
           WHERE st.song_id = ? AND t.status != 'removed'
           ORDER BY st.vote_count DESC`
        ).bind(songId).all();

        let myTagIds: string[] = [];
        if (deviceId) {
          const { results: myRows } = await env.DB.prepare(
            "SELECT tag_id FROM device_song_tag WHERE device_id = ? AND song_id = ?"
          ).bind(deviceId, songId).all<{ tag_id: string }>();
          myTagIds = myRows.map((r) => r.tag_id);
        }

        return json({ tags, my_tag_ids: myTagIds });
      }

      // ----------------------------------------------------------------
      // GET /songs/:song_id/similar — タグが似ている楽曲 (この曲が好きな人にはこれもおすすめ)
      //   共有タグ数を第一キー、共有タグの票数合計を第二キーで近い順に並べる。
      // ----------------------------------------------------------------
      const songSimilarMatch = path.match(/^\/songs\/([^/]+)\/similar$/);
      if (songSimilarMatch && request.method === "GET") {
        const songId = decodeURIComponent(songSimilarMatch[1]);
        const limitParam = parseInt(url.searchParams.get("limit") ?? "10", 10);
        const limit = Math.min(Math.max(Number.isFinite(limitParam) ? limitParam : 10, 1), 30);

        const { results: songs } = await env.DB.prepare(
          `SELECT st2.song_id AS song_id,
                  COUNT(*) AS shared_tags,
                  SUM(st2.vote_count) AS score
           FROM song_tags st1
           JOIN song_tags st2 ON st2.tag_id = st1.tag_id AND st2.song_id != st1.song_id
           JOIN tags t ON t.id = st1.tag_id AND t.status != 'removed'
           WHERE st1.song_id = ?
           GROUP BY st2.song_id
           ORDER BY shared_tags DESC, score DESC
           LIMIT ?`
        ).bind(songId, limit).all();

        // タグ類似は完全にユーザー非依存 (my_* フラグを一切含まない集計のみ)。
        // タグ付けの分布で決まり変化が非常に緩やかなので、エッジ (Cloudflare) で
        // 全ユーザ共有キャッシュして D1 負荷を削減。曲詳細を開くたびに叩かれるため
        // 効果が大きい。鮮度は粗くてよい (max-age 10分 + SWR 1時間)。
        return json({ song_id: songId, songs }, 200, {
          "Cache-Control": "public, max-age=600, stale-while-revalidate=3600",
        });
      }

      // ----------------------------------------------------------------
      // POST /edits — マスタ create/update/delete (オープン編集, 1 リクエスト = 1 edit_batch)
      // ----------------------------------------------------------------
      if (path === "/edits" && request.method === "POST") {
        return handlePostEdits(request, env, {
          getAuthUser,
          upsertUser,
          checkIsAdmin,
          checkRateLimit,
          json,
          error,
          rateLimitResponse,
        });
      }

      // ----------------------------------------------------------------
      // POST /edit-requests — マスタ修正リクエスト (GitHub issue 化, CloudKit に書かない)
      // ----------------------------------------------------------------
      if (path === "/edit-requests" && request.method === "POST") {
        return handlePostEditRequests(request, env, {
          getAuthUser,
          checkRateLimit,
          json,
          error,
          rateLimitResponse,
        });
      }

      // ----------------------------------------------------------------
      // GET /master/:recordType/:recordName/history — レコードの編集履歴
      // ----------------------------------------------------------------
      const masterHistoryMatch = path.match(/^\/master\/([^/]+)\/([^/]+)\/history$/);
      if (masterHistoryMatch && request.method === "GET") {
        const recordType = decodeURIComponent(masterHistoryMatch[1]);
        const recordName = decodeURIComponent(masterHistoryMatch[2]);
        return handleGetRecordHistory(recordType, recordName, url, env, { json, error });
      }

      return addRequestId(error("Not found", 404), requestId);
    } catch (e: unknown) {
      console.error("route_failed", {
        requestId,
        path: url.pathname,
        method: request.method,
        origin: request.headers.get("Origin"),
        ip: request.headers.get("CF-Connecting-IP"),
        error: e instanceof Error ? { message: e.message, stack: e.stack } : String(e),
      });
      // クライアントに D1 / Workers runtime のエラーメッセージ (schema 情報含む) を
      // 露出させない。 詳細は console.error 経由で運営側のみ確認できる。
      return addRequestId(
        error(`Internal error (request id: ${requestId})`, 500),
        requestId
      );
    }
    };

    const response = await handle();
    // 公開 (Cache-Control: public) かつ成功GETのみエッジへ保存。TTL はレスポンスの max-age に従う。
    if (edgeCacheEligible && response.ok) {
      const cc = response.headers.get("Cache-Control");
      if (cc && cc.includes("public") && cc.includes("max-age")) {
        ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
      }
    }
    return response;
  },

  // ----------------------------------------------------------------
  // Scheduled handler: approved → applied (via CloudKit) + rate limit cleanup
  // ----------------------------------------------------------------
  async scheduled(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    await Promise.all([handleScheduled(env), cleanOldRateLimitBuckets(env.DB)]);
  },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function slugify(input: string): string {
  const ascii = input
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .replace(/\s+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
  // ASCII 化が短すぎる、または "tag_" 単体になる場合はハッシュベースIDを使う
  if (ascii.length < 2 || ascii === "tag_") {
    // Web Crypto は sync で使えないので btoa ベースの fallback
    const encoded = btoa(unescape(encodeURIComponent(input)))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=/g, "");
    return "tag_" + encoded.slice(0, 16);
  }
  return ascii;
}

async function resolveSlug(db: D1Database, name: string): Promise<string> {
  const base = slugify(name);
  // 衝突時は -2, -3, ... を最大10回試みる (name の UNIQUE 制約で同名は弾けるが PK 衝突を防ぐ)
  for (let i = 0; i <= 10; i++) {
    const candidate = i === 0 ? base : `${base}-${i + 1}`;
    const existing = await db
      .prepare("SELECT id FROM tags WHERE id = ?")
      .bind(candidate)
      .first();
    if (!existing) return candidate;
  }
  // 万が一全て衝突した場合はタイムスタンプサフィックス
  return `${base}-${Date.now()}`;
}

async function checkIsAdmin(env: Env, uid: string): Promise<boolean> {
  // allowlist check via env var
  if (env.ADMIN_USER_IDS) {
    const allowed = env.ADMIN_USER_IDS.split(",").map((s) => s.trim()).filter(Boolean);
    if (allowed.includes(uid)) return true;
  }
  // DB check
  const row = await env.DB.prepare("SELECT is_admin FROM users WHERE id = ?")
    .bind(uid)
    .first<{ is_admin: number }>();
  return !!row?.is_admin;
}
