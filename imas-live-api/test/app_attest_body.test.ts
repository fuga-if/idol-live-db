// /app/attest・/app/assert の本文の検証。文字列でない値や base64 として読めない challenge は、
// 500 ではなく 400 で返す。検証に通らない証明は 401 で、内部の例外メッセージは本文に載せない。

import { afterEach, describe, expect, it, vi } from "vitest";
import { callJson } from "./support/worker";
import { exec } from "./support/d1";

describe("アプリ証明の本文", () => {
  it.each(["/app/attest", "/app/assert"])("%s: 文字列でない・空の項目は 400 bad request", async (path) => {
    const proof = path === "/app/attest" ? "attestation" : "assertion";
    for (const body of [
      { keyId: 5, [proof]: "p", challenge: "AAAA" },
      { keyId: "k", [proof]: {}, challenge: "AAAA" },
      { keyId: "k", [proof]: "p", challenge: "" },
      [1, 2],
    ]) {
      const res = await callJson("POST", path, { body });
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body).toEqual({ error: "bad request" });
    }
  });

  it.each(["/app/attest", "/app/assert"])("%s: base64 として読めない challenge は 400 bad challenge", async (path) => {
    const proof = path === "/app/attest" ? "attestation" : "assertion";
    const res = await callJson("POST", path, { body: { keyId: "k", [proof]: "p", challenge: "!!!!" } });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "bad challenge" });
  });
});

describe("検証に通らない証明", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  /** 発行したばかりの正しいチャレンジ (チャレンジの検証は通り、証明の検証で落ちる)。 */
  async function challenge(): Promise<string> {
    return (await callJson("GET", "/app/challenge")).body.challenge;
  }

  function failureLog(errors: { mock: { calls: unknown[][] } }) {
    const line = errors.mock.calls.map((c) => String(c[0])).find((l) => l.includes("app_attest_failed"));
    return line ? JSON.parse(line) : null;
  }

  it("/app/attest: 401 の本文は固定の文言。例外メッセージは request id と一緒にログにだけ出す", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    const res = await callJson("POST", "/app/attest", {
      body: { keyId: "a2V5", attestation: "bm90LWF0dGVzdGF0aW9u", challenge: await challenge() },
    });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "attestation failed" });
    expect(failureLog(errors)).toMatchObject({
      event: "app_attest_failed", step: "attestation", requestId: expect.any(String), error: expect.any(String),
    });
  });

  it("/app/assert: 401 の本文は固定の文言。例外メッセージは request id と一緒にログにだけ出す", async () => {
    const errors = vi.spyOn(console, "error").mockImplementation(() => {});
    await exec(
      "INSERT INTO app_attest_keys (key_id, public_key, counter, created_at, updated_at) VALUES ('k1', 'AAAA', 0, 0, 0)"
    );
    const res = await callJson("POST", "/app/assert", {
      body: { keyId: "k1", assertion: "bm90LWFzc2VydGlvbg", challenge: await challenge() },
    });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "assertion failed" });
    expect(failureLog(errors)).toMatchObject({
      event: "app_attest_failed", step: "assertion", requestId: expect.any(String), error: expect.any(String),
    });
  });
});
