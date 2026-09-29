// test/support/jwt.ts — テスト用の JWT 署名 (自前セッションの HS256 と、Apple / Google を模した RS256)。

import { TEST_SECRET } from "./worker";

const enc = new TextEncoder();

export function b64url(bytes: Uint8Array | string): string {
  const data = typeof bytes === "string" ? enc.encode(bytes) : bytes;
  let bin = "";
  for (const b of data) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export function decodePayload(token: string): Record<string, unknown> {
  const part = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
  const bin = atob(part + "=".repeat((4 - (part.length % 4)) % 4));
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0))));
}

export function decodeHeader(token: string): Record<string, unknown> {
  return JSON.parse(atob(token.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")));
}

export const nowSec = () => Math.floor(Date.now() / 1000);

/** 任意の header / payload で HS256 の JWT を作る (期限切れ・aud 違い等を試すため)。 */
export async function signHs256(
  payload: Record<string, unknown>,
  secret = TEST_SECRET,
  header: Record<string, unknown> = { alg: "HS256", typ: "JWT" }
): Promise<string> {
  const input = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(input)));
  return `${input}.${b64url(sig)}`;
}

/** 自前セッション JWT と同じ形の payload (上書きで期限や aud を変える)。 */
export function sessionPayload(uid: string, overrides: Record<string, unknown> = {}) {
  const iat = nowSec();
  return { iss: "imas-live-db", aud: "imas-live-db-ios", sub: uid, iat, exp: iat + 3600, ...overrides };
}

/** Apple / Google の ID トークンを模す RS256 の鍵。JWKS は呼び出し側が fetchMock で返す。 */
export class FakeIdProvider {
  private constructor(
    private readonly keyPair: CryptoKeyPair,
    readonly kid: string,
    /** JWKS の keys[] にそのまま入れる公開鍵。 */
    readonly jwk: JsonWebKey
  ) {}

  static async create(kid: string): Promise<FakeIdProvider> {
    const keyPair = (await crypto.subtle.generateKey(
      { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
      true,
      ["sign", "verify"]
    )) as CryptoKeyPair;
    const jwk = (await crypto.subtle.exportKey("jwk", keyPair.publicKey)) as JsonWebKey;
    return new FakeIdProvider(keyPair, kid, { ...jwk, kid, alg: "RS256", use: "sig" } as JsonWebKey);
  }

  async sign(payload: Record<string, unknown>, header: Record<string, unknown> = {}): Promise<string> {
    const input = `${b64url(JSON.stringify({ alg: "RS256", kid: this.kid, ...header }))}.${b64url(JSON.stringify(payload))}`;
    const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", this.keyPair.privateKey, enc.encode(input)));
    return `${input}.${b64url(sig)}`;
  }
}

export const APPLE_ORIGIN = "https://appleid.apple.com";
export const APPLE_JWKS_PATH = "/auth/keys";
export const GOOGLE_ORIGIN = "https://www.googleapis.com";
export const GOOGLE_JWKS_PATH = "/oauth2/v3/certs";
