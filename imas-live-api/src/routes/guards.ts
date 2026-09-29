// routes/guards.ts — ルートの入口で繰り返す確認 (端末 ID・IP の枠・本文・パスの値・BAN)。
//
// どれも「値か、そのまま返せる応答 (Response) か」を返す形にそろえてある。
// 呼び出し側は `if (x instanceof Response) return x;` で抜ける。
// 文言とステータスは、ここへ集める前の各ルートのものと同じ。

import { isRevokedSession, type AuthUser } from "../auth";
import {
  dryCheckIpRateLimit,
  type IpRateCheck,
  type IpRateLimits,
  type IpRateScope,
} from "../rate_limit";
import { validateOpaqueKey } from "../validation";
import type { RouteContext } from "./context";

/** ここの関数が使う RouteContext の一部 (使う項目だけを受け取る)。 */
type ErrorResponder = Pick<RouteContext, "error">;
type DbContext = Pick<RouteContext, "env" | "error">;

/** 呼び出し元の IP。Cloudflare が必ず付けるので、無いのはローカルで動かしたときだけ。 */
export function clientIp(request: Request): string {
  return request.headers.get("CF-Connecting-IP") || "unknown";
}

/** X-Device-Id (端末ごとの集計の主体)。無ければ 400。 */
export function requireDeviceId(ctx: ErrorResponder & Pick<RouteContext, "request">): string | Response {
  return ctx.request.headers.get("X-Device-Id") || ctx.error("X-Device-Id header is required");
}

/**
 * IP 単位の分 (と日) の枠が残っているかを確かめる。尽きていれば 429。
 * ここでは数えない。数えるのは、呼び出し側が成功の地点で commitIpRateLimit を呼んだときだけ
 * (断った要求や、何もしなかった取り消しで枠を減らさないため。数える地点はルートごとに違う)。
 */
export async function requireIpQuota(
  ctx: Pick<RouteContext, "request" | "env" | "rateLimitSimple">,
  scope: IpRateScope,
  limits?: IpRateLimits
): Promise<IpRateCheck | Response> {
  const check = await dryCheckIpRateLimit(ctx.env.DB, scope, clientIp(ctx.request), limits);
  return check.allowed ? check : ctx.rateLimitSimple();
}

/**
 * 端末集計の書き込み (お気に入り・ペンライト・タグ) の入口: X-Device-Id 必須 → IP の枠。
 * 枠は成功の地点で commitIpRateLimit(env.DB, ipQuota) を呼んで数える。
 */
export async function requireDeviceWrite(
  ctx: RouteContext
): Promise<{ deviceId: string; ipQuota: IpRateCheck } | Response> {
  const deviceId = requireDeviceId(ctx);
  if (deviceId instanceof Response) return deviceId;
  const ipQuota = await requireIpQuota(ctx, "community");
  if (ipQuota instanceof Response) return ipQuota;
  return { deviceId, ipQuota };
}

/**
 * パスの 1 区間を percent-decode する。壊れた符号化 (%G0 や、途中で切れた UTF-8) は
 * 400 `invalid <name>` (decodeURIComponent の例外を 500 にしない)。
 */
export function decodePathParam(ctx: ErrorResponder, raw: string, name: string): string | Response {
  try {
    return decodeURIComponent(raw);
  } catch {
    return ctx.error(`invalid ${name}`);
  }
}

/** JSON の本文の項目。値は unknown なので、使う前に型を確かめること。 */
export type JsonFields = Readonly<Record<string, unknown>>;

/**
 * 本文を JSON として読む。壊れた JSON と `null` は 400 (`message`)。
 * オブジェクトでない値 (数値・文字列・配列) は項目の無いものとして返し、
 * 後段の項目の検証 ("name is required" 等) に任せる (集める前の各ルートと同じ応答)。
 */
export async function readJsonBody(
  ctx: ErrorResponder & Pick<RouteContext, "request">,
  message = "invalid JSON body"
): Promise<JsonFields | Response> {
  const body: unknown = await ctx.request.json().catch(() => null);
  if (body === null) return ctx.error(message);
  return typeof body === "object" && !Array.isArray(body) ? (body as JsonFields) : {};
}

/** 本文の不透明キー (曲・アイドル・候補の ID) を確かめて文字列で返す。空・長すぎは 400。 */
export function requireOpaqueKey(ctx: ErrorResponder, value: unknown, fieldName: string): string | Response {
  const invalid = validateOpaqueKey(value, fieldName);
  if (invalid !== null || typeof value !== "string") return ctx.error(invalid ?? `${fieldName} is required`);
  return value;
}

/**
 * 書き込んでよいアカウントかを、users の行 1 行で確かめる。認証 (getAuthUser) の後に呼ぶ。
 *   - 退会で無効になったセッション (行が無い・作り直した行より前の発行) → 401
 *   - BAN → 403
 * だめなら返す応答、よければ null。日次の枠 (checkRateLimit) と Promise.all で並べて走らせてよい。
 * 読むのは今までの BAN の確認と同じ 1 行 (列を足しただけ)。
 */
export async function requireActiveUser(ctx: DbContext, user: AuthUser): Promise<Response | null> {
  const row = await ctx.env.DB.prepare("SELECT is_banned, created_at FROM users WHERE id = ?")
    .bind(user.uid)
    .first<{ is_banned: number; created_at: string }>();
  if (isRevokedSession(user, row)) return ctx.error("Unauthorized", 401);
  return row?.is_banned ? ctx.error("Banned", 403) : null;
}
