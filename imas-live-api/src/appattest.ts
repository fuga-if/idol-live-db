// appattest.ts — 正規アプリだけが Worker を叩けるようにするアプリ証明検証。
//
// OSS 化に伴い「クローンアプリのただ乗り (read endpoint への無認証アクセス)」を防ぐ。
// 埋め込み秘密は OSS では無意味なので、プラットフォーム証明で正規性を担保する:
//   - iOS:     App Attest (DCAppAttestService) の attestation / assertion を検証
//   - Android: Play Integrity トークンを Google API で検証
// 検証が通った端末にだけ短命の「アプリ実体トークン (app token)」を発行し、
// read endpoint はそれ (または Apple 認証済みユーザセッション) を要求する。
//
// 安全なロールアウト: gate は env.APP_ATTEST_MODE で monitor/enforce を切替。
// monitor の間は失敗してもログのみで通す (実機で正規 attestation が通るのを確認してから enforce)。

const APP_ID = "GQ3WP34LFW.com.fugaif.ImasLiveDB"; // TeamID.bundleId
const ANDROID_PACKAGE = "com.fugaif.imaslivedb";
const APPLE_ROOT_PEM_URL =
  "https://www.apple.com/certificateauthority/Apple_App_Attest_Root_CA.pem";

// session token (iss=imas-live-db) とキードメインを分離し、取り違え昇格を防ぐ
const APP_TOKEN_ISS = "imas-app-attest";
const APP_TOKEN_AUD = "imas-app-attest";
const APP_TOKEN_TTL = 60 * 60 * 24; // 24h

// ---------------------------------------------------------------------------
// 小物: base64 / hash / hex
// ---------------------------------------------------------------------------

function b64ToBytes(b64: string): Uint8Array {
  let s = b64.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "="; // base64url (padding 無し) でも確実にデコード
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}
function bytesToB64Url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data));
}
function concat(...arrs: Uint8Array[]): Uint8Array {
  const len = arrs.reduce((n, a) => n + a.length, 0);
  const out = new Uint8Array(len);
  let o = 0;
  for (const a of arrs) { out.set(a, o); o += a.length; }
  return out;
}
function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a[i] ^ b[i];
  return d === 0;
}

// ---------------------------------------------------------------------------
// 最小 CBOR デコーダ (App Attest の attestation object に必要な部分集合)
// ---------------------------------------------------------------------------

function cborDecode(buf: Uint8Array): any {
  let pos = 0;
  function read(): any {
    const ib = buf[pos++];
    const major = ib >> 5;
    const minor = ib & 0x1f;
    const len = readLen(minor);
    switch (major) {
      case 0: return len; // uint
      case 1: return -1 - len; // negative
      case 2: { const v = buf.slice(pos, pos + len); pos += len; return v; } // bytes
      case 3: { const v = new TextDecoder().decode(buf.slice(pos, pos + len)); pos += len; return v; } // text
      case 4: { const arr = []; for (let i = 0; i < len; i++) arr.push(read()); return arr; }
      case 5: { const m: Record<string, any> = {}; for (let i = 0; i < len; i++) { const k = read(); m[k] = read(); } return m; }
      default: throw new Error("cbor: unsupported major " + major);
    }
  }
  function readLen(minor: number): number {
    if (minor < 24) return minor;
    if (minor === 24) return buf[pos++];
    if (minor === 25) { const v = (buf[pos] << 8) | buf[pos + 1]; pos += 2; return v; }
    if (minor === 26) { const v = (buf[pos] * 0x1000000) + (buf[pos + 1] << 16) + (buf[pos + 2] << 8) + buf[pos + 3]; pos += 4; return v; }
    throw new Error("cbor: length too large");
  }
  return read();
}

// ---------------------------------------------------------------------------
// 最小 ASN.1/DER パーサ
// ---------------------------------------------------------------------------

interface TLV { tag: number; start: number; len: number; contentStart: number; end: number; }
function readTLV(buf: Uint8Array, off: number): TLV {
  const tag = buf[off];
  let p = off + 1;
  let len = buf[p++];
  if (len & 0x80) {
    const n = len & 0x7f;
    len = 0;
    for (let i = 0; i < n; i++) len = (len << 8) | buf[p++];
  }
  return { tag, start: off, len, contentStart: p, end: p + len };
}
function children(buf: Uint8Array, t: TLV): TLV[] {
  const out: TLV[] = [];
  let p = t.contentStart;
  while (p < t.end) { const c = readTLV(buf, p); out.push(c); p = c.end; }
  return out;
}
function der(buf: Uint8Array, t: TLV): Uint8Array { return buf.slice(t.start, t.end); }

interface Cert { tbs: Uint8Array; sigAlgHash: string; sig: Uint8Array; spki: Uint8Array; raw: Uint8Array; tbsTLV: TLV; }
function parseCert(raw: Uint8Array): Cert {
  const root = readTLV(raw, 0);                 // Certificate ::= SEQUENCE
  const top = children(raw, root);              // [tbs, sigAlg, sigValue]
  const tbs = der(raw, top[0]);
  // signatureAlgorithm: SEQUENCE { OID }
  const sigAlgOid = oidString(raw, children(raw, top[1])[0]);
  const sigAlgHash = sigAlgOid.endsWith(".3.2") ? "SHA-256" : sigAlgOid.endsWith(".3.3") ? "SHA-384" : "SHA-256";
  // signatureValue: BIT STRING (先頭1byte unused-bits を除く)
  const sigBits = top[2];
  const sigDer = raw.slice(sigBits.contentStart + 1, sigBits.end);
  // tbs の子から subjectPublicKeyInfo を取り出す
  const tbsTLV = top[0];
  const tbsKids = children(raw, tbsTLV);
  // version[0] optional → SPKI は固定 index ではないので「AlgId+BITSTRING な SEQUENCE」を探す
  let spki: Uint8Array | null = null;
  for (const k of tbsKids) {
    if (k.tag !== 0x30) continue;
    const kk = children(raw, k);
    if (kk.length === 2 && kk[0].tag === 0x30 && kk[1].tag === 0x03) { spki = der(raw, k); /* 最後に見つかった SPKI 候補を使う前に break しない: subject の後の最初 */ }
  }
  if (!spki) throw new Error("cert: SPKI not found");
  return { tbs, sigAlgHash, sig: sigDer, spki, raw, tbsTLV };
}
function oidString(buf: Uint8Array, t: TLV): string {
  const b = buf.slice(t.contentStart, t.end);
  const parts = [Math.floor(b[0] / 40), b[0] % 40];
  let v = 0;
  for (let i = 1; i < b.length; i++) {
    v = (v << 7) | (b[i] & 0x7f);
    if (!(b[i] & 0x80)) { parts.push(v); v = 0; }
  }
  return parts.join(".");
}

// DER ECDSA 署名 (SEQUENCE{r,s}) → WebCrypto 用 raw (r||s, 各 size byte)
function derEcdsaToRaw(buf: Uint8Array, size: number): Uint8Array {
  const seq = readTLV(buf, 0);
  const [rT, sT] = children(buf, seq);
  const trim = (t: TLV) => {
    let s = t.contentStart, e = t.end;
    while (s < e - 1 && buf[s] === 0) s++;
    return buf.slice(s, e);
  };
  const r = trim(rT), s = trim(sT);
  const out = new Uint8Array(size * 2);
  out.set(r, size - r.length);
  out.set(s, size * 2 - s.length);
  return out;
}

async function importEcSpki(spki: Uint8Array, curve: "P-256" | "P-384"): Promise<CryptoKey> {
  return crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: curve }, false, ["verify"]);
}

// cert の署名を issuerSpki で検証
async function verifyCertSig(cert: Cert, issuerSpki: Uint8Array, issuerCurve: "P-256" | "P-384"): Promise<boolean> {
  const key = await importEcSpki(issuerSpki, issuerCurve);
  const size = issuerCurve === "P-384" ? 48 : 32;
  const raw = derEcdsaToRaw(cert.sig, size);
  return crypto.subtle.verify({ name: "ECDSA", hash: cert.sigAlgHash }, key, raw, cert.tbs);
}

// ---------------------------------------------------------------------------
// Apple App Attest Root CA (実行時に取得してキャッシュ)
// ---------------------------------------------------------------------------

// Apple App Attestation Root CA の SPKI (P-384) を定数で固定 (RedTeam H1)。
// 公開鍵なので OSS でも問題なし。トラストアンカーをネットワークに依存させない。
// 出所: https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
//   subject = CN=Apple App Attestation Root CA, O=Apple Inc., ST=California
//   cert SHA-256 = 1C:B9:82:3B:A2:8B:A6:AD:2D:33:A0:06:94:1D:E2:AE:4F:51:3E:F1:D4:E8:31:B9:F7:E0:FA:7B:62:42:C9:32
const APPLE_ROOT_SPKI_B64 =
  "MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdhNbJhFs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9auYen1mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41";
let _appleRootSpki: Uint8Array | null = null;
async function appleRootSpki(): Promise<Uint8Array> {
  if (_appleRootSpki) return _appleRootSpki;
  if (APPLE_ROOT_SPKI_B64) {
    _appleRootSpki = b64ToBytes(APPLE_ROOT_SPKI_B64);
    return _appleRootSpki;
  }
  const pem = await (await fetch(APPLE_ROOT_PEM_URL)).text();
  if (!pem.includes("BEGIN CERTIFICATE")) {
    throw new Error("apple root fetch did not return a certificate (embed APPLE_ROOT_SPKI_B64)");
  }
  const b64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  _appleRootSpki = parseCert(b64ToBytes(b64)).spki;
  return _appleRootSpki;
}

// ---------------------------------------------------------------------------
// authenticatorData パース
// ---------------------------------------------------------------------------

interface AuthData { rpIdHash: Uint8Array; counter: number; aaguid: Uint8Array; credId: Uint8Array; }
function parseAuthData(ad: Uint8Array): AuthData {
  const rpIdHash = ad.slice(0, 32);
  const counter = (ad[33] << 24) | (ad[34] << 16) | (ad[35] << 8) | ad[36];
  const aaguid = ad.slice(37, 53);
  const credIdLen = (ad[53] << 8) | ad[54];
  const credId = ad.slice(55, 55 + credIdLen);
  return { rpIdHash, counter, aaguid, credId };
}

// credCert から nonce 拡張 (OID 1.2.840.113635.100.8.2) を取り出す
function extractNonce(cert: Cert): Uint8Array | null {
  const tbsKids = children(cert.raw, cert.tbsTLV);
  const extsCtx = tbsKids.find((k) => k.tag === 0xa3); // [3] extensions
  if (!extsCtx) return null;
  const extsSeq = children(cert.raw, extsCtx)[0];
  for (const ext of children(cert.raw, extsSeq)) {
    const parts = children(cert.raw, ext);
    if (oidString(cert.raw, parts[0]) !== "1.2.840.113635.100.8.2") continue;
    const octet = parts[parts.length - 1]; // OCTET STRING
    // 中身: SEQUENCE { [1] { OCTET STRING nonce } }
    const inner = readTLV(cert.raw, octet.contentStart);
    const c1 = children(cert.raw, inner)[0]; // [1]
    const oct = children(cert.raw, c1)[0];   // OCTET STRING
    return cert.raw.slice(oct.contentStart, oct.end);
  }
  return null;
}

// ---------------------------------------------------------------------------
// 1) Attestation 検証 → 公開鍵(SPKI)と counter を返す
// ---------------------------------------------------------------------------

export interface AttestResult { spki: Uint8Array; counter: number; }

export async function verifyAttestation(
  challenge: Uint8Array,
  keyId: Uint8Array,
  attestationB64: string,
  allowDev = false
): Promise<AttestResult> {
  const obj = cborDecode(b64ToBytes(attestationB64));
  if (obj.fmt !== "apple-appattest") throw new Error("bad fmt");
  const x5c: Uint8Array[] = obj.attStmt.x5c;
  const authData: Uint8Array = obj.authData;
  const credCert = parseCert(x5c[0]);
  const interCert = parseCert(x5c[1]);

  // チェーン検証: leaf ← intermediate ← Apple Root
  const rootSpki = await appleRootSpki();
  if (!(await verifyCertSig(interCert, rootSpki, "P-384"))) throw new Error("intermediate not signed by root");
  if (!(await verifyCertSig(credCert, interCert.spki, "P-384"))) throw new Error("leaf not signed by intermediate");

  // nonce = SHA256(authData || SHA256(challenge))
  const clientDataHash = await sha256(challenge);
  const nonce = await sha256(concat(authData, clientDataHash));
  const certNonce = extractNonce(credCert);
  if (!certNonce || !bytesEqual(certNonce, nonce)) throw new Error("nonce mismatch");

  // rpIdHash == SHA256(appId), counter==0, credId==keyId
  const ad = parseAuthData(authData);
  if (!bytesEqual(ad.rpIdHash, await sha256(new TextEncoder().encode(APP_ID)))) throw new Error("rpId mismatch");
  if (ad.counter !== 0) throw new Error("counter != 0");
  if (!bytesEqual(ad.credId, keyId)) throw new Error("credId != keyId");
  const aaguidStr = new TextDecoder().decode(ad.aaguid).replace(/\0+$/, "");
  // 本番では production attestation ("appattest") のみ。dev は明示許可時だけ。
  if (aaguidStr !== "appattest" && !(allowDev && aaguidStr === "appattestdevelop")) {
    throw new Error("bad aaguid: " + aaguidStr);
  }

  return { spki: credCert.spki, counter: 0 };
}

// ---------------------------------------------------------------------------
// 2) Assertion 検証 (トークン再発行用・軽量)
// ---------------------------------------------------------------------------

export async function verifyAssertion(
  challenge: Uint8Array,
  assertionB64: string,
  storedSpki: Uint8Array,
  prevCounter: number
): Promise<number> {
  const obj = cborDecode(b64ToBytes(assertionB64)); // { signature, authenticatorData }
  const sig: Uint8Array = obj.signature;
  const authData: Uint8Array = obj.authenticatorData;
  const clientDataHash = await sha256(challenge);
  const nonce = await sha256(concat(authData, clientDataHash));
  const key = await importEcSpki(storedSpki, "P-256");
  const raw = derEcdsaToRaw(sig, 32);
  if (!(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, raw, nonce)))
    throw new Error("assertion sig invalid");
  const ad = parseAuthData(authData);
  if (!bytesEqual(ad.rpIdHash, await sha256(new TextEncoder().encode(APP_ID)))) throw new Error("rpId mismatch");
  if (ad.counter <= prevCounter) throw new Error("counter not increasing");
  return ad.counter;
}

// ---------------------------------------------------------------------------
// 3) Android: Play Integrity トークン検証 (Google API)
// ---------------------------------------------------------------------------

export async function verifyPlayIntegrity(
  token: string,
  expectedNonce: string,
  serviceAccountJson: string
): Promise<boolean> {
  const sa = JSON.parse(serviceAccountJson);
  const accessToken = await googleAccessToken(sa, "https://www.googleapis.com/auth/playintegrity");
  const res = await fetch(
    `https://playintegrity.googleapis.com/v1/${ANDROID_PACKAGE}:decodeIntegrityToken`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ integrity_token: token }),
    }
  );
  if (!res.ok) throw new Error("playintegrity decode failed: " + res.status);
  const data = (await res.json()) as any;
  const p = data?.tokenPayloadExternal ?? {};
  const rd = p?.requestDetails ?? {};
  const nonceOk = rd?.nonce === expectedNonce;
  const reqPkgOk = rd?.requestPackageName === ANDROID_PACKAGE;
  const pkgOk = p?.appIntegrity?.packageName === ANDROID_PACKAGE;
  const appVerdict = p?.appIntegrity?.appRecognitionVerdict;
  const deviceVerdict: string[] = p?.deviceIntegrity?.deviceRecognitionVerdict ?? [];
  // トークン鮮度 (10 分以内)。challenge TTL と二重で担保。
  const ts = Number(rd?.timestampMillis ?? 0);
  const freshOk = ts > 0 && Math.abs(Date.now() - ts) < 10 * 60 * 1000;
  return (
    nonceOk &&
    reqPkgOk &&
    pkgOk &&
    freshOk &&
    appVerdict === "PLAY_RECOGNIZED" &&
    deviceVerdict.includes("MEETS_DEVICE_INTEGRITY")
  );
}

// service account → OAuth2 access token (JWT bearer grant)
async function googleAccessToken(sa: any, scope: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = bytesToB64Url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claim = bytesToB64Url(new TextEncoder().encode(JSON.stringify({
    iss: sa.client_email, scope, aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600,
  })));
  const signingInput = `${header}.${claim}`;
  const pemBody = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8", b64ToBytes(pemBody), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]
  );
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(signingInput)));
  const jwt = `${signingInput}.${bytesToB64Url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tok = (await res.json()) as any;
  if (!tok.access_token) throw new Error("google token grant failed");
  return tok.access_token;
}

// ---------------------------------------------------------------------------
// 4) アプリ実体トークン (HS256 JWT)
// ---------------------------------------------------------------------------

async function hmacKey(secret: string, usage: ("sign" | "verify")[]): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, usage);
}

export async function mintAppToken(keyId: string, secret: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = bytesToB64Url(new TextEncoder().encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = bytesToB64Url(new TextEncoder().encode(JSON.stringify({
    iss: APP_TOKEN_ISS, aud: APP_TOKEN_AUD, sub: keyId, iat: now, exp: now + APP_TOKEN_TTL,
  })));
  const input = `${header}.${payload}`;
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(secret, ["sign"]), new TextEncoder().encode(input)));
  return `${input}.${bytesToB64Url(sig)}`;
}

export async function verifyAppToken(token: string, secret: string): Promise<boolean> {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return false;
    const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret, ["verify"]), b64ToBytes(parts[2]), new TextEncoder().encode(`${parts[0]}.${parts[1]}`));
    if (!ok) return false;
    const p = JSON.parse(new TextDecoder().decode(b64ToBytes(parts[1])));
    if (p.iss !== APP_TOKEN_ISS || p.aud !== APP_TOKEN_AUD) return false;
    if (typeof p.exp !== "number" || p.exp < Date.now() / 1000) return false;
    return true;
  } catch { return false; }
}

// ---------------------------------------------------------------------------
// 5) ステートレスなチャレンジ (リプレイ防止・D1 不要)
//    blob = random(16) || expMsBE(8) || HMAC(secret, random||exp)(32)
//    クライアントはこの blob 全体を App Attest の challenge / Play Integrity の nonce に使う。
// ---------------------------------------------------------------------------

const CHALLENGE_TTL_MS = 5 * 60 * 1000;

export async function makeChallenge(secret: string): Promise<Uint8Array> {
  const rnd = crypto.getRandomValues(new Uint8Array(16));
  const exp = Date.now() + CHALLENGE_TTL_MS;
  const expB = new Uint8Array(8);
  new DataView(expB.buffer).setFloat64(0, exp); // exp(ms) を 53bit 安全に格納
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(secret, ["sign"]), concat(rnd, expB)));
  return concat(rnd, expB, mac);
}

export async function checkChallenge(blob: Uint8Array, secret: string): Promise<boolean> {
  if (blob.length !== 16 + 8 + 32) return false;
  const rnd = blob.slice(0, 16);
  const expB = blob.slice(16, 24);
  const mac = blob.slice(24);
  const exp = new DataView(expB.buffer, expB.byteOffset, 8).getFloat64(0);
  if (!(exp > Date.now())) return false;
  const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret, ["verify"]), mac, concat(rnd, expB));
  return ok;
}

export { b64ToBytes, bytesToB64Url, APP_ID, ANDROID_PACKAGE };
