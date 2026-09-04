import type { Env } from "./env";
import {
  verifyAppleToken, verifyGoogleToken, signSessionToken,
  verifySessionTokenForRefresh, getAuthUser, peekJwtIssuer,
  SESSION_JWT_ISSUER, SESSION_JWT_TTL_SECONDS,
} from "./auth";
import { checkRateLimit, dryCheckIpRateLimit, commitIpRateLimit } from "./rate_limit";
import { upsertUser, checkIsAdmin } from "./users";
import { handleDeviceAggregates } from "./routes/device_aggregates";
import { handlePolls } from "./routes/polls";
import { handleTags } from "./routes/tags";
import { handleLyrics } from "./routes/lyrics";
import { handleLyricsCalls, handleCallsDashboard } from "./routes/calls";
import { handleSongDetail } from "./routes/song_detail";
import { handleSetlistPredictions } from "./routes/setlist_predictions";
import { fetchBadges, calcTier } from "./badges";
import { handleScheduled } from "./apply";
import { cloudKitModify, cloudKitLookup, buildForceUpdate, buildSoftDelete, CloudKitOperation } from "./cloudkit";
import { handlePostEdits, handleGetRecordHistory } from "./edits";
import { handleCreateTransfer, handleFetchTransfer } from "./transfer";
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

// ---------------------------------------------------------------------------
// Input helpers
// ---------------------------------------------------------------------------

/**
 * Parse a query-string integer safely.
 * Returns defaultValue when the input is missing, empty, NaN or ≤ 0.
 * Caps the result at max.
 */

/** Escape LIKE wildcards so user input is treated literally. */

/** polls.scope_brand_ids / scope_entity_ids の JSON 配列文字列を string[] にパース。NULL や不正値は null を返す。 */

/**
 * 投票候補スコープの ID 配列を検証 + DB 実在チェック。
 * - 配列型/文字列型/長さ範囲/エントリ長/重複の有無を順に検査
 * - allowDuplicates=false なら重複を 400 で弾く、true なら dedup して通す
 * - 通れば dedup 済み配列を JSON 文字列で返す。失敗時は error メッセージ文字列を返す。
 *
 * brand スコープ ({minLen:1, maxLen:16, maxEntryLen:32, allowDuplicates:true})、
 * manual スコープ ({minLen:2, maxLen:500, maxEntryLen:64, allowDuplicates:false}) で共用。
 */

async function cleanOldRateLimitBuckets(db: D1Database): Promise<void> {
  const oneDayAgo = Math.floor(Date.now() / 1000 / 60) - 1440;
  await db
    .prepare("DELETE FROM api_rate_limits WHERE minute_bucket < ?")
    .bind(oneDayAgo)
    .run();
}

async function cleanExpiredTransferCodes(db: D1Database): Promise<void> {
  await db
    .prepare("DELETE FROM transfer_codes WHERE expires_at < ?")
    .bind(new Date().toISOString())
    .run();
}



// ---------------------------------------------------------------------------
// 不透明キー (song_id / idol_id / entity_id) 検証
// ---------------------------------------------------------------------------


function isCommunityRead(path: string, method: string): boolean {
  if (method !== "GET") return false;
  // D1 固定無料枠に乗る集計 read を網羅する (CLAUDE.md 名指しの予想/いいね/ランキング含む)
  if (/^\/(polls|favorites|penlight|tags|master|leaderboard)(\/|$)/.test(path)) return true;
  if (/^\/songs\/[^/]+\/(tags|similar|detail)$/.test(path)) return true;
  if (/^\/idols\/[^/]+\/similar$/.test(path)) return true;
  if (/^\/units\/[^/]+\/similar$/.test(path)) return true;
  if (/^\/shows\/[^/]+\/(predictions|likes)$/.test(path)) return true;
  // コールガイドの整備状況。歌詞本文もコール本文も含まない件数・日時・表示名だけの
  // 集計なので、歌詞の枠 (認証必須・no-store) ではなくこちら側に置く。
  if (path === "/calls/dashboard") return true;
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

/**
 * JSON 応答共通の X-Content-Type-Options: nosniff と、Universal Links フォールバック
 * HTML (renderAppFallbackPage) 共通の CSP を、応答経路の合流点で一括付与する。
 * 個々の handler 内の大量の return json(...) 呼び出し側は一切変更しない。
 * HTML はインライン <style> のみで外部リソース・script を持たないため、
 * default-src 'none' + style-src 'unsafe-inline' で十分 (<a href> のトップレベル遷移は
 * default-src の対象外)。
 */
function applySecurityHeaders(response: Response): Response {
  const contentType = response.headers.get("Content-Type") || "";
  if (contentType.includes("application/json")) {
    const headers = new Headers(response.headers);
    headers.set("X-Content-Type-Options", "nosniff");
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  }
  if (contentType.includes("text/html")) {
    const headers = new Headers(response.headers);
    headers.set("X-Content-Type-Options", "nosniff");
    headers.set(
      "Content-Security-Policy",
      "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    );
    return new Response(response.body, { status: response.status, statusText: response.statusText, headers });
  }
  return response;
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
  kind: "events" | "shows" | "polls";
  id: string;
  title: string | null;
  subtitle: string | null;
}): string {
  const { title } = opts;
  let heading: string;
  let description: string;
  if (title !== null) {
    heading = escapeHtml(title);
    description = opts.kind === "polls"
      ? `「${heading}」の投票にアプリから参加しよう`
      : `「${heading}」のセットリスト・出演情報をアプリでチェック`;
  } else {
    heading = {
      events: "イベントが見つかりません",
      shows: "公演が見つかりません",
      polls: "お題が見つかりません",
    }[opts.kind];
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
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Vary": "Origin",
          "X-Content-Type-Options": "nosniff",
          "X-Request-Id": requestId,
        },
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
    // - 応答が X-Device-Id で変わるエンドポイント (GET /songs/:id/detail の
    //   my_tag_ids / my_vote) は、端末ヘッダ付きリクエストを共有キャッシュから
    //   完全に外す (読みも書きもしない)。キャッシュキーが URL のみなので、外さないと
    //   他人の my_* が配られる / 自分の my_* が消えた応答を掴む。
    //   ※ 他の公開 GET (favorites/ranking, songs/:id/similar 等) は端末非依存なので
    //     従来どおり X-Device-Id 付きでもエッジで賄う。
    const varyByDeviceId = /^\/songs\/[^/]+\/detail$/.test(path);
    const edgeCacheEligible =
      request.method === "GET" &&
      !request.headers.get("Authorization") &&
      !(varyByDeviceId && request.headers.get("X-Device-Id"));
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
            // 曲詳細の集計束ね (tags + similar + penlight、認証時のみ lyrics も同梱)。
            "GET /songs/:song_id/detail",
            // 歌詞は 1 リクエスト 1 曲・認証必須 (JASRAC 許諾の「一括ダウンロード不可」)。
            "GET /songs/:song_id/lyrics",
            // 歌詞検索。返すのは song_id と一致箇所まわりのスニペットだけ。
            "GET /lyrics/search",
            "PUT /admin/lyrics/:song_id",
            "PUT /songs/:song_id/calls",
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
                  components: [
                    { "/": "/app/events/*" },
                    { "/": "/app/shows/*" },
                    { "/": "/app/polls/*" },
                  ],
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
      // GET /app/events/:id, /app/shows/:id, /app/polls/:id — Universal Links フォールバック
      //   アプリ未インストールのブラウザアクセスに App Store 誘導 HTML を返す。
      //   (インストール済み端末では iOS がアプリを直接開くため通常表示されない)
      // ----------------------------------------------------------------
      const appLinkMatch = path.match(/^\/app\/(events|shows|polls)\/([^/]+)$/);
      if (appLinkMatch && request.method === "GET") {
        const kind = appLinkMatch[1] as "events" | "shows" | "polls";
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
          if (kind === "polls") {
            // お題は CloudKit ではなく D1 (polls テーブル) が正。
            const poll = await env.DB.prepare(
              "SELECT title, description, ends_at FROM polls WHERE id = ? AND status = 'active'"
            )
              .bind(id)
              .first<{ title: string; description: string | null; ends_at: string }>();
            if (poll) {
              title = poll.title;
              subtitle = poll.description || null;
            }
          } else if (kind === "events") {
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
      // POST /auth/login — Apple identityToken または Google idToken (Android) → 1年有効 sessionToken
      // ----------------------------------------------------------------
      if (path === "/auth/login" && request.method === "POST") {
        if (!env.SESSION_JWT_SECRET) return error("SESSION_JWT_SECRET not configured", 500);

        // IP 単位のレート制限 (未認証エンドポイントなので device/user 単位の制限は使えない)。
        // Apple/Google トークン検証の外部コスト枯渇を防ぐ一次防御。
        const authLoginIp = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const authLoginRl = await checkRateLimit(env.DB, "ip:" + authLoginIp, "auth_login");
        if (!authLoginRl.allowed) {
          return rateLimitResponse(authLoginRl.used, authLoginRl.limit, authLoginRl.reset_at);
        }

        // iOS の APIClient は JSONEncoder.keyEncodingStrategy = .convertToSnakeCase で
        // 全リクエストボディを snake_case 化して送る (identityToken → identity_token,
        // displayName → display_name)。この endpoint だけ camelCase を読んでいたため
        // iOS のログインは常に 400 となり、session token が一度も発行されず、Apple
        // identityToken を直接 Bearer (10分有効) に流用するフォールバックで誤魔化されていた。
        // snake_case を正として読む (旧 camelCase クライアントも後方互換で許容)。
        // Android は Google の ID トークンを google_id_token として送る (identity_token とは別枠)。
        const body = (await request.json().catch(() => null)) as
          | {
              identity_token?: string; identityToken?: string;
              google_id_token?: string; googleIdToken?: string;
              display_name?: string; displayName?: string;
            }
          | null;
        const identityToken = body?.identity_token ?? body?.identityToken;
        const googleIdToken = body?.google_id_token ?? body?.googleIdToken;
        const displayName = body?.display_name ?? body?.displayName;

        let verified: { uid: string; email?: string; picture?: string; name?: string } | null = null;
        if (googleIdToken) {
          if (!env.GOOGLE_WEB_CLIENT_ID) return error("GOOGLE_WEB_CLIENT_ID not configured", 500);
          verified = await verifyGoogleToken(googleIdToken, env.GOOGLE_WEB_CLIENT_ID);
          if (!verified) return error("invalid googleIdToken", 401);
        } else if (identityToken) {
          verified = await verifyAppleToken(identityToken, env.APPLE_BUNDLE_ID);
          if (!verified) return error("invalid identityToken", 401);
        } else {
          return error("identityToken or googleIdToken required");
        }

        // Google は検証済みトークンの name クレームを信頼できる表示名として使う
        // (Apple はクライアント供給の displayName に頼る既存挙動を維持)。
        await upsertUser(env, verified.uid, verified.name ?? displayName, verified.picture);
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

        // IP 単位のレート制限 (auth/login と同じ理由。refresh は外部コストは無いが下限の防御)。
        const authRefreshIp = request.headers.get("CF-Connecting-IP") ?? "unknown";
        const authRefreshRl = await checkRateLimit(env.DB, "ip:" + authRefreshIp, "auth_refresh");
        if (!authRefreshRl.allowed) {
          return rateLimitResponse(authRefreshRl.used, authRefreshRl.limit, authRefreshRl.reset_at);
        }

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
        // 検証より前に走らせると空文字・型不正など 400 になるリクエストでも 1日3枠を
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
      // DELETE /users/me — 本人によるアカウント削除 (App Store 5.1.1(v) 対応)
      //   退会を妨げないため BAN 中でも許可する。リクエストボディは無い。
      //   ログインで初めて作られるアカウント紐付けデータ (投票・like・編集履歴・Good) は
      //   すべて物理削除する。Good 数や like 数は保存値ではなく都度 COUNT(*) なので、
      //   本人の行を消せば表示カウントも自然に減る。予想/投票の集計テーブル (vote_count 等) は
      //   端末・匿名の共有データなので触らない。
      //   foreign_keys が ON でも通るよう、子テーブルの参照を先に外してから親 → users の順に消す。
      //   一連の操作は env.DB.batch() で原子的に実行し、途中失敗で中途半端な状態を残さない。
      // ----------------------------------------------------------------
      if (path === "/users/me" && request.method === "DELETE") {
        const user = await getAuthUser(request, env);
        if (!user) return error("Unauthorized", 401);
        const uid = user.uid;

        await env.DB.batch([
          // 本人だけに紐づく個人データ。FK は無いのでそのまま削除する。
          env.DB.prepare("DELETE FROM rate_limits WHERE user_id = ?").bind(uid),
          env.DB.prepare("DELETE FROM setlist_prediction_votes WHERE user_id = ?").bind(uid),
          env.DB
            .prepare("DELETE FROM setlist_performer_prediction_votes WHERE user_id = ?")
            .bind(uid),
          env.DB.prepare("DELETE FROM poll_votes WHERE user_id = ?").bind(uid),
          env.DB.prepare("DELETE FROM setlist_song_likes WHERE user_id = ?").bind(uid),

          // Good は本人が付けた分と、本人の編集が受け取った分の双方を削除する。
          // edit_batch を消す前に、それを参照する edit_good を先に消す (FK)。
          env.DB.prepare("DELETE FROM edit_good WHERE user_id = ?").bind(uid),
          env.DB
            .prepare(
              "DELETE FROM edit_good WHERE batch_id IN (SELECT id FROM edit_batch WHERE editor_id = ?)"
            )
            .bind(uid),

          // edit_history も edit_batch を参照するので先に消す (FK)。
          env.DB
            .prepare(
              "DELETE FROM edit_history WHERE batch_id IN (SELECT id FROM edit_batch WHERE editor_id = ?)"
            )
            .bind(uid),

          // 他者の batch に残る本人の batch / 本人への参照を外す (FK)。
          //   reverts_batch_id: 本人の編集を revert した他者 batch から、消える batch への参照を外す
          //   reverted_by:      本人が他者の編集を revert した記録の実行者参照を外す
          env.DB
            .prepare(
              "UPDATE edit_batch SET reverts_batch_id = NULL WHERE reverts_batch_id IN (SELECT id FROM edit_batch WHERE editor_id = ?)"
            )
            .bind(uid),
          env.DB.prepare("UPDATE edit_batch SET reverted_by = NULL WHERE reverted_by = ?").bind(uid),

          // 本人のコール編集履歴を消す。コールそのもの (lines_json) は消さない —
          // タグ・投票集計と同じ「みんなの共有データ」であって個人データではないため。
          env.DB.prepare("DELETE FROM call_edit_history WHERE user_id = ?").bind(uid),
          // 「最後にコールを書いた人」の参照だけ外す (表示は「匿名」に落ちる)。
          env.DB
            .prepare("UPDATE song_call_stats SET updated_by_uid = NULL WHERE updated_by_uid = ?")
            .bind(uid),

          // 参照を外したので本人の編集 batch を削除し、最後に users 行を削除する。
          env.DB.prepare("DELETE FROM edit_batch WHERE editor_id = ?").bind(uid),
          env.DB.prepare("DELETE FROM users WHERE id = ?").bind(uid),
        ]);

        return json({ deleted: true });
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

        const body = (await request.json().catch(() => null)) as any;
        if (body === null) return error("invalid JSON body");
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

      // ----------------------------------------------------------------
      // 予想セトリ / 出演者予想 / セトリいいね は
      // routes/setlist_predictions.ts へ切り出し済み。
      // 一致しなければ null が返り、以降の if チェーンが続く。
      // ----------------------------------------------------------------
      const setlistPredictionResponse = await handleSetlistPredictions({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
      });
      if (setlistPredictionResponse) return setlistPredictionResponse;

      // ================================================================
      // みんなの投票 (Community Theme Polls) API
      // ================================================================

      // ----------------------------------------------------------------
      // みんなの投票 API は routes/polls.ts へ切り出し済み。
      // 一致しなければ null が返り、以降の if チェーンが続く。
      // ----------------------------------------------------------------
      const pollsResponse = await handlePolls({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
      });
      if (pollsResponse) return pollsResponse;

      // ================================================================
      // コミュニティ集計 API
      // ================================================================

      // ----------------------------------------------------------------
      // device 集計 API (お気に入り / ペンライト色) は routes/ へ切り出し済み。
      // 一致しなければ null が返り、以降の if チェーンが続く。
      // ----------------------------------------------------------------
      const deviceAggregateResponse = await handleDeviceAggregates({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
      });
      if (deviceAggregateResponse) return deviceAggregateResponse;

      // ----------------------------------------------------------------
      // ユーザータグ API (song / idol / unit の 3 プール + 類似) は
      // routes/tags.ts へ切り出し済み。一致しなければ null が返る。
      // ----------------------------------------------------------------
      const tagsResponse = await handleTags({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
      });
      if (tagsResponse) return tagsResponse;

      // ----------------------------------------------------------------
      // 歌詞 API (GET /songs/:id/lyrics, PUT /admin/lyrics/:id) は
      // routes/lyrics.ts へ切り出し済み。一致しなければ null が返る。
      //
      // ⚠️ isCommunityRead には足さないこと。GET が Authorization を必須にしている
      //    ことで上の edgeCacheEligible が false になり、歌詞がエッジキャッシュに
      //    載らない。歌詞は JASRAC 許諾の条件上「一括ダウンロードできない形式」で
      //    配信する必要があり、共有キャッシュに置くのはその条件に反する。
      // ----------------------------------------------------------------
      const lyricsResponse = await handleLyrics({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
      });
      if (lyricsResponse) return lyricsResponse;

      // ----------------------------------------------------------------
      // コールガイド保存 (PUT /songs/:id/calls) は routes/calls.ts へ。
      // コール**本文**の読み出しは専用エンドポイントを作らず、歌詞応答 (上の GET と
      // /detail) に clap / calls が含まれる形にしてある。
      // waitUntil は保存後に /calls/dashboard のエッジキャッシュを捨てるのに使う。
      // ----------------------------------------------------------------
      const callsResponse = await handleLyricsCalls({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
        waitUntil: ctx.waitUntil.bind(ctx),
      });
      if (callsResponse) return callsResponse;

      // ----------------------------------------------------------------
      // GET /calls/dashboard — コールガイドの整備状況 (件数・日時・表示名のみ)。
      //
      // ⚠️ 歌詞本文もコール本文もアンカー文字列も含まない。含めた瞬間に、認証不要 =
      //    edgeCacheEligible の公開キャッシュに歌詞の断片が載る (routes/calls.ts 冒頭)。
      // ----------------------------------------------------------------
      const callsDashboardResponse = await handleCallsDashboard({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
        waitUntil: ctx.waitUntil.bind(ctx),
      });
      if (callsDashboardResponse) return callsDashboardResponse;

      // ----------------------------------------------------------------
      // GET /songs/:song_id/detail — 曲詳細の集計を 1 リクエストに束ねる
      //   (penlight votes + tags + similar、認証時は歌詞も同梱)。
      //   既存 3 エンドポイントは残してあるので段階移行できる。
      //
      // ⚠️ 認証ありの応答は歌詞を含む。上の edgeCacheEligible が Authorization の
      //    有無で false になることに依存して、歌詞がエッジキャッシュに載らないことを
      //    構造的に担保している (routes/song_detail.ts 冒頭のコメント参照)。
      // ----------------------------------------------------------------
      const songDetailResponse = await handleSongDetail({
        request, env, url, path, json, error, rateLimitResponse, rateLimitSimple,
        waitUntil: ctx.waitUntil.bind(ctx),
      });
      if (songDetailResponse) return songDetailResponse;

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

      // ----------------------------------------------------------------
      // POST /transfer — 引き継ぎコード発行 (auth必須・rate limit "transfer_create")
      // GET  /transfer/:code — 引き継ぎコードでペイロード取得 (取得と同時に消費)
      // ----------------------------------------------------------------
      if (path === "/transfer" && request.method === "POST") {
        return handleCreateTransfer(request, env, {
          getAuthUser,
          checkRateLimit,
          json,
          error,
          rateLimitResponse,
        });
      }
      const transferFetchMatch = path.match(/^\/transfer\/([^/]+)$/);
      if (transferFetchMatch && request.method === "GET") {
        const code = decodeURIComponent(transferFetchMatch[1]);
        return handleFetchTransfer(request, env, code, {
          getAuthUser,
          checkRateLimit,
          json,
          error,
          rateLimitResponse,
        });
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

    const response = applySecurityHeaders(await handle());
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
    await Promise.all([
      handleScheduled(env),
      cleanOldRateLimitBuckets(env.DB),
      cleanExpiredTransferCodes(env.DB),
    ]);
  },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------


