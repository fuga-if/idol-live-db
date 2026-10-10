// 公開データ API のルーティングと応答。判断 (何を返すか) は持たない:
// 詳細は imas-core が組んだ文書 (D1 の docs.body) をそのまま返し、
// 一覧は索引行を名前と鍵だけの形にして返す。
import {
  DEFAULT_LIMIT,
  MAX_LIMIT,
  SQL_DOC,
  SQL_META,
  SQL_VERSION,
  buildList,
  type ListKind,
} from "./queries";

export interface Env {
  DB: D1Database;
  RATE_LIMITER: { limit(options: { key: string }): Promise<{ success: boolean }> };
}

export interface Deps {
  /** 検索語の畳み込み (本番は imas-fold-wasm) */
  fold: (text: string) => string;
  /** エッジのキャッシュ (本番は caches.default) */
  cache: Cache;
  now?: () => number;
}

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, HEAD, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
  "X-Content-Type-Options": "nosniff",
};
const OK_CACHE = "public, max-age=3600";
const MISS_CACHE = "public, max-age=60";
const VERSION_TTL_MS = 60_000;

const KINDS: Record<string, ListKind> = { idols: "idol", songs: "song", units: "unit" };

let versionMemo: { value: string; at: number } | undefined;
/** テストが isolate をまたいだ状態を捨てるため */
export function resetMemo(): void {
  versionMemo = undefined;
}

function json(status: number, body: unknown, cacheControl?: string): Response {
  const headers: Record<string, string> = {
    ...CORS,
    "Content-Type": "application/json; charset=utf-8",
  };
  if (cacheControl) headers["Cache-Control"] = cacheControl;
  return new Response(typeof body === "string" ? body : JSON.stringify(body), { status, headers });
}

function fail(status: number, code: string, message: string, cacheControl?: string): Response {
  return json(status, { error: { code, message } }, cacheControl ?? "no-store");
}

export async function handle(request: Request, env: Env, ctx: ExecutionContext, deps: Deps): Promise<Response> {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (request.method !== "GET" && request.method !== "HEAD") {
    return fail(405, "method_not_allowed", "GET のみ受け付けます");
  }
  const url = new URL(request.url);
  const route = parseRoute(url);
  if (route.type === "none") {
    return fail(404, "not_found", "知らないパスです。/v1/meta から辿れます", MISS_CACHE);
  }
  if (route.type === "bad") return fail(400, "bad_request", route.message);

  // 同期の版はエッジのキャッシュ鍵に入れる。isolate に 1 分覚えさせて D1 を毎回読まない。
  const now = (deps.now ?? Date.now)();
  let version: string;
  try {
    version = await currentVersion(env, now);
  } catch {
    return fail(503, "unavailable", "データベースを読めません");
  }
  const cacheKey = new Request(`https://cache.imas-data-api.invalid/${encodeURIComponent(version)}${route.key}`);
  const hit = await deps.cache.match(cacheKey);
  if (hit) return withMethod(hit, request.method);

  // ここから先は D1 を読む。キャッシュに当たらないリクエストだけを数える。
  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const verdict = await env.RATE_LIMITER.limit({ key: ip });
  if (!verdict.success) {
    const r = fail(429, "rate_limited", "リクエストが多すぎます。しばらくしてから再試行してください");
    r.headers.set("Retry-After", "60");
    return r;
  }

  let response: Response;
  try {
    response = await run(route, env, deps);
  } catch {
    return fail(503, "unavailable", "データベースを読めません");
  }
  if (response.headers.get("Cache-Control")?.startsWith("public")) {
    ctx.waitUntil(deps.cache.put(cacheKey, response.clone()));
  }
  return withMethod(response, request.method);
}

function withMethod(r: Response, method: string): Response {
  return method === "HEAD" ? new Response(null, { status: r.status, headers: r.headers }) : r;
}

async function currentVersion(env: Env, now: number): Promise<string> {
  if (versionMemo && now - versionMemo.at < VERSION_TTL_MS) return versionMemo.value;
  const row = await env.DB.prepare(SQL_VERSION).first<{ value: string }>();
  if (!row) throw new Error("meta.version が無い (まだ同期されていない)");
  versionMemo = { value: row.value, at: now };
  return row.value;
}

type Route =
  | { type: "none" }
  | { type: "bad"; message: string }
  | { type: "meta"; key: string }
  | { type: "brands"; key: string }
  | { type: "doc"; kind: ListKind; id: string; key: string }
  | { type: "facts"; id: string; key: string }
  | { type: "list"; kind: ListKind; q?: string; brand?: string; idol?: string; limit: number; cursor: number; key: string };

const ID_MAX = 200;
const BRAND_RE = /^[a-z0-9_]{1,32}$/;

function parseRoute(url: URL): Route {
  const parts = url.pathname.split("/").filter((p) => p !== "");
  if (parts[0] !== "v1") return { type: "none" };
  if (parts.length === 2 && parts[1] === "meta") return { type: "meta", key: "/v1/meta" };
  if (parts.length === 2 && parts[1] === "brands") return { type: "brands", key: "/v1/brands" };
  const kind = KINDS[parts[1] ?? ""];
  if (!kind) return { type: "none" };
  if (parts.length === 3) {
    let id: string;
    try {
      id = decodeURIComponent(parts[2]);
    } catch {
      return { type: "bad", message: "id の percent-encoding が壊れています" };
    }
    if (id.length === 0 || id.length > ID_MAX) return { type: "bad", message: "id が不正です" };
    return { type: "doc", kind, id, key: `/v1/${parts[1]}/${encodeURIComponent(id)}` };
  }
  // /v1/idols/:id/facts (アイドルの項目の束。同期のときに組んだ文書を 1 行返すだけ)
  if (parts.length === 4 && kind === "idol" && parts[3] === "facts") {
    let id: string;
    try {
      id = decodeURIComponent(parts[2]);
    } catch {
      return { type: "bad", message: "id の percent-encoding が壊れています" };
    }
    if (id.length === 0 || id.length > ID_MAX) return { type: "bad", message: "id が不正です" };
    return { type: "facts", id, key: `/v1/idols/${encodeURIComponent(id)}/facts` };
  }
  if (parts.length !== 2) return { type: "none" };

  const p = url.searchParams;
  const allowed = new Set(["q", "brand", "limit", "cursor", ...(kind === "song" ? ["idol"] : [])]);
  for (const k of p.keys()) {
    if (!allowed.has(k)) return { type: "bad", message: `知らない引数: ${k} (使えるのは ${[...allowed].join(" / ")})` };
  }
  const num = (name: string, def: number, min: number, max: number): number | string => {
    const raw = p.get(name);
    if (raw === null || raw === "") return def;
    if (!/^\d{1,9}$/.test(raw)) return `${name} は整数です`;
    const n = Number(raw);
    return n < min || n > max ? `${name} は ${min}〜${max} です` : n;
  };
  const limit = num("limit", DEFAULT_LIMIT, 1, MAX_LIMIT);
  if (typeof limit === "string") return { type: "bad", message: limit };
  const cursor = num("cursor", 0, 0, 999_999_999);
  if (typeof cursor === "string") return { type: "bad", message: cursor };
  const brand = p.get("brand") || undefined;
  if (brand !== undefined && !BRAND_RE.test(brand)) return { type: "bad", message: "brand が不正です" };
  const idol = p.get("idol") || undefined;
  if (idol !== undefined && idol.length > ID_MAX) return { type: "bad", message: "idol が不正です" };
  const q = p.get("q") || undefined;
  if (q !== undefined && q.length > 64) return { type: "bad", message: "q は 64 文字までです" };
  if (q !== undefined && idol !== undefined) return { type: "bad", message: "q と idol は同時に使えません" };

  const key = `/v1/${parts[1]}?` + [
    ["brand", brand], ["cursor", cursor === 0 ? undefined : String(cursor)], ["idol", idol],
    ["limit", limit === DEFAULT_LIMIT ? undefined : String(limit)], ["q", q],
  ]
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${encodeURIComponent(v as string)}`)
    .join("&");
  return { type: "list", kind, q, brand, idol, limit, cursor, key };
}

async function run(route: Exclude<Route, { type: "none" } | { type: "bad" }>, env: Env, deps: Deps): Promise<Response> {
  switch (route.type) {
    case "meta": {
      const { results } = await env.DB.prepare(SQL_META).all<{ key: string; value: string }>();
      return json(200, Object.fromEntries(results.map((r) => [r.key, r.value])), OK_CACHE);
    }
    case "brands":
      return docResponse(env, "brands", "all");
    case "doc":
      return docResponse(env, route.kind, route.id);
    case "facts":
      return docResponse(env, "facts", route.id);
    case "list": {
      const prefix = route.q === undefined ? undefined : deps.fold(route.q);
      if (prefix === "") return fail(400, "bad_request", "q が空になります");
      const built = buildList({
        kind: route.kind, prefix, brand: route.brand, idol: route.idol, cursor: route.cursor, limit: route.limit,
      });
      const { results } = await env.DB.prepare(built.sql).bind(...built.binds).all<Record<string, unknown>>();
      const more = results.length > route.limit;
      const page = results.slice(0, route.limit);
      const items = page.map((r) => item(route.kind, r));
      const next = more ? (page[page.length - 1].ord as number) : null;
      return json(200, { items, next_cursor: next }, OK_CACHE);
    }
  }
}

async function docResponse(env: Env, kind: string, id: string): Promise<Response> {
  const row = await env.DB.prepare(SQL_DOC).bind(kind, id).first<{ body: string }>();
  if (!row) return fail(404, "not_found", `${kind} ${id} は見つかりません`, MISS_CACHE);
  return json(200, row.body, OK_CACHE);
}

function item(kind: ListKind, r: Record<string, unknown>): Record<string, unknown> {
  const plural = kind === "idol" ? "idols" : kind === "song" ? "songs" : "units";
  const out: Record<string, unknown> = { id: r.id };
  if (kind === "song") out.title = r.title;
  else out.name = r.name;
  if (r.name_kana ?? r.title_kana) out.kana = r.name_kana ?? r.title_kana;
  if (r.brand_id) out.brand_id = r.brand_id;
  if (kind === "idol" && r.is_external) out.is_external = true;
  if (kind === "unit") out.is_permanent = Boolean(r.is_permanent);
  if (kind === "song" && r.release_date) out.release_date = r.release_date;
  out.path = `/v1/${plural}/${encodeURIComponent(String(r.id))}`;
  return out;
}
