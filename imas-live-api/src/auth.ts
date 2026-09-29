// auth.ts — 認証 (Apple / Google の ID トークン検証と、自前セッション JWT)。
//
// index.ts のルーターから切り離してあるのは、ルート群を routes/ へ移すときに
// getAuthUser を import し返す循環を避けるため。検証の厳密さ (alg/iss/aud/exp/
// iat/kid) は Apple 側の仕様に依存するので、ここを緩めないこと。

import type { Env } from "./env";
import { decodeJwt, JwksCache, signHs256, verifyHs256, verifyRs256, type DecodedJwt } from "./jwt";
import { sqliteTimestampToEpochSeconds } from "./time";

export const SESSION_JWT_ISSUER = "imas-live-db";
// 名前は "-ios" だが実体は自前セッションJWT共通の aud 固定値 (Android の Google Sign-In 経由でも同じ値を使う)。
const SESSION_JWT_AUDIENCE = "imas-live-db-ios";
export const SESSION_JWT_TTL_SECONDS = 60 * 60 * 24 * 365;

/** 認証済みの呼び出し元。uid は Apple の sub か "google:" + Google の sub。 */
export interface AuthUser {
  uid: string;
  email?: string;
  /**
   * 自前のセッション JWT で認証したとき、その発行時刻 (iat 秒。無いトークンは null)。
   * Apple の ID トークンをそのまま使う互換の経路では undefined。
   */
  session?: { issuedAt: number | null };
}

/** セッションの発行がアカウントの作成より前でも許す幅 (時計のずれ)。 */
const SESSION_REISSUE_SKEW_SECONDS = 10 * 60;

/**
 * 退会で無効になったセッションか。自前のセッション JWT だけが対象で、
 *   - users の行が無い (退会した)
 *   - 行が作られた時刻より 10 分以上前に発行されている (退会したあと同じ人がまた登録した)
 * のどちらかなら true。行は呼び出し側が既に読んでいるものを渡す (このために読み足さない)。
 */
export function isRevokedSession(user: AuthUser, row: { created_at?: string | null } | null): boolean {
  if (!user.session) return false;
  if (!row) return true;
  const { issuedAt } = user.session;
  if (issuedAt === null) return false;
  return issuedAt < sqliteTimestampToEpochSeconds(row.created_at) - SESSION_REISSUE_SKEW_SECONDS;
}

// ---------------------------------------------------------------------------
// Apple / Google の ID トークン (RS256)
// ---------------------------------------------------------------------------

const APPLE_JWKS = new JwksCache("https://appleid.apple.com/auth/keys");
const GOOGLE_JWKS = new JwksCache("https://www.googleapis.com/oauth2/v3/certs");

/** RS256 の ID トークンの共通の確認: alg・exp・iat (未来は 60 秒まで)。 */
function hasValidRs256Timing(jwt: DecodedJwt): boolean {
  const now = Date.now() / 1000;
  const { exp, iat } = jwt.payload;
  if (jwt.header.alg !== "RS256") return false;
  if (typeof exp !== "number" || exp < now) return false;
  if (typeof iat !== "number" || iat > now + 60) return false;
  return true;
}

/** JWKS から kid の鍵を選んで署名を確かめる。 */
async function hasValidRs256Signature(jwt: DecodedJwt, jwks: JwksCache): Promise<boolean> {
  const key = await jwks.find(jwt.header.kid);
  return key !== null && (await verifyRs256(jwt, key));
}

export async function verifyAppleToken(
  token: string,
  bundleId: string
): Promise<{ uid: string; email?: string } | null> {
  try {
    const jwt = decodeJwt(token);
    if (!jwt || !hasValidRs256Timing(jwt)) return null;
    const { payload } = jwt;
    if (payload.iss !== "https://appleid.apple.com") return null;
    if (payload.aud !== bundleId) return null;
    if (!(await hasValidRs256Signature(jwt, APPLE_JWKS))) return null;
    return { uid: payload.sub as string, email: payload.email as string | undefined };
  } catch {
    return null;
  }
}

/** Android の Credential Manager (GetGoogleIdOption) が返す ID トークンを検証する。
 *  aud は Android クライアント ID ではなく指定した serverClientId (= Web クライアント ID) になる仕様。
 *  uid は Apple の sub と衝突しないよう "google:" を前置する (users テーブルは provider 非依存の opaque id)。 */
export async function verifyGoogleToken(
  token: string,
  webClientId: string
): Promise<{ uid: string; email?: string; picture?: string; name?: string } | null> {
  try {
    const jwt = decodeJwt(token);
    if (!jwt || !hasValidRs256Timing(jwt)) return null;
    const { payload } = jwt;
    if (payload.iss !== "https://accounts.google.com" && payload.iss !== "accounts.google.com") return null;
    if (payload.aud !== webClientId) return null;
    if (typeof payload.sub !== "string" || !payload.sub) return null;
    if (!(await hasValidRs256Signature(jwt, GOOGLE_JWKS))) return null;
    return {
      uid: `google:${payload.sub}`,
      email: payload.email as string | undefined,
      picture: payload.picture as string | undefined,
      name: payload.name as string | undefined,
    };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Self-issued session JWT (HS256, 1 年)
// Apple identityToken (10 分) を毎リクエスト送る代わりに、 初回ログイン時に
// /auth/login で発行 → クライアントが Keychain で保持。
// ---------------------------------------------------------------------------

/** secret の下限。短い secret では発行も検証もしない。 */
const MIN_SECRET_LENGTH = 32;

export async function signSessionToken(uid: string, secret: string): Promise<string> {
  if (secret.length < MIN_SECRET_LENGTH) {
    throw new Error("SESSION_JWT_SECRET must be at least 32 chars");
  }
  const now = Math.floor(Date.now() / 1000);
  return signHs256(
    { iss: SESSION_JWT_ISSUER, aud: SESSION_JWT_AUDIENCE, sub: uid, iat: now, exp: now + SESSION_JWT_TTL_SECONDS },
    secret
  );
}

/**
 * 自前セッション JWT を検証する。header は HS256 / JWT、iss と aud は固定値 (aud 欠落も reject)、
 * sub は文字列、iat は未来 60 秒まで。exp は expGraceSeconds だけ過ぎていても通す (refresh 用)。
 */
async function verifySession(
  token: string,
  secret: string,
  expGraceSeconds: number
): Promise<{ uid: string; issuedAt: number | null } | null> {
  try {
    if (secret.length < MIN_SECRET_LENGTH) return null;
    const jwt = decodeJwt(token);
    if (!jwt || jwt.header.alg !== "HS256" || jwt.header.typ !== "JWT") return null;
    if (!(await verifyHs256(jwt, secret))) return null;
    const { iss, aud, exp, iat, sub } = jwt.payload;
    const now = Date.now() / 1000;
    if (iss !== SESSION_JWT_ISSUER) return null;
    // 確定契約 §5: aud 欠落トークンも reject (aud は必須。トークン用途固定で取り違えを防ぐ)。
    if (aud !== SESSION_JWT_AUDIENCE) return null;
    if (typeof exp !== "number" || exp < now - expGraceSeconds) return null;
    if (typeof iat === "number" && iat > now + 60) return null;
    if (typeof sub !== "string") return null;
    return { uid: sub, issuedAt: typeof iat === "number" ? iat : null };
  } catch {
    return null;
  }
}

export async function verifySessionToken(token: string, secret: string): Promise<AuthUser | null> {
  const verified = await verifySession(token, secret, 0);
  return verified && { uid: verified.uid, session: { issuedAt: verified.issuedAt } };
}

/** sliding refresh 用: 署名 + iss/aud が有効なら、exp 切れでも猶予内なら uid を返す。
 *  攻撃者が偽造できない (署名検証は通常どおり)。古すぎる (exp が猶予より前) トークンは拒否。 */
const REFRESH_GRACE_SECONDS = 60 * 60 * 24 * 90; // 期限切れ後90日まで再発行可
export async function verifySessionTokenForRefresh(token: string, secret: string): Promise<AuthUser | null> {
  const verified = await verifySession(token, secret, REFRESH_GRACE_SECONDS);
  return verified && { uid: verified.uid, session: { issuedAt: verified.issuedAt } };
}

/** JWT の iss クレームだけ覗いて自前セッションか Apple か振り分ける (署名はまだ見ない)。 */
export function peekJwtIssuer(token: string): string | null {
  const iss = decodeJwt(token)?.payload.iss;
  return typeof iss === "string" ? iss : null;
}

export async function getAuthUser(request: Request, env: Env): Promise<AuthUser | null> {
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
