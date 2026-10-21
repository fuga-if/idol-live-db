// auth.ts の検証関数を直接呼ぶ拒否の分岐。HTTP の経路は test/auth.test.ts にある。
// ここは 1 条件ずつ崩したトークンを作り、どれも null になることを表で確かめる。

import { fetchMock } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import {
  isRevokedSession,
  verifyAppleToken,
  verifyGoogleToken,
  verifySessionToken,
  verifySessionTokenForRefresh,
} from "../src/auth";
import { TEST_SECRET } from "./support/worker";
import {
  APPLE_JWKS_PATH, APPLE_ORIGIN, FakeIdProvider, GOOGLE_JWKS_PATH, GOOGLE_ORIGIN, nowSec, sessionPayload, signHs256,
} from "./support/jwt";

const BUNDLE_ID = "com.fugaif.ImasLiveDB";
const GOOGLE_CLIENT_ID = "web-client.apps.googleusercontent.com";

let apple: FakeIdProvider;
let google: FakeIdProvider;

beforeAll(async () => {
  apple = await FakeIdProvider.create("apple-kid-v");
  google = await FakeIdProvider.create("google-kid-v");
  fetchMock.get(APPLE_ORIGIN).intercept({ path: APPLE_JWKS_PATH }).reply(200, () => ({ keys: [apple.jwk] })).persist();
  fetchMock.get(GOOGLE_ORIGIN).intercept({ path: GOOGLE_JWKS_PATH }).reply(200, () => ({ keys: [google.jwk] })).persist();
});

describe("verifySessionToken", () => {
  it("正しいトークンは uid と発行時刻を返す", async () => {
    const payload = sessionPayload("u1");
    expect(await verifySessionToken(await signHs256(payload), TEST_SECRET))
      .toEqual({ uid: "u1", session: { issuedAt: payload.iat } });
  });

  it("iat の無いトークンは発行時刻 null で通す", async () => {
    const { iat: _, ...noIat } = sessionPayload("u1");
    expect(await verifySessionToken(await signHs256(noIat), TEST_SECRET))
      .toEqual({ uid: "u1", session: { issuedAt: null } });
  });

  it.each<[string, () => Promise<string>, string?]>([
    ["secret が 32 文字未満", async () => signHs256(sessionPayload("u1"), "short"), "short"],
    ["typ が JWT でない", async () => signHs256(sessionPayload("u1"), TEST_SECRET, { alg: "HS256", typ: "JWS" })],
    ["alg が HS256 でない", async () => signHs256(sessionPayload("u1"), TEST_SECRET, { alg: "HS384", typ: "JWT" })],
    ["iss 違い", async () => signHs256(sessionPayload("u1", { iss: "someone-else" }))],
    ["aud 欠落", async () => signHs256(sessionPayload("u1", { aud: undefined }))],
    ["exp 欠落", async () => signHs256(sessionPayload("u1", { exp: "never" }))],
    ["iat が 60 秒より先の未来", async () => signHs256(sessionPayload("u1", { iat: nowSec() + 120 }))],
    ["sub が文字列でない", async () => signHs256(sessionPayload("u1", { sub: 42 }))],
    ["形が JWT でない", async () => "not-a-jwt"],
  ])("%s は null", async (_label, make, secret = TEST_SECRET) => {
    expect(await verifySessionToken(await make(), secret)).toBeNull();
  });

  it("refresh は期限切れ 90 日まで通し、それより古いものと署名違いは通さない", async () => {
    const expired = await signHs256(sessionPayload("u1", { exp: nowSec() - 89 * 86400 }));
    expect(await verifySessionToken(expired, TEST_SECRET)).toBeNull();
    expect((await verifySessionTokenForRefresh(expired, TEST_SECRET))?.uid).toBe("u1");
    const tooOld = await signHs256(sessionPayload("u1", { exp: nowSec() - 91 * 86400 }));
    expect(await verifySessionTokenForRefresh(tooOld, TEST_SECRET)).toBeNull();
    const forged = await signHs256(sessionPayload("u1"), "another-secret-that-is-long-enough!!");
    expect(await verifySessionTokenForRefresh(forged, TEST_SECRET)).toBeNull();
  });
});

describe("isRevokedSession", () => {
  const created = "2026-10-01 00:00:00";
  const createdSec = Date.parse("2026-10-01T00:00:00Z") / 1000;

  it("自前セッションでなければ (Apple のトークンの互換経路) 対象外", () => {
    expect(isRevokedSession({ uid: "u1" }, null)).toBe(false);
  });

  it("users の行が無ければ無効", () => {
    expect(isRevokedSession({ uid: "u1", session: { issuedAt: createdSec } }, null)).toBe(true);
  });

  it("iat の無いトークンは判定できないので有効のまま", () => {
    expect(isRevokedSession({ uid: "u1", session: { issuedAt: null } }, { created_at: created })).toBe(false);
  });

  it("行の作成より 10 分以上前の発行は無効 (退会して再登録した)。10 分以内のずれは許す", () => {
    expect(isRevokedSession({ uid: "u1", session: { issuedAt: createdSec - 601 } }, { created_at: created })).toBe(true);
    expect(isRevokedSession({ uid: "u1", session: { issuedAt: createdSec - 599 } }, { created_at: created })).toBe(false);
    expect(isRevokedSession({ uid: "u1", session: { issuedAt: createdSec + 10 } }, { created_at: created })).toBe(false);
  });
});

function appleClaims(overrides: Record<string, unknown> = {}) {
  const iat = nowSec();
  return { iss: "https://appleid.apple.com", aud: BUNDLE_ID, sub: "a1", iat, exp: iat + 600, ...overrides };
}

function googleClaims(overrides: Record<string, unknown> = {}) {
  const iat = nowSec();
  return { iss: "https://accounts.google.com", aud: GOOGLE_CLIENT_ID, sub: "g1", iat, exp: iat + 600, ...overrides };
}

describe("verifyAppleToken", () => {
  it("正しいトークンは sub と email を返す", async () => {
    expect(await verifyAppleToken(await apple.sign(appleClaims({ email: "a@example.com" })), BUNDLE_ID))
      .toEqual({ uid: "a1", email: "a@example.com" });
  });

  it.each<[string, () => Promise<string>]>([
    ["iss 違い", () => apple.sign(appleClaims({ iss: "https://accounts.google.com" }))],
    ["aud 違い", () => apple.sign(appleClaims({ aud: "com.example.other" }))],
    ["期限切れ", () => apple.sign(appleClaims({ exp: nowSec() - 1 }))],
    ["iat が未来", () => apple.sign(appleClaims({ iat: nowSec() + 120 }))],
    ["alg が RS256 でない", () => apple.sign(appleClaims(), { alg: "HS256" })],
    ["知らない kid", () => apple.sign(appleClaims(), { kid: "unknown-kid" })],
    ["別の鍵で署名", () => google.sign(appleClaims(), { kid: "apple-kid-v" })],
  ])("%s は null", async (_label, make) => {
    expect(await verifyAppleToken(await make(), BUNDLE_ID)).toBeNull();
  });
});

describe("verifyGoogleToken", () => {
  it("uid に google: を付ける。iss は scheme 無しの形も受ける", async () => {
    const token = await google.sign(googleClaims({ iss: "accounts.google.com", name: "N", picture: "https://p" }));
    expect(await verifyGoogleToken(token, GOOGLE_CLIENT_ID))
      .toEqual({ uid: "google:g1", email: undefined, name: "N", picture: "https://p" });
  });

  it.each<[string, () => Promise<string>]>([
    ["iss 違い", () => google.sign(googleClaims({ iss: "https://appleid.apple.com" }))],
    ["aud 違い (Android のクライアント ID)", () => google.sign(googleClaims({ aud: "android-client" }))],
    ["sub が文字列でない", () => google.sign(googleClaims({ sub: 123 }))],
    ["sub が空", () => google.sign(googleClaims({ sub: "" }))],
    ["exp 欠落", () => google.sign(googleClaims({ exp: undefined }))],
    ["iat 欠落", () => google.sign(googleClaims({ iat: undefined }))],
  ])("%s は null", async (_label, make) => {
    expect(await verifyGoogleToken(await make(), GOOGLE_CLIENT_ID)).toBeNull();
  });
});
