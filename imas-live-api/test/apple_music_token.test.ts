// Apple Music のデベロッパトークン (apple_music_token.ts と GET /music-token)。
// テスト内で P-256 の鍵を作って env に渡し、ES256 の JWT の形と署名を確かめる。

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { callJson, makeEnv } from "./support/worker";
import { decodeHeader, decodePayload } from "./support/jwt";
import { resetAppleMusicTokenCache, signedAppleMusicToken } from "../src/apple_music_token";

let pem = "";
let publicKey: CryptoKey;

beforeAll(async () => {
  const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"])) as CryptoKeyPair;
  publicKey = pair.publicKey;
  const der = new Uint8Array((await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer);
  let bin = "";
  for (const b of der) bin += String.fromCharCode(b);
  // 実際の .p8 と同じく、本文を 64 文字で折り返す
  pem = `-----BEGIN PRIVATE KEY-----\n${btoa(bin).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
});

beforeEach(() => resetAppleMusicTokenCache());
afterEach(() => vi.useRealTimers());

function musicEnv() {
  return makeEnv({ APPLE_MUSIC_PRIVATE_KEY: pem, APPLE_MUSIC_KEY_ID: "KEY123", APPLE_MUSIC_TEAM_ID: "TEAM456" });
}

function fromB64url(s: string): Uint8Array {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (s.length % 4)) % 4));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

describe("signedAppleMusicToken", () => {
  it("ES256 で署名した 6 時間の JWT を返す (kid = 鍵 ID、iss = チーム ID)", async () => {
    const { token, expiresAt } = await signedAppleMusicToken(musicEnv());
    expect(decodeHeader(token)).toEqual({ alg: "ES256", kid: "KEY123", typ: "JWT" });
    const payload = decodePayload(token);
    expect(payload.iss).toBe("TEAM456");
    expect(payload.exp).toBe(expiresAt);
    expect(expiresAt - (payload.iat as number)).toBe(6 * 60 * 60);

    // 署名は JWT と同じ r‖s (64 バイト) で、公開鍵で検証できる
    const [h, p, sig] = token.split(".");
    const raw = fromB64url(sig);
    expect(raw.length).toBe(64);
    const valid = await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" }, publicKey, raw, new TextEncoder().encode(`${h}.${p}`)
    );
    expect(valid).toBe(true);
  });

  it("残りが 30 分を切るまでは同じトークンを使い回し、切ったら作り直す", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-10-08T00:00:00Z"));
    const first = await signedAppleMusicToken(musicEnv());

    vi.setSystemTime(new Date("2026-10-08T05:29:00Z"));
    expect((await signedAppleMusicToken(musicEnv())).token).toBe(first.token);

    vi.setSystemTime(new Date("2026-10-08T05:31:00Z"));
    const renewed = await signedAppleMusicToken(musicEnv());
    expect(renewed.token).not.toBe(first.token);
    expect(renewed.expiresAt).toBeGreaterThan(first.expiresAt);
  });

  it("鍵・鍵 ID・チーム ID のどれかが無ければ AppleMusicNotConfigured", async () => {
    await expect(signedAppleMusicToken(makeEnv({ APPLE_MUSIC_PRIVATE_KEY: pem, APPLE_MUSIC_KEY_ID: "KEY123" })))
      .rejects.toThrow("apple music credentials are not configured");
  });
});

describe("GET /music-token", () => {
  it("トークンと残り秒数を返し、エッジに 60 秒載せる", async () => {
    const res = await callJson("GET", "/music-token", { env: musicEnv() });
    expect(res.status).toBe(200);
    expect(decodeHeader(res.body.token).kid).toBe("KEY123");
    expect(res.body.expiresIn).toBeGreaterThan(6 * 60 * 60 - 5);
    expect(res.body.expiresIn).toBeLessThanOrEqual(6 * 60 * 60);
    expect(res.res.headers.get("Cache-Control")).toBe("public, max-age=60");
  });

  it("鍵が壊れていたら 503 ではなく 500 (設定漏れと区別する)", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const broken = makeEnv({ APPLE_MUSIC_PRIVATE_KEY: "-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----", APPLE_MUSIC_KEY_ID: "K", APPLE_MUSIC_TEAM_ID: "T" });
    const res = await callJson("GET", "/music-token?broken=1", { env: broken });
    expect(res.status).toBe(500);
  });
});
