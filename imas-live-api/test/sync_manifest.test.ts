// GET /sync/manifest — 同期の目録 (型ごとの最新 modifiedAt)。CloudKit は fetchMock で返す。

import { fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { callJson, makeEnv } from "./support/worker";
import { SYNC_RECORD_TYPES } from "../src/routes/sync_manifest";

const CK_ORIGIN = "https://api.apple-cloudkit.com";
const CK_QUERY = "/database/1/iCloud.com.fugaif.ImasLiveDB/production/public/records/query";

let ckEnv: ReturnType<typeof makeEnv>;

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  ckEnv = makeEnv({
    CLOUDKIT_KEY_ID: "test-key",
    CLOUDKIT_PRIVATE_KEY: `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----`,
  });
});

afterEach(() => vi.restoreAllMocks());

/** 型ごとの応答を決めて、全型ぶんの query を受ける。 */
function serveQueries(reply: (recordType: string) => { status: number; body: unknown }) {
  const asked: unknown[] = [];
  fetchMock
    .get(CK_ORIGIN)
    .intercept({ path: CK_QUERY, method: "POST" })
    .reply((req) => {
      const payload = JSON.parse(String(req.body));
      asked.push(payload);
      const { status, body } = reply(payload.query.recordType);
      return { statusCode: status, data: JSON.stringify(body) };
    })
    .times(SYNC_RECORD_TYPES.length);
  return asked;
}

describe("GET /sync/manifest", () => {
  it("型ごとの最新 modifiedAt を返し、エッジで共有させる。空の型は null", async () => {
    const asked = serveQueries((type) => ({
      status: 200,
      body: type === "Costume" ? { records: [] } : { records: [{ recordName: "x", fields: { modifiedAt: { value: 1_700_000_000_123 } } }] },
    }));
    const before = Date.now();
    const res = await callJson("GET", "/sync/manifest", { env: ckEnv });
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe("public, max-age=60");
    expect(Object.keys(res.body.types).sort()).toEqual([...SYNC_RECORD_TYPES].sort());
    expect(res.body.types.Song).toBe(1_700_000_000_123);
    expect(res.body.types.Costume).toBeNull();
    expect(res.body.generatedAt).toBeGreaterThanOrEqual(before);
    expect(res.body.generatedAt).toBeLessThanOrEqual(Date.now());
    // 1 型 1 件、modifiedAt の新しい順で、列は modifiedAt だけ。
    expect(asked).toHaveLength(SYNC_RECORD_TYPES.length);
    expect(asked[0]).toMatchObject({
      resultsLimit: 1,
      desiredKeys: ["modifiedAt"],
      query: {
        // 絞り込み無しだと本番の CloudKit は「recordName が queryable でない」で断る。
        filterBy: [{ fieldName: "modifiedAt", comparator: "GREATER_THAN", fieldValue: { value: 0, type: "TIMESTAMP" } }],
        sortBy: [{ fieldName: "modifiedAt", ascending: false }],
      },
    });
  });

  it("引けなかった型は載せない (アプリは載っていない型を従来どおり問い合わせる)", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    serveQueries((type) =>
      type === "Song"
        ? { status: 503, body: {} }
        : { status: 200, body: { records: [{ fields: { modifiedAt: { value: 5 } } }] } }
    );
    const res = await callJson("GET", "/sync/manifest", { env: ckEnv });
    expect(res.status).toBe(200);
    expect("Song" in res.body.types).toBe(false);
    expect(res.body.types.Brand).toBe(5);
  });

  it("全部引けなければ 503 で、キャッシュさせない", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    serveQueries(() => ({ status: 500, body: {} }));
    const res = await callJson("GET", "/sync/manifest", { env: ckEnv });
    expect(res.status).toBe(503);
    expect(res.res.headers.get("Cache-Control") ?? "").not.toContain("public");
  });
});
