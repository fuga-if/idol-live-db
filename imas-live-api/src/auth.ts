// auth.ts — 認証 (Apple / Google の ID トークン検証と、自前セッション JWT)。
//
// index.ts のルーターから切り離してあるのは、ルート群を routes/ へ移すときに
// getAuthUser を import し返す循環を避けるため。検証の厳密さ (alg/iss/aud/exp/
// iat/kid) は Apple 側の仕様に依存するので、ここを緩めないこと。

import type { Env } from "./env";

export const SESSION_JWT_ISSUER = "imas-live-db";
// 名前は "-ios" だが実体は自前セッションJWT共通の aud 固定値 (Android の Google Sign-In 経由でも同じ値を使う)。
const SESSION_JWT_AUDIENCE = "imas-live-db-ios";
export const SESSION_JWT_TTL_SECONDS = 60 * 60 * 24 * 365;

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

export async function verifyAppleToken(
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
// Google Sign In ID token verification (Android)
// ---------------------------------------------------------------------------

let cachedGoogleKeys: { keys: JsonWebKey[]; fetchedAt: number } | null = null;

async function getGooglePublicKeys(): Promise<JsonWebKey[]> {
  if (cachedGoogleKeys && Date.now() - cachedGoogleKeys.fetchedAt < 3600000) {
    return cachedGoogleKeys.keys;
  }
  const res = await fetch("https://www.googleapis.com/oauth2/v3/certs");
  const jwks = (await res.json()) as { keys: JsonWebKey[] };
  cachedGoogleKeys = { keys: jwks.keys, fetchedAt: Date.now() };
  return jwks.keys;
}

/** Android の Credential Manager (GetGoogleIdOption) が返す ID トークンを検証する。
 *  aud は Android クライアント ID ではなく指定した serverClientId (= Web クライアント ID) になる仕様。
 *  uid は Apple の sub と衝突しないよう "google:" を前置する (users テーブルは provider 非依存の opaque id)。 */
export async function verifyGoogleToken(
  token: string,
  webClientId: string
): Promise<{ uid: string; email?: string; picture?: string; name?: string } | null> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    const headerJson = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[0])));
    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));

    if (headerJson.alg !== "RS256") return null;
    if (typeof payload.exp !== "number" || payload.exp < Date.now() / 1000) return null;
    if (typeof payload.iat !== "number" || payload.iat > Date.now() / 1000 + 60) return null;
    if (payload.iss !== "https://accounts.google.com" && payload.iss !== "accounts.google.com") return null;
    if (payload.aud !== webClientId) return null;
    if (typeof payload.sub !== "string" || !payload.sub) return null;

    const keys = await getGooglePublicKeys();
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

    return { uid: `google:${payload.sub}`, email: payload.email, picture: payload.picture, name: payload.name };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Self-issued session JWT (HS256, 1 年)
// Apple identityToken (10 分) を毎リクエスト送る代わりに、 初回ログイン時に
// /auth/login で発行 → クライアントが Keychain で保持。
// ---------------------------------------------------------------------------

export function base64UrlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * Web Crypto の鍵用途。`@cloudflare/workers-types` の `importKey` は `keyUsages` を
 * `string[]` としか型付けしないため (DOM lib は Worker に無い API まで見えるので入れない)、
 * 実際に使う用途だけを列挙したローカル型で呼び出し側を縛る。
 */
type HmacKeyUsage = "sign" | "verify";

async function importHmacKey(secret: string, usage: HmacKeyUsage[]): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    usage
  );
}

export async function signSessionToken(uid: string, secret: string): Promise<string> {
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

export async function verifySessionToken(
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
export async function verifySessionTokenForRefresh(
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
export function peekJwtIssuer(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(parts[1])));
    return typeof payload.iss === "string" ? payload.iss : null;
  } catch {
    return null;
  }
}

export async function getAuthUser(
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
