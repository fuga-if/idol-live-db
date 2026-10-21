// App Attest の attestation / assertion の検証 (appattest.ts) と、/app/assert の成功の流れ。
//
// attestation は実機の fixture が無いので、test/support/appattest.ts で自前のルートからチェーンを組み、
// トラストアンカーを引数で受ける verifyAttestationWithRoot に通す。公開の verifyAttestation は
// Apple のルートしか信頼しないことも確かめる (自前のチェーンは中間の段で落ちる)。
// assertion は端末の鍵 (P-256) をテスト内で作って署名するので、ルートの経路まで本物で通る。

import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { verifyAssertion, verifyAttestation, verifyAttestationWithRoot, verifyAppToken } from "../src/appattest";
import { bytesToBase64Url } from "../src/bytes";
import { callJson, TEST_SECRET } from "./support/worker";
import { exec, row } from "./support/d1";
import { buildAssertion, buildAttestation, makeAttestKeys, type AttestKeys, type AttestationOptions } from "./support/appattest";

let keys: AttestKeys;
let otherKeys: AttestKeys;
const challenge = new TextEncoder().encode("challenge-bytes-for-test");
const keyId = crypto.getRandomValues(new Uint8Array(32));

beforeAll(async () => {
  [keys, otherKeys] = await Promise.all([makeAttestKeys(), makeAttestKeys()]);
});

afterEach(() => vi.restoreAllMocks());

async function attest(overrides: Partial<AttestationOptions> = {}, allowDev = false) {
  const att = await buildAttestation(keys, { challenge, keyId, ...overrides });
  return verifyAttestationWithRoot(challenge, keyId, att, allowDev, keys.rootSpki);
}

describe("verifyAttestationWithRoot", () => {
  it("チェーン・nonce・authData がそろえば、端末の公開鍵 (SPKI) と counter 0 を返す", async () => {
    expect(await attest()).toEqual({ spki: keys.deviceSpki, counter: 0 });
  });

  it("開発用の aaguid (appattestdevelop) は allowDev のときだけ通す", async () => {
    await expect(attest({ aaguid: "appattestdevelop" })).rejects.toThrow("bad aaguid: appattestdevelop");
    expect((await attest({ aaguid: "appattestdevelop" }, true)).counter).toBe(0);
  });

  it.each<[string, () => Partial<AttestationOptions>, string]>([
    ["fmt が apple-appattest でない", () => ({ fmt: "packed" }), "bad fmt"],
    ["中間が別のルートの署名", () => ({ intermediateSigner: otherKeys.root.privateKey }), "intermediate not signed by root"],
    ["leaf が別の中間の署名", () => ({ leafSigner: otherKeys.intermediate.privateKey }), "leaf not signed by intermediate"],
    ["leaf の nonce が違う", () => ({ nonce: new Uint8Array(32) }), "nonce mismatch"],
    ["別のアプリの rpId", () => ({ appId: "TEAMID.com.example.clone" }), "rpId mismatch"],
    ["counter が 0 でない", () => ({ counter: 1 }), "counter != 0"],
    ["credId が keyId と違う", () => ({ credId: new Uint8Array(32) }), "credId != keyId"],
    ["aaguid が不正", () => ({ aaguid: "something" }), "bad aaguid: something"],
  ])("%s は例外", async (_label, overrides, message) => {
    await expect(attest(overrides())).rejects.toThrow(message);
  });

  it("challenge が違えば nonce が合わない", async () => {
    const att = await buildAttestation(keys, { challenge, keyId });
    await expect(verifyAttestationWithRoot(new Uint8Array([1, 2, 3]), keyId, att, false, keys.rootSpki))
      .rejects.toThrow("nonce mismatch");
  });
});

describe("verifyAttestation (公開の口)", () => {
  it("Apple のルートだけを信頼する。自前のルートで組んだチェーンは中間の段で落ちる", async () => {
    const att = await buildAttestation(keys, { challenge, keyId });
    await expect(verifyAttestation(challenge, keyId, att)).rejects.toThrow("intermediate not signed by root");
  });
});

describe("verifyAssertion", () => {
  it("署名が通り counter が増えていれば新しい counter を返す", async () => {
    const assertion = await buildAssertion(keys.device.privateKey, { challenge, counter: 5 });
    expect(await verifyAssertion(challenge, assertion, keys.deviceSpki, 4)).toBe(5);
  });

  it.each<[string, () => Promise<[string, Uint8Array, number, Uint8Array?]>, string]>([
    ["別の端末の鍵で署名", async () => [await buildAssertion(otherKeys.device.privateKey, { challenge, counter: 5 }), keys.deviceSpki, 0], "assertion sig invalid"],
    ["challenge が違う", async () => [await buildAssertion(keys.device.privateKey, { challenge, counter: 5 }), keys.deviceSpki, 0, new Uint8Array([9])], "assertion sig invalid"],
    ["別のアプリの rpId", async () => [await buildAssertion(keys.device.privateKey, { challenge, counter: 5, appId: "X.com.example" }), keys.deviceSpki, 0], "rpId mismatch"],
    ["counter が増えていない (リプレイ)", async () => [await buildAssertion(keys.device.privateKey, { challenge, counter: 5 }), keys.deviceSpki, 5], "counter not increasing"],
  ])("%s は例外", async (_label, make, message) => {
    const [assertion, spki, prev, ch] = await make();
    await expect(verifyAssertion(ch ?? challenge, assertion, spki, prev)).rejects.toThrow(message);
  });
});

describe("POST /app/assert", () => {
  async function freshChallenge(): Promise<{ text: string; bytes: Uint8Array }> {
    const text = (await callJson("GET", "/app/challenge")).body.challenge as string;
    const bin = atob(text.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (text.length % 4)) % 4));
    return { text, bytes: Uint8Array.from(bin, (c) => c.charCodeAt(0)) };
  }

  it("登録済みの鍵の assertion でアプリ実体トークンを返し、counter を進める。同じ counter の再送は 401", async () => {
    await exec(
      "INSERT INTO app_attest_keys (key_id, public_key, counter, created_at, updated_at) VALUES ('dev-key', ?, 3, 0, 0)",
      bytesToBase64Url(keys.deviceSpki)
    );
    const ch = await freshChallenge();
    const assertion = await buildAssertion(keys.device.privateKey, { challenge: ch.bytes, counter: 4 });

    const res = await callJson("POST", "/app/assert", { body: { keyId: "dev-key", assertion, challenge: ch.text } });
    expect(res.status).toBe(200);
    expect(await verifyAppToken(res.body.appToken, TEST_SECRET)).toBe(true);
    const stored = await row<{ counter: number; updated_at: number }>("SELECT counter, updated_at FROM app_attest_keys WHERE key_id = 'dev-key'");
    expect(stored!.counter).toBe(4);
    expect(stored!.updated_at).toBeGreaterThan(0);

    vi.spyOn(console, "error").mockImplementation(() => {});
    const replay = await callJson("POST", "/app/assert", { body: { keyId: "dev-key", assertion, challenge: ch.text } });
    expect(replay.status).toBe(401);
    expect(replay.body).toEqual({ error: "assertion failed" });
  });

  it("登録の無い鍵は 401 unknown key、検証できない challenge は 400", async () => {
    const ch = await freshChallenge();
    const assertion = await buildAssertion(keys.device.privateKey, { challenge: ch.bytes, counter: 1 });
    expect((await callJson("POST", "/app/assert", { body: { keyId: "nobody", assertion, challenge: ch.text } })).body)
      .toEqual({ error: "unknown key" });
    const forged = bytesToBase64Url(new Uint8Array(56));
    expect((await callJson("POST", "/app/assert", { body: { keyId: "nobody", assertion, challenge: forged } })).body)
      .toEqual({ error: "bad challenge" });
  });
});
