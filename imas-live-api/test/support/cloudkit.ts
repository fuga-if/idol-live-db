// test/support/cloudkit.ts — CloudKit Public DB の records/{lookup,query,modify} を手元のメモリで模す。
//
// オープン編集 (POST /edits) と revert は lookup → query → modify を何往復もするので、
// 1 回ずつ fetchMock.intercept を積むと順番に縛られて読めなくなる。ここではレコードを
// Map に持ち、3 つの path を persist した interceptor で受けて、送られた本文どおりに読み書きする。
//
// forceUpdate は送られたフィールドだけを既存レコードに重ねる (未送信のフィールドは残る)。
// value:null のフィールドはクリアとして消す。query は EQUALS の 1 条件だけを扱う
// (cloudKitQuery が送るのはそれだけ)。deletedAt の付いたレコードの除外は cloudKitQuery 側の仕事なので、
// ここでは除外せずに返す。

import { fetchMock } from "cloudflare:test";

export const CK_ORIGIN = "https://api.apple-cloudkit.com";
const PREFIX = "/database/1/iCloud.com.fugaif.ImasLiveDB/production/public/records";
export const CK_PATHS = {
  lookup: `${PREFIX}/lookup`,
  query: `${PREFIX}/query`,
  modify: `${PREFIX}/modify`,
} as const;
export type CkEndpoint = keyof typeof CK_PATHS;

type CkField = { value: unknown; type?: string };
export interface FakeRecord {
  recordType: string;
  recordName: string;
  fields: Record<string, CkField>;
}

/** CloudKit の S2S 署名に使う P-256 の秘密鍵 (PKCS#8 PEM)。テストごとに作る。 */
export async function testCloudKitKey(): Promise<string> {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  return `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----`;
}

export class FakeCloudKit {
  readonly records = new Map<string, FakeRecord>();
  /** 受けたリクエスト (発行順)。どの op を送ったかを assert するため。 */
  readonly requests: Array<{ endpoint: CkEndpoint; body: any }> = [];
  /** endpoint ごとに、次の n 回を HTTP 503 で失敗させる。 */
  private readonly failures: Partial<Record<CkEndpoint, number>> = {};

  /** 3 つの path に persist な interceptor を張る。fetchMock はファイル単位なので beforeAll で 1 回呼ぶ。 */
  install(): void {
    for (const endpoint of Object.keys(CK_PATHS) as CkEndpoint[]) {
      fetchMock
        .get(CK_ORIGIN)
        .intercept({ path: CK_PATHS[endpoint], method: "POST" })
        .reply((opts: { body?: unknown }) => this.handle(endpoint, String(opts.body ?? "")))
        .persist();
    }
  }

  /** テストの間で状態を持ち越さない (beforeEach で呼ぶ)。 */
  reset(): void {
    this.records.clear();
    this.requests.length = 0;
    for (const k of Object.keys(this.failures)) delete this.failures[k as CkEndpoint];
  }

  /** 平坦な値でレコードを置く (型は付けない。flattenCkFields は value しか見ない)。 */
  put(recordType: string, recordName: string, fields: Record<string, unknown>): void {
    const ck: Record<string, CkField> = {};
    for (const [k, v] of Object.entries(fields)) ck[k] = { value: v };
    this.records.set(recordName, { recordType, recordName, fields: ck });
  }

  /** レコードを平坦な値で返す (無ければ undefined)。 */
  get(recordName: string): Record<string, unknown> | undefined {
    const rec = this.records.get(recordName);
    if (!rec) return undefined;
    return Object.fromEntries(Object.entries(rec.fields).map(([k, v]) => [k, v.value]));
  }

  failNext(endpoint: CkEndpoint, times = 1): void {
    this.failures[endpoint] = (this.failures[endpoint] ?? 0) + times;
  }

  /** modify で送られた op を発行順に平らに並べる。 */
  modifiedOps(): Array<{ operationType: string; record: FakeRecord }> {
    return this.requests.filter((r) => r.endpoint === "modify").flatMap((r) => r.body.operations);
  }

  count(endpoint: CkEndpoint): number {
    return this.requests.filter((r) => r.endpoint === endpoint).length;
  }

  private handle(endpoint: CkEndpoint, raw: string): { statusCode: number; data: string } {
    const body = JSON.parse(raw);
    this.requests.push({ endpoint, body });
    if ((this.failures[endpoint] ?? 0) > 0) {
      this.failures[endpoint]! -= 1;
      return { statusCode: 503, data: JSON.stringify({ reason: "unavailable" }) };
    }
    const ok = (data: unknown) => ({ statusCode: 200, data: JSON.stringify(data) });
    switch (endpoint) {
      case "lookup":
        return ok({
          records: (body.records as Array<{ recordName: string }>).map(
            ({ recordName }) => this.records.get(recordName) ?? { recordName, serverErrorCode: "NOT_FOUND" }
          ),
        });
      case "query": {
        const { recordType, filterBy } = body.query;
        const [{ fieldName, fieldValue }] = filterBy;
        return ok({
          records: [...this.records.values()].filter(
            (r) => r.recordType === recordType && r.fields[fieldName]?.value === fieldValue.value
          ),
        });
      }
      case "modify": {
        for (const { record } of body.operations as Array<{ record: FakeRecord }>) {
          const current = this.records.get(record.recordName);
          const fields = { ...(current?.fields ?? {}) };
          for (const [k, v] of Object.entries(record.fields)) {
            if (v.value === null) delete fields[k];
            else fields[k] = v;
          }
          this.records.set(record.recordName, { recordType: record.recordType, recordName: record.recordName, fields });
        }
        return ok({ records: body.operations.map((o: { record: FakeRecord }) => o.record) });
      }
    }
  }
}
