// CloudKit の records/modify: HTTP 2xx でもレコード単位で失敗しうる (serverErrorCode)。
// 挙動 (ok: true を返す) は変えず、失敗したレコードを構造化してログに残す。

import { fetchMock } from "cloudflare:test";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { buildForceUpdate, cloudKitModify } from "../src/cloudkit";

const CK_ORIGIN = "https://api.apple-cloudkit.com";
const CK_MODIFY = "/database/1/iCloud.com.fugaif.ImasLiveDB/production/public/records/modify";

let pem = "";

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin)}\n-----END PRIVATE KEY-----`;
});

afterEach(() => vi.restoreAllMocks());

function captureErrors(): string[] {
  const lines: string[] = [];
  vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
  return lines;
}

const ops = [
  buildForceUpdate("Song", "s1", { title: "a" }),
  buildForceUpdate("Song", "s2", { title: "b" }),
];

describe("cloudKitModify", () => {
  it("レコード単位の失敗は ok のまま、失敗したレコードを構造化してログに出す", async () => {
    fetchMock.get(CK_ORIGIN).intercept({ path: CK_MODIFY, method: "POST" }).reply(200, {
      records: [
        { recordName: "s1", recordType: "Song", fields: {} },
        { recordName: "s2", serverErrorCode: "CONFLICT", reason: "record changed" },
      ],
    });
    const errors = captureErrors();
    expect(await cloudKitModify(ops, "key", pem)).toEqual({ ok: true });
    expect(errors).toHaveLength(1);
    expect(JSON.parse(errors[0])).toEqual({
      event: "cloudkit_modify_record_errors",
      operations: 2,
      failed: 1,
      errors: [{ recordName: "s2", serverErrorCode: "CONFLICT", reason: "record changed" }],
    });
  });

  it("全部成功ならログを出さない。本文が読めなくても ok のまま", async () => {
    fetchMock.get(CK_ORIGIN).intercept({ path: CK_MODIFY, method: "POST" }).reply(200, {
      records: [{ recordName: "s1" }, { recordName: "s2" }],
    });
    fetchMock.get(CK_ORIGIN).intercept({ path: CK_MODIFY, method: "POST" }).reply(200, "not json");
    const errors = captureErrors();
    expect(await cloudKitModify(ops, "key", pem)).toEqual({ ok: true });
    expect(await cloudKitModify(ops, "key", pem)).toEqual({ ok: true });
    expect(errors).toEqual([]);
  });

  it("HTTP の失敗は今までどおり ok: false と本文の先頭", async () => {
    fetchMock.get(CK_ORIGIN).intercept({ path: CK_MODIFY, method: "POST" }).reply(503, "unavailable");
    const res = await cloudKitModify(ops, "key", pem);
    expect(res).toEqual({ ok: false, error: "CloudKit HTTP 503: unavailable" });
  });
});
