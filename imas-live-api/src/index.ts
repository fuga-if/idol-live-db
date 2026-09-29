import type { Env } from "./env";
import { runScheduledTasks } from "./scheduled";
import type { RouteContext } from "./routes/context";
import { gateCommunityRead, handleAppAttest } from "./routes/app_attest";
import { handleAppLinks } from "./routes/app_links";
import { handleAuth } from "./routes/auth";
import { handleUsers } from "./routes/users";
import { handleEdits } from "./routes/edits";
import { handleAdmin } from "./routes/admin";
import { handleSetlistPredictions } from "./routes/setlist_predictions";
import { handlePolls } from "./routes/polls";
import { handleDeviceAggregates } from "./routes/device_aggregates";
import { handleTags } from "./routes/tags";
import { handleLyrics } from "./routes/lyrics";
import { handleLyricsCalls, handleCallsDashboard } from "./routes/calls";
import { handleSongDetail } from "./routes/song_detail";
import { handleTransfer } from "./routes/transfer";
import { handleDiscord } from "./routes/discord";

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
// Response helpers
// ---------------------------------------------------------------------------

// json / error / rateLimit* はリクエストごとの CORS ヘッダを閉じ込めたクロージャ
// (makeResponders)。ルートには RouteContext に入れて渡す。

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
// ルート
// ---------------------------------------------------------------------------

/** GET / — 名前と主なエンドポイントの一覧 (ヘルスチェック)。 */
async function handleRoot(ctx: RouteContext): Promise<Response | null> {
  if (ctx.path !== "/" && ctx.path !== "") return null;
  return ctx.json({
    name: "imas-live-api",
    description: "THE IDOLM@STER Live Database API",
    endpoints: [
      "POST /auth/login",
      "GET /auth/me",
      "POST /edits",
      "GET /edits?brand_id=&record_type=&editor_id=&page=1&limit=20",
      "GET /me/edits?page=1&limit=20",
      "POST /edits/:batchId/good",
      "DELETE /edits/:batchId/good",
      "POST /edits/:batchId/revert",
      "GET /master/:recordType/:recordName/history",
      "GET /users/:user_id/badges",
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
      // 歌詞クイズの出題母集団。公開中の曲 id だけ (本文は含まない)。
      "GET /lyrics/published",
      "PUT /admin/lyrics/:song_id",
      "PUT /songs/:song_id/calls",
      "POST /discord/link",
      "POST /discord/interactions",
    ],
  });
}

/**
 * ルートを上から順に試す。最初に応答を返したものがそのまま応答になり、全部 null なら 404。
 * どのルートも RouteContext を 1 つ受け取り、ここで await される (失敗は下の catch で
 * request id 付きの 500 になる)。
 *
 * マスタの読み取り API (旧 Web アプリ用の /brands /idols /songs /events /shows /units /search 等)
 * は持たない。アプリはマスタを CloudKit から直接同期し、D1 のマスタのミラーは撤去済み。
 */
const ROUTES: ReadonlyArray<(ctx: RouteContext) => Promise<Response | null>> = [
  // アプリ証明の口 (IP の日次上限つき) と、集計の読み取りのゲート。ゲートはルートではなく
  // 関所 (通すなら null) なので、集計の読み取りより前のここに置く。
  handleAppAttest,
  gateCommunityRead,
  handleRoot,
  handleAppLinks,
  handleAuth,
  handleUsers,
  handleEdits,
  handleAdmin,
  handleSetlistPredictions,
  handlePolls,
  handleDeviceAggregates,
  handleTags,
  // 歌詞 (GET /songs/:id/lyrics・/lyrics/search・/admin/lyrics/*)。
  // ⚠️ ゲートの対象 (isCommunityRead) には足さないこと。歌詞は下の isLyricsRead で
  //    edgeCacheEligible から明示的に外してあり、共有キャッシュに載らない。
  //    エッジで返すと Worker に届かず、リクエスト回数が数えられなくなる。
  handleLyrics,
  // コールガイドの保存 (PUT /songs/:id/calls)。コール本文の読み出しは専用の口を作らず、
  // 歌詞の応答 (GET と /detail) に clap / calls を含める。waitUntil は保存後に
  // /calls/dashboard のエッジキャッシュを捨てるのに使う。
  handleLyricsCalls,
  // GET /calls/dashboard — 整備状況 (件数・日時・表示名だけ)。
  // ⚠️ 歌詞本文もコール本文もアンカー文字列も含めない。含めた瞬間に、認証不要 =
  //    edgeCacheEligible の公開キャッシュに歌詞の断片が載る (routes/calls.ts 冒頭)。
  handleCallsDashboard,
  // GET /songs/:song_id/detail — 曲詳細の集計の束ね (認証時は歌詞も同梱)。
  // ⚠️ 認証ありの応答は歌詞を含む。edgeCacheEligible が Authorization の有無で false に
  //    なることに依存して、歌詞がエッジキャッシュに載らないことを構造的に担保している
  //    (routes/song_detail.ts 冒頭のコメント参照)。
  handleSongDetail,
  handleTransfer,
  // Discord のロール受け取り (/discord/link・/discord/callback・/discord/interactions・/github/callback)。
  handleDiscord,
];

/** ROUTES を順に試す。無ければ 404、失敗は request id 付きの 500 (エラー文は応答に出さない)。 */
async function dispatch(ctx: RouteContext): Promise<Response> {
  const { request, requestId, error } = ctx;
  try {
    for (const route of ROUTES) {
      const res = await route(ctx);
      if (res) return res;
    }
    return addRequestId(error("Not found", 404), requestId);
  } catch (e: unknown) {
    console.error("route_failed", {
      requestId,
      path: ctx.path,
      method: request.method,
      origin: request.headers.get("Origin"),
      ip: request.headers.get("CF-Connecting-IP"),
      error: e instanceof Error ? { message: e.message, stack: e.stack } : String(e),
    });
    // クライアントに D1 / Workers runtime のエラーメッセージ (schema 情報含む) を
    // 露出させない。 詳細は console.error 経由で運営側のみ確認できる。
    return addRequestId(error(`Internal error (request id: ${requestId})`, 500), requestId);
  }
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
    // 歌詞は共有キャッシュに載せない。**要件は「まとめ取りできないこと」と
    // 「リクエスト回数が数えられること」**の 2 つで、エッジで返してしまうと後者が
    // 崩れる (Worker に届かず logLyricsRead が走らない = JASRAC 年次報告の
    // 19 項目目が数えられない)。
    //
    // 以前はここを Authorization の有無で間接的に外していたが、それだと
    // 「未認証は配れない」という要件でない制約が付いてくる。除外はパスで明示する。
    const isLyricsRead =
      /^\/songs\/[^/]+\/lyrics$/.test(path) || path === "/lyrics/search";
    const edgeCacheEligible =
      request.method === "GET" &&
      !isLyricsRead &&
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

    const routeCtx: RouteContext = {
      request, env, url, path, requestId,
      json, error, rateLimitResponse, rateLimitSimple,
      waitUntil: ctx.waitUntil.bind(ctx),
    };
    const response = applySecurityHeaders(await dispatch(routeCtx));
    // 公開 (Cache-Control: public) かつ成功GETのみエッジへ保存。TTL はレスポンスの max-age に従う。
    if (edgeCacheEligible && response.ok) {
      const cc = response.headers.get("Cache-Control");
      if (cc && cc.includes("public") && cc.includes("max-age")) {
        ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
      }
    }
    return response;
  },

  // cron: 掃除と日次の集計 (scheduled.ts)。wrangler.jsonc の crons と対。
  async scheduled(event: ScheduledEvent, env: Env, _ctx: ExecutionContext): Promise<void> {
    await runScheduledTasks(event.cron, env);
  },
};
