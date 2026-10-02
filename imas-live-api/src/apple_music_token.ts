// apple_music_token.ts — Apple Music のデベロッパトークン (ES256 の JWT) をその場で署名する。
//
// Android の MusicKit SDK は、再生とサインインのためにプロセス内でトークンを要求する。
// APK に焼き込むと取り出せるうえ失効で再生が止まるので、Worker が短命のトークンを配る
// (routes/music_token.ts)。鍵は Worker の secret (APPLE_MUSIC_PRIVATE_KEY / _KEY_ID / _TEAM_ID)。

import type { Env } from "./env";

/** 1 回の利用 (曲を聴く・記録する) を跨げる長さ。 */
const TOKEN_TTL_SECONDS = 6 * 60 * 60;

/** isolate が生きている間だけ使い回す。永続化はしない。 */
let cached: { value: string; expiresAt: number } | null = null;

export class AppleMusicNotConfigured extends Error {}

function decodePrivateKey(pem: string): ArrayBuffer {
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "").replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const base64urlText = (text: string) => base64url(new TextEncoder().encode(text));

/** 署名済みトークンと失効時刻 (epoch 秒)。WebCrypto の署名は JWT と同じ (r‖s) 形なので変換は要らない。 */
export async function signedAppleMusicToken(env: Env): Promise<{ token: string; expiresAt: number }> {
  const now = Math.floor(Date.now() / 1000);
  // 残り 30 分を切った使い回しは配らない (受け取った直後に切れる)。
  if (cached && cached.expiresAt - 30 * 60 > now) return { token: cached.value, expiresAt: cached.expiresAt };
  const { APPLE_MUSIC_PRIVATE_KEY, APPLE_MUSIC_KEY_ID, APPLE_MUSIC_TEAM_ID } = env;
  if (!APPLE_MUSIC_PRIVATE_KEY || !APPLE_MUSIC_KEY_ID || !APPLE_MUSIC_TEAM_ID) {
    throw new AppleMusicNotConfigured("apple music credentials are not configured");
  }
  const expiresAt = now + TOKEN_TTL_SECONDS;
  const input = `${base64urlText(JSON.stringify({ alg: "ES256", kid: APPLE_MUSIC_KEY_ID, typ: "JWT" }))}.` +
    base64urlText(JSON.stringify({ iss: APPLE_MUSIC_TEAM_ID, iat: now, exp: expiresAt }));
  const key = await crypto.subtle.importKey("pkcs8", decodePrivateKey(APPLE_MUSIC_PRIVATE_KEY),
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  const token = `${input}.${base64url(new Uint8Array(signature))}`;
  cached = { value: token, expiresAt };
  return { token, expiresAt };
}

/** テスト用: 使い回しを捨てる。 */
export function resetAppleMusicTokenCache(): void {
  cached = null;
}
