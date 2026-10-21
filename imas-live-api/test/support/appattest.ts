// test/support/appattest.ts — App Attest の attestation / assertion をテスト内で組み立てる。
//
// 実機の attestation は手元に無いので、自前の P-384 ルート → P-384 中間 → P-256 leaf のチェーンを
// DER で書き、src/appattest.ts の verifyAttestationWithRoot に自前ルートの SPKI を渡して通す。
// 証明書は appattest.ts の最小パーサが読む形だけを満たす (issuer / subject は空、有効期限は見ない)。
//
// 既定値は「すべての検査に通る」組み合わせ。失敗の分岐は 1 項目だけ崩して作る。
// authData を崩すときは nonce も作り直さないと、目的の分岐の前に nonce mismatch で止まる
// (buildAttestation は崩した authData から nonce を計算するので、その心配は要らない)。

import { APP_ID } from "../../src/appattest";

// ---------------------------------------------------------------------------
// DER
// ---------------------------------------------------------------------------

function concat(...parts: Uint8Array[]): Uint8Array {
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let off = 0;
  for (const p of parts) { out.set(p, off); off += p.length; }
  return out;
}

function derLength(len: number): Uint8Array {
  if (len < 0x80) return new Uint8Array([len]);
  const bytes: number[] = [];
  for (let n = len; n > 0; n >>= 8) bytes.unshift(n & 0xff);
  return new Uint8Array([0x80 | bytes.length, ...bytes]);
}

const tlv = (tag: number, content: Uint8Array) => concat(new Uint8Array([tag]), derLength(content.length), content);
const seq = (...items: Uint8Array[]) => tlv(0x30, concat(...items));
const octets = (b: Uint8Array) => tlv(0x04, b);
const bitString = (b: Uint8Array) => tlv(0x03, concat(new Uint8Array([0]), b));
const explicit = (n: number, inner: Uint8Array) => tlv(0xa0 | n, inner);

function derInteger(bytes: Uint8Array): Uint8Array {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  let v: Uint8Array = bytes.slice(start);
  if (v[0] & 0x80) v = concat(new Uint8Array([0]), v);
  return tlv(0x02, v);
}

function oid(dotted: string): Uint8Array {
  const [a, b, ...rest] = dotted.split(".").map(Number);
  const out = [40 * a + b];
  for (const n of rest) {
    const chunk = [n & 0x7f];
    for (let v = n >> 7; v > 0; v >>= 7) chunk.unshift(0x80 | (v & 0x7f));
    out.push(...chunk);
  }
  return tlv(0x06, new Uint8Array(out));
}

/** WebCrypto の ECDSA 署名 (r‖s) を DER の SEQUENCE { r, s } にする。 */
export function ecdsaRawToDer(raw: Uint8Array): Uint8Array {
  const half = raw.length / 2;
  return seq(derInteger(raw.slice(0, half)), derInteger(raw.slice(half)));
}

const ECDSA_SHA384 = "1.2.840.10045.4.3.3";
const NONCE_OID = "1.2.840.113635.100.8.2";

/** issuerKey (P-384) で署名した X.509 v3 証明書。nonce を渡すと leaf の拡張に入れる。 */
async function certificate(subjectSpki: Uint8Array, issuerKey: CryptoKey, nonce?: Uint8Array): Promise<Uint8Array> {
  const sigAlg = seq(oid(ECDSA_SHA384));
  const utc = (s: string) => tlv(0x17, new TextEncoder().encode(s));
  const fields = [
    explicit(0, derInteger(new Uint8Array([2]))),
    derInteger(crypto.getRandomValues(new Uint8Array(8))),
    sigAlg,
    seq(), // issuer
    seq(utc("260101000000Z"), utc("270101000000Z")),
    seq(), // subject
    subjectSpki,
  ];
  if (nonce) {
    const ext = seq(oid(NONCE_OID), octets(seq(explicit(1, octets(nonce)))));
    fields.push(explicit(3, seq(ext)));
  }
  const tbs = seq(...fields);
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-384" }, issuerKey, tbs));
  return seq(tbs, sigAlg, bitString(ecdsaRawToDer(raw)));
}

// ---------------------------------------------------------------------------
// CBOR (text / bytes / array / map と非負整数だけ)
// ---------------------------------------------------------------------------

function cborHead(major: number, len: number): Uint8Array {
  if (len < 24) return new Uint8Array([(major << 5) | len]);
  if (len < 0x100) return new Uint8Array([(major << 5) | 24, len]);
  if (len < 0x10000) return new Uint8Array([(major << 5) | 25, len >> 8, len & 0xff]);
  return new Uint8Array([(major << 5) | 26, len >>> 24, (len >> 16) & 0xff, (len >> 8) & 0xff, len & 0xff]);
}

export function cbor(value: unknown): Uint8Array {
  if (typeof value === "number") return cborHead(0, value);
  if (typeof value === "string") {
    const b = new TextEncoder().encode(value);
    return concat(cborHead(3, b.length), b);
  }
  if (value instanceof Uint8Array) return concat(cborHead(2, value.length), value);
  if (Array.isArray(value)) return concat(cborHead(4, value.length), ...value.map(cbor));
  const entries = Object.entries(value as Record<string, unknown>);
  return concat(cborHead(5, entries.length), ...entries.flatMap(([k, v]) => [cbor(k), cbor(v)]));
}

export function b64(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

const sha256 = async (b: Uint8Array) => new Uint8Array(await crypto.subtle.digest("SHA-256", b));

// ---------------------------------------------------------------------------
// authenticatorData / attestation / assertion
// ---------------------------------------------------------------------------

export async function rpIdHash(appId = APP_ID): Promise<Uint8Array> {
  return sha256(new TextEncoder().encode(appId));
}

function counterBytes(n: number): Uint8Array {
  return new Uint8Array([n >>> 24, (n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff]);
}

/** rpIdHash(32) ‖ flags(1) ‖ counter(4) ‖ aaguid(16) ‖ credIdLen(2) ‖ credId */
export function attestAuthData(o: { rpIdHash: Uint8Array; counter: number; aaguid: string; credId: Uint8Array }): Uint8Array {
  const aaguid = new Uint8Array(16);
  aaguid.set(new TextEncoder().encode(o.aaguid).slice(0, 16));
  return concat(
    o.rpIdHash, new Uint8Array([0x40]), counterBytes(o.counter), aaguid,
    new Uint8Array([o.credId.length >> 8, o.credId.length & 0xff]), o.credId
  );
}

/** rpIdHash(32) ‖ flags(1) ‖ counter(4) */
export function assertAuthData(o: { rpIdHash: Uint8Array; counter: number }): Uint8Array {
  return concat(o.rpIdHash, new Uint8Array([0x40]), counterBytes(o.counter));
}

const P384 = { name: "ECDSA", namedCurve: "P-384" } as const;
const P256 = { name: "ECDSA", namedCurve: "P-256" } as const;
const spki = async (k: CryptoKey) => new Uint8Array((await crypto.subtle.exportKey("spki", k)) as ArrayBuffer);

/** 自前のルート・中間・端末の鍵。テストファイルで 1 回作って使い回す。 */
export interface AttestKeys {
  root: CryptoKeyPair;
  rootSpki: Uint8Array;
  intermediate: CryptoKeyPair;
  device: CryptoKeyPair;
  deviceSpki: Uint8Array;
}

export async function makeAttestKeys(): Promise<AttestKeys> {
  const gen = (alg: typeof P384 | typeof P256) =>
    crypto.subtle.generateKey(alg, true, ["sign", "verify"]) as Promise<CryptoKeyPair>;
  const [root, intermediate, device] = await Promise.all([gen(P384), gen(P384), gen(P256)]);
  return { root, rootSpki: await spki(root.publicKey), intermediate, device, deviceSpki: await spki(device.publicKey) };
}

export interface AttestationOptions {
  challenge: Uint8Array;
  keyId: Uint8Array;
  fmt?: string;
  appId?: string;
  counter?: number;
  aaguid?: string;
  credId?: Uint8Array;
  /** 中間証明書に署名する鍵 (既定はルート)。 */
  intermediateSigner?: CryptoKey;
  /** leaf に署名する鍵 (既定は中間)。 */
  leafSigner?: CryptoKey;
  /** leaf の nonce を差し替える (既定は authData と challenge から正しく計算した値)。 */
  nonce?: Uint8Array;
}

/** attestation object (CBOR) を base64 で返す。 */
export async function buildAttestation(keys: AttestKeys, o: AttestationOptions): Promise<string> {
  const authData = attestAuthData({
    rpIdHash: await rpIdHash(o.appId),
    counter: o.counter ?? 0,
    aaguid: o.aaguid ?? "appattest",
    credId: o.credId ?? o.keyId,
  });
  const nonce = o.nonce ?? (await sha256(concat(authData, await sha256(o.challenge))));
  const interCert = await certificate(await spki(keys.intermediate.publicKey), o.intermediateSigner ?? keys.root.privateKey);
  const leafCert = await certificate(keys.deviceSpki, o.leafSigner ?? keys.intermediate.privateKey, nonce);
  return b64(cbor({ fmt: o.fmt ?? "apple-appattest", attStmt: { x5c: [leafCert, interCert] }, authData }));
}

/** assertion object (CBOR { signature, authenticatorData }) を base64 で返す。 */
export async function buildAssertion(
  device: CryptoKey,
  o: { challenge: Uint8Array; counter: number; appId?: string }
): Promise<string> {
  const authenticatorData = assertAuthData({ rpIdHash: await rpIdHash(o.appId), counter: o.counter });
  const nonce = await sha256(concat(authenticatorData, await sha256(o.challenge)));
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, device, nonce));
  return b64(cbor({ signature: ecdsaRawToDer(raw), authenticatorData }));
}
