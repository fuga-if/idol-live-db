// bytes.ts — バイト列の小物 (base64 / base64url / UTF-8 / 連結 / 定数時間の比較 / SHA-256 / PEM)。
//
// JWT (jwt.ts)・App Attest (appattest.ts)・CloudKit の署名 (cloudkit.ts)・運用者トークンの比較
// (routes/lyrics.ts) が同じ処理をそれぞれ書いていたので、ここに 1 つだけ置く。

const encoder = new TextEncoder();
const decoder = new TextDecoder();

/** 文字列を UTF-8 のバイト列にする。 */
export function utf8(s: string): Uint8Array {
  return encoder.encode(s);
}

/** UTF-8 のバイト列を文字列にする。 */
export function fromUtf8(bytes: Uint8Array): string {
  return decoder.decode(bytes);
}

/** base64 / base64url (パディングの有無を問わない) をバイト列にする。不正な文字は atob が投げる。 */
export function base64ToBytes(b64: string): Uint8Array {
  let s = b64.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** バイト列を base64 (パディングあり) にする。 */
export function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

/** バイト列を base64url (パディングなし。JWT の形) にする。 */
export function bytesToBase64Url(bytes: Uint8Array): string {
  return bytesToBase64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** バイト列をつなげる。 */
export function concatBytes(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let offset = 0;
  for (const p of parts) {
    out.set(p, offset);
    offset += p.length;
  }
  return out;
}

/** 長さ以外で時間が変わらない比較 (秘密の値の推測を、応答までの時間から助けない)。 */
export function timingSafeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** SHA-256。 */
export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}

/** PEM (-----BEGIN ...----- の囲みと改行) から中身の DER を取り出す。 */
export function pemToDer(pem: string): Uint8Array {
  return base64ToBytes(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, ""));
}
