// jwt.ts — JWT の分解、HS256 の署名と検証、RS256 (JWKS) の検証と、JWKS のキャッシュ。
//
// クレーム (iss / aud / exp / iat / sub) の判定は使う側 (auth.ts のセッションと Apple / Google、
// appattest.ts のアプリ実体トークン) が持つ。ここはトークンの形と署名だけを扱う。

import { base64ToBytes, bytesToBase64Url, fromUtf8, utf8 } from "./bytes";

/** 分解した JWT。header と payload は JSON として読めたもの (中身の型は使う側が確かめる)。 */
export interface DecodedJwt {
  header: Record<string, unknown>;
  payload: Record<string, unknown>;
  /** 署名の対象 (`<header>.<payload>`)。 */
  signingInput: string;
  signature: Uint8Array;
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

/** `<header>.<payload>.<signature>` を分解する。形が違えば null (署名はまだ見ない)。 */
export function decodeJwt(token: string): DecodedJwt | null {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  try {
    const header: unknown = JSON.parse(fromUtf8(base64ToBytes(parts[0])));
    const payload: unknown = JSON.parse(fromUtf8(base64ToBytes(parts[1])));
    if (!isRecord(header) || !isRecord(payload)) return null;
    return {
      header,
      payload,
      signingInput: `${parts[0]}.${parts[1]}`,
      signature: base64ToBytes(parts[2]),
    };
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// HS256
// ---------------------------------------------------------------------------

/** HMAC-SHA256 の鍵 (JWT の HS256 と、App Attest のチャレンジの MAC で使う)。 */
export async function hmacKey(secret: string, usage: "sign" | "verify"): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", utf8(secret), { name: "HMAC", hash: "SHA-256" }, false, [usage]);
}

/** HS256 で署名した JWT を作る (header は {alg: "HS256", typ: "JWT"})。 */
export async function signHs256(payload: Record<string, unknown>, secret: string): Promise<string> {
  const header = bytesToBase64Url(utf8(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = bytesToBase64Url(utf8(JSON.stringify(payload)));
  const signingInput = `${header}.${body}`;
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(secret, "sign"), utf8(signingInput));
  return `${signingInput}.${bytesToBase64Url(new Uint8Array(sig))}`;
}

/** HS256 の署名が正しいか (header の alg / typ は使う側が見る)。 */
export async function verifyHs256(jwt: DecodedJwt, secret: string): Promise<boolean> {
  return crypto.subtle.verify("HMAC", await hmacKey(secret, "verify"), jwt.signature, utf8(jwt.signingInput));
}

// ---------------------------------------------------------------------------
// RS256 (Apple / Google の ID トークン)
// ---------------------------------------------------------------------------

/** RS256 の署名が正しいか。鍵は JWKS の 1 本 (kid で選んだもの)。 */
export async function verifyRs256(jwt: DecodedJwt, jwk: JsonWebKey): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
  return crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, jwt.signature, utf8(jwt.signingInput));
}

/**
 * JWKS (公開鍵の一覧) のキャッシュ。1 isolate に 1 つ。
 *   - 正常に取れた応答だけを ttlMs のあいだ使う。取得に失敗したら手元の前の鍵のまま、
 *     retryMs たってから取り直す (失敗や壊れた応答を 1 時間抱え込まない)。
 *   - 知らない kid が来たら 1 回だけ取り直す (鍵の更新の直後にログインが 401 にならないように)。
 *     知らない kid を並べた要求で取得を繰り返させないよう、この取り直しは retryMs に 1 回まで。
 */
export class JwksCache {
  private keys: JsonWebKey[] | null = null;
  /** これより後なら取り直す。 */
  private staleAt = 0;
  /** 知らない kid での取り直しを、これより前はしない。 */
  private refetchAllowedAt = 0;

  constructor(
    private readonly url: string,
    private readonly ttlMs = 60 * 60 * 1000,
    private readonly retryMs = 60 * 1000
  ) {}

  /** kid の鍵。無ければ null。 */
  async find(kid: unknown): Promise<JsonWebKey | null> {
    let refreshed = false;
    if (Date.now() >= this.staleAt) {
      await this.refresh();
      refreshed = true;
    }
    const hit = pick(this.keys, kid);
    if (hit || refreshed || Date.now() < this.refetchAllowedAt) return hit;
    this.refetchAllowedAt = Date.now() + this.retryMs;
    await this.refresh();
    return pick(this.keys, kid);
  }

  private async refresh(): Promise<void> {
    try {
      const res = await fetch(this.url);
      const body: unknown = res.ok ? await res.json() : null;
      if (isRecord(body) && Array.isArray(body.keys)) {
        this.keys = body.keys as JsonWebKey[];
        this.staleAt = Date.now() + this.ttlMs;
        return;
      }
    } catch {
      // 通信の失敗・JSON でない応答は、下の「前の鍵のまま少し待つ」に落とす。
    }
    this.staleAt = Date.now() + this.retryMs;
  }
}

function pick(keys: JsonWebKey[] | null, kid: unknown): JsonWebKey | null {
  return keys?.find((k) => (k as { kid?: unknown }).kid === kid) ?? null;
}
