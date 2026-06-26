// cloudkit.ts — CloudKit S2S auth (ECDSA P-256) + records/modify + records/lookup + records/query

import { ckFieldType } from "./ck_schema";

const BASE_URL = "https://api.apple-cloudkit.com";
const CONTAINER = "iCloud.com.fugaif.ImasLiveDB";
const MODIFY_PATH = `/database/1/${CONTAINER}/production/public/records/modify`;
const LOOKUP_PATH = `/database/1/${CONTAINER}/production/public/records/lookup`;
const QUERY_PATH = `/database/1/${CONTAINER}/production/public/records/query`;

// ---------------------------------------------------------------------------
// Key import (cached per PEM string — Workers isolate reuse across requests in same instance)
// ---------------------------------------------------------------------------

const keyCache = new Map<string, CryptoKey>();

async function importP256PrivateKey(pem: string): Promise<CryptoKey> {
  const cached = keyCache.get(pem);
  if (cached) return cached;

  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
  keyCache.set(pem, key);
  return key;
}

// ---------------------------------------------------------------------------
// DER encode helpers (for raw signature → DER)
// ---------------------------------------------------------------------------

function encodeLength(len: number): Uint8Array {
  if (len < 0x80) return new Uint8Array([len]);
  const bytes = [];
  let tmp = len;
  while (tmp > 0) {
    bytes.unshift(tmp & 0xff);
    tmp >>= 8;
  }
  return new Uint8Array([0x80 | bytes.length, ...bytes]);
}

function encodeDerInt(bytes: Uint8Array): Uint8Array {
  // Trim leading zeros, but keep at least 1 byte
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  let trimmed = bytes.slice(start);
  // Prepend 0x00 if high bit is set (avoid negative number interpretation)
  if (trimmed[0] & 0x80) {
    const padded = new Uint8Array(trimmed.length + 1);
    padded[0] = 0x00;
    padded.set(trimmed, 1);
    trimmed = padded;
  }
  const lenBytes = encodeLength(trimmed.length);
  const result = new Uint8Array(1 + lenBytes.length + trimmed.length);
  result[0] = 0x02; // INTEGER tag
  result.set(lenBytes, 1);
  result.set(trimmed, 1 + lenBytes.length);
  return result;
}

/**
 * Convert raw 64-byte signature (r||s) to DER SEQUENCE.
 */
function rawToDer(rawSig: Uint8Array): Uint8Array {
  const r = encodeDerInt(rawSig.slice(0, 32));
  const s = encodeDerInt(rawSig.slice(32));
  const seqLen = r.length + s.length;
  const lenBytes = encodeLength(seqLen);
  const result = new Uint8Array(1 + lenBytes.length + seqLen);
  result[0] = 0x30; // SEQUENCE tag
  result.set(lenBytes, 1);
  result.set(r, 1 + lenBytes.length);
  result.set(s, 1 + lenBytes.length + r.length);
  return result;
}

// ---------------------------------------------------------------------------
// Sign request headers
// ---------------------------------------------------------------------------

async function signRequest(
  body: Uint8Array,
  subpath: string,
  keyId: string,
  privKeyPem: string
): Promise<Record<string, string>> {
  const dateStr = new Date().toISOString().replace(/\.\d{3}/, "");
  // SHA-256 of body → base64
  const bodyHashBuf = await crypto.subtle.digest("SHA-256", body);
  const bodyHash = btoa(String.fromCharCode(...new Uint8Array(bodyHashBuf)));
  const message = `${dateStr}:${bodyHash}:${subpath}`;

  // Sign with WebCrypto (P-256 / ECDSA-SHA256) via PKCS8 key
  const privKey = await importP256PrivateKey(privKeyPem);
  const rawSig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privKey,
    new TextEncoder().encode(message)
  );

  // WebCrypto returns raw r||s (64 bytes); CloudKit expects DER
  const rawArr = new Uint8Array(rawSig);
  const derSig = rawToDer(rawArr);
  const sigBase64 = btoa(String.fromCharCode(...derSig));

  return {
    "Content-Type": "application/json",
    "X-Apple-CloudKit-Request-KeyID": keyId,
    "X-Apple-CloudKit-Request-ISO8601Date": dateStr,
    "X-Apple-CloudKit-Request-SignatureV1": sigBase64,
  };
}

// ---------------------------------------------------------------------------
// CloudKit modify
// ---------------------------------------------------------------------------

export interface CloudKitOperation {
  operationType: "forceUpdate" | "forceDelete" | "create" | "delete";
  record: {
    recordType: string;
    recordName: string;
    fields: Record<string, { value: unknown; type?: string }>;
  };
}

export interface CloudKitModifyResult {
  ok: boolean;
  error?: string;
}

export async function cloudKitModify(
  operations: CloudKitOperation[],
  keyId: string,
  privKeyPem: string
): Promise<CloudKitModifyResult> {
  const payload = { operations };
  const body = new TextEncoder().encode(JSON.stringify(payload));

  let headers: Record<string, string>;
  try {
    headers = await signRequest(body, MODIFY_PATH, keyId, privKeyPem);
  } catch (e: any) {
    return { ok: false, error: `sign error: ${e.message}` };
  }

  const res = await fetch(`${BASE_URL}${MODIFY_PATH}`, {
    method: "POST",
    headers,
    body,
  });

  if (res.ok) return { ok: true };
  const text = await res.text().catch(() => "");
  return { ok: false, error: `CloudKit HTTP ${res.status}: ${text.slice(0, 300)}` };
}

// ---------------------------------------------------------------------------
// CloudKit lookup — recordName から現在のフィールドを権威的に取得 (before 取得用)
// ---------------------------------------------------------------------------

export interface CloudKitRecord {
  recordType: string;
  recordName: string;
  fields: Record<string, { value: unknown; type?: string }>;
}

export interface CloudKitLookupResult {
  ok: boolean;
  /** recordName → レコード。CloudKit に存在しない recordName はキーごと欠落する。 */
  records?: Map<string, CloudKitRecord>;
  error?: string;
}

/**
 * recordName のリストから CloudKit Public DB の現在値を取得する。
 * 編集の before スナップショットをサーバが権威的に得るために使う
 * (クライアント送信の before は改竄可能で revert を汚染しうるため信頼しない)。
 */
export async function cloudKitLookup(
  recordNames: string[],
  keyId: string,
  privKeyPem: string
): Promise<CloudKitLookupResult> {
  if (recordNames.length === 0) return { ok: true, records: new Map() };

  const payload = { records: recordNames.map((recordName) => ({ recordName })) };
  const body = new TextEncoder().encode(JSON.stringify(payload));

  let headers: Record<string, string>;
  try {
    headers = await signRequest(body, LOOKUP_PATH, keyId, privKeyPem);
  } catch (e: any) {
    return { ok: false, error: `sign error: ${e.message}` };
  }

  const res = await fetch(`${BASE_URL}${LOOKUP_PATH}`, { method: "POST", headers, body });
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    return { ok: false, error: `CloudKit HTTP ${res.status}: ${text.slice(0, 300)}` };
  }

  const data = (await res.json().catch(() => null)) as
    | { records?: Array<CloudKitRecord & { serverErrorCode?: string }> }
    | null;
  const out = new Map<string, CloudKitRecord>();
  for (const rec of data?.records ?? []) {
    // 存在しないレコードは serverErrorCode: "NOT_FOUND" で返る → before=なし (create 相当) として扱うため map に載せない
    if (rec.serverErrorCode) continue;
    if (rec.recordName && rec.fields) {
      out.set(rec.recordName, { recordType: rec.recordType, recordName: rec.recordName, fields: rec.fields });
    }
  }
  return { ok: true, records: out };
}

// ---------------------------------------------------------------------------
// CloudKit query — フィールド等値で recordType をまとめて取得 (ShowSetlist スナップショット用)
// ---------------------------------------------------------------------------

export interface CloudKitQueryResult {
  ok: boolean;
  /** マッチした全レコード (continuationMarker を辿って全件取得済み)。 */
  records?: CloudKitRecord[];
  error?: string;
}

/**
 * recordType を 1 つのフィールド等値フィルタで全件 query する。
 * setlist の show 単位スナップショットを得るために使う:
 *   - SetlistItem を showId == <show.id> で取得
 *   - SetlistPerformer を setlistItemId == <item.id> で取得 (item ごとに 1 query)
 *
 * lookup と同じく before スナップショットの権威取得経路なので、クライアント送信値は使わない。
 * continuationMarker を辿り全件取得する (1 show のセトリは高々数十件だが安全のため)。
 *
 * filterValue の型は ck_schema を正として明示付与する (showId/setlistItemId は STRING)。
 */
export async function cloudKitQuery(
  recordType: string,
  filterField: string,
  filterValue: unknown,
  keyId: string,
  privKeyPem: string
): Promise<CloudKitQueryResult> {
  const out: CloudKitRecord[] = [];
  const type = ckFieldType(recordType, filterField);
  let continuationMarker: string | undefined;

  // 無限ループ保護 (1 show あたり最大 50 ページ = 数千件)。
  for (let page = 0; page < 50; page++) {
    const payload: Record<string, unknown> = {
      query: {
        recordType,
        filterBy: [
          { fieldName: filterField, comparator: "EQUALS", fieldValue: { value: filterValue, type } },
        ],
      },
      resultsLimit: 200,
    };
    if (continuationMarker) payload.continuationMarker = continuationMarker;

    const body = new TextEncoder().encode(JSON.stringify(payload));
    let headers: Record<string, string>;
    try {
      headers = await signRequest(body, QUERY_PATH, keyId, privKeyPem);
    } catch (e: any) {
      return { ok: false, error: `sign error: ${e.message}` };
    }

    const res = await fetch(`${BASE_URL}${QUERY_PATH}`, { method: "POST", headers, body });
    if (!res.ok) {
      const text = await res.text().catch(() => "");
      return { ok: false, error: `CloudKit HTTP ${res.status}: ${text.slice(0, 300)}` };
    }
    const data = (await res.json().catch(() => null)) as
      | { records?: Array<CloudKitRecord & { serverErrorCode?: string }>; continuationMarker?: string }
      | null;
    for (const rec of data?.records ?? []) {
      if (rec.serverErrorCode) continue;
      if (!rec.recordName || !rec.fields) continue;
      // soft-deleted は現状スナップショットに含めない (deletedAt != null は論理削除済み)。
      const del = rec.fields.deletedAt?.value;
      if (del != null) continue;
      out.push({ recordType: rec.recordType, recordName: rec.recordName, fields: rec.fields });
    }
    continuationMarker = data?.continuationMarker;
    if (!continuationMarker) break;
  }
  return { ok: true, records: out };
}

/** CloudKit lookup の {value,type} fields を平坦な値マップへ。modifiedAt 等システム系は落とす。 */
export function flattenCkFields(fields: Record<string, { value: unknown; type?: string }>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) {
    if (k.startsWith("___")) continue;
    out[k] = v?.value ?? null;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Helper: build forceUpdate operation
// ---------------------------------------------------------------------------

/**
 * forceUpdate オペレーションを構築する。型は ck_schema を正として明示付与する
 * (値からの型推論は DOUBLE/BOOL/TIMESTAMP を誤判定するため使わない)。
 *
 * fields の値の扱い:
 *   - undefined        → そのフィールドは「変更しない」(送らない)
 *   - null             → そのフィールドを「明示的にクリア」(value:null を送る)
 *   - boolean          → INT64(0/1) に変換 (CloudKit に BOOL 型は無い)
 *   - その他           → ck_schema の型を付けて送信
 *
 * modifiedAt は差分同期 (predicate: modifiedAt > lastSync) のため常に bump する。
 */
export function buildForceUpdate(
  recordType: string,
  recordName: string,
  fields: Record<string, unknown>
): CloudKitOperation {
  const ckFields: Record<string, { value: unknown; type?: string }> = {};
  for (const [k, v] of Object.entries(fields)) {
    if (v === undefined) continue;
    if (k === "modifiedAt") continue; // 末尾で常に上書きするため無視
    const type = ckFieldType(recordType, k);
    if (v === null) {
      ckFields[k] = { value: null, type };
      continue;
    }
    const value = typeof v === "boolean" ? (v ? 1 : 0) : v;
    ckFields[k] = { value, type };
  }
  ckFields.modifiedAt = { value: Date.now(), type: "TIMESTAMP" };
  return {
    operationType: "forceUpdate",
    record: { recordType, recordName, fields: ckFields },
  };
}

/**
 * ソフト削除。deletedAt をセットする forceUpdate で実装する。
 *
 * 重要: ハード削除 (forceDelete) は iOS 差分同期が観測できない
 * (CloudKitSyncEngine は deletedAt != nil のレコードのみ削除として伝播し、
 *  CloudKit から物理消滅したレコードは modifiedAt > lastSync predicate に
 *  二度と乗らない)。よってアプリ経由の削除・revert は必ずソフト削除で行う。
 */
export function buildSoftDelete(recordType: string, recordName: string): CloudKitOperation {
  const now = Date.now();
  return {
    operationType: "forceUpdate",
    record: {
      recordType,
      recordName,
      fields: {
        deletedAt: { value: now, type: "TIMESTAMP" },
        modifiedAt: { value: now, type: "TIMESTAMP" },
      },
    },
  };
}
