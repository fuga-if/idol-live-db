// 認証の特性テスト: セッション JWT の発行・検証・refresh、/auth/me、表示名の変更、退会、
// App Attest のゲート。Apple / Google の JWKS は fetchMock で返す (外部には出ない)。

import { fetchMock } from "cloudflare:test";
import { beforeAll, describe, expect, it, vi } from "vitest";
import { mintAppToken } from "../src/appattest";
import { signSessionToken } from "../src/auth";
import { bearer, call, callJson, makeEnv, TEST_IP, TEST_SECRET } from "./support/worker";
import { exec, insertUser, meterD1, row, rows } from "./support/d1";
import {
  APPLE_JWKS_PATH, APPLE_ORIGIN, decodeHeader, decodePayload, FakeIdProvider,
  GOOGLE_JWKS_PATH, GOOGLE_ORIGIN, nowSec, sessionPayload, signHs256,
} from "./support/jwt";

const BUNDLE_ID = "com.fugaif.ImasLiveDB";
const GOOGLE_CLIENT_ID = makeEnv().GOOGLE_WEB_CLIENT_ID!;
const YEAR = 60 * 60 * 24 * 365;
const TODAY = () => new Date().toISOString().slice(0, 10);

let apple: FakeIdProvider;
let google: FakeIdProvider;

beforeAll(async () => {
  apple = await FakeIdProvider.create("apple-kid");
  google = await FakeIdProvider.create("google-kid");
  fetchMock.get(APPLE_ORIGIN).intercept({ path: APPLE_JWKS_PATH }).reply(200, () => ({ keys: [apple.jwk] })).persist();
  fetchMock.get(GOOGLE_ORIGIN).intercept({ path: GOOGLE_JWKS_PATH }).reply(200, () => ({ keys: [google.jwk] })).persist();
});

function appleToken(sub: string, overrides: Record<string, unknown> = {}) {
  const iat = nowSec();
  return apple.sign({ iss: "https://appleid.apple.com", aud: BUNDLE_ID, sub, iat, exp: iat + 600, email: `${sub}@example.com`, ...overrides });
}

function googleToken(sub: string, overrides: Record<string, unknown> = {}) {
  const iat = nowSec();
  return google.sign({
    iss: "https://accounts.google.com", aud: GOOGLE_CLIENT_ID, sub, iat, exp: iat + 600,
    email: "g@example.com", name: "Google Name", picture: "https://example.com/p.png", ...overrides,
  });
}

describe("セッション JWT の形", () => {
  it("HS256 / iss imas-live-db / aud imas-live-db-ios / 有効 1 年", async () => {
    const token = await signSessionToken("uid-1", TEST_SECRET);
    expect(decodeHeader(token)).toEqual({ alg: "HS256", typ: "JWT" });
    const payload = decodePayload(token);
    expect(payload).toMatchObject({ iss: "imas-live-db", aud: "imas-live-db-ios", sub: "uid-1" });
    expect((payload.exp as number) - (payload.iat as number)).toBe(YEAR);
  });

  it("32 文字未満の secret では発行しない", async () => {
    await expect(signSessionToken("uid-1", "short")).rejects.toThrow();
  });
});

describe("POST /auth/login", () => {
  it("secret 未設定は 500", async () => {
    const res = await callJson("POST", "/auth/login", { body: {}, env: makeEnv({ SESSION_JWT_SECRET: undefined }) });
    expect(res.status).toBe(500);
    expect(res.body).toEqual({ error: "SESSION_JWT_SECRET not configured" });
  });

  it("トークンが無ければ 400、検証に通らなければ 401", async () => {
    expect((await callJson("POST", "/auth/login", { body: {} })).body)
      .toEqual({ error: "identityToken or googleIdToken required" });
    const bad = await callJson("POST", "/auth/login", { body: { identity_token: "not.a.jwt" } });
    expect(bad.status).toBe(401);
    expect(bad.body).toEqual({ error: "invalid identityToken" });
    const wrongAud = await callJson("POST", "/auth/login", {
      body: { identity_token: await appleToken("apple-1", { aud: "other.app" }) },
    });
    expect(wrongAud.status).toBe(401);
  });

  it("Apple: セッション JWT と表示名を返し、users 行を作る (snake_case / camelCase どちらも受ける)", async () => {
    const res = await callJson("POST", "/auth/login", {
      body: { identity_token: await appleToken("apple-1"), display_name: "りん" },
    });
    expect(res.status).toBe(200);
    expect(Object.keys(res.body).sort()).toEqual(["displayName", "email", "expiresIn", "isAdmin", "sessionToken", "uid"]);
    expect(res.body).toMatchObject({
      uid: "apple-1", email: "apple-1@example.com", isAdmin: false, displayName: "りん", expiresIn: YEAR,
    });
    expect(decodePayload(res.body.sessionToken)).toMatchObject({ sub: "apple-1", iss: "imas-live-db" });

    // 2 回目以降のログインは表示名を上書きしない (Apple は fullName を初回しか返さない)。
    const again = await callJson("POST", "/auth/login", {
      body: { identityToken: await appleToken("apple-1"), displayName: "別名" },
    });
    expect(again.body.displayName).toBe("りん");
    expect(await row("SELECT display_name FROM users WHERE id = 'apple-1'")).toEqual({ display_name: "りん" });
  });

  it("Google: uid に google: を前置し、表示名とアバターはトークンのものを使う", async () => {
    const res = await callJson("POST", "/auth/login", {
      body: { google_id_token: await googleToken("12345"), display_name: "無視される" },
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ uid: "google:12345", displayName: "Google Name", email: "g@example.com" });
    expect(await row("SELECT avatar_url FROM users WHERE id = 'google:12345'"))
      .toEqual({ avatar_url: "https://example.com/p.png" });

    const noClient = await callJson("POST", "/auth/login", {
      body: { googleIdToken: await googleToken("12345") },
      env: makeEnv({ GOOGLE_WEB_CLIENT_ID: undefined }),
    });
    expect(noClient.status).toBe(500);
    expect(noClient.body).toEqual({ error: "GOOGLE_WEB_CLIENT_ID not configured" });
  });

  it("admin は isAdmin: true", async () => {
    const res = await callJson("POST", "/auth/login", {
      body: { identity_token: await appleToken("apple-admin") },
      env: makeEnv({ ADMIN_USER_IDS: "someone, apple-admin" }),
    });
    expect(res.body.isAdmin).toBe(true);
  });

  it("users の行は upsert のあと 1 回だけ読む (表示名と admin の判定を同じ行で済ませる)", async () => {
    await insertUser("apple-1", { displayName: "りん", isAdmin: true });
    const m = meterD1();
    const res = await callJson("POST", "/auth/login", {
      body: { identity_token: await appleToken("apple-1") },
      env: makeEnv({ DB: m.db }),
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ uid: "apple-1", displayName: "りん", isAdmin: true });
    expect(m.usage.log.filter((l) => /^SELECT .*FROM users/.test(l.sql))).toHaveLength(1);
  });

  it("IP ごとに 1 日 500 回まで。超えると 429 と使用量", async () => {
    await exec(
      "INSERT INTO rate_limits (user_id, date, action, count) VALUES (?, ?, 'auth_login', 500)",
      `ip:${TEST_IP}`, TODAY()
    );
    const res = await callJson("POST", "/auth/login", { body: {} });
    expect(res.status).toBe(429);
    expect(res.body).toMatchObject({ error: "rate_limit_exceeded", limit: 500, used: 501 });
    expect(res.res.headers.get("Retry-After")).not.toBeNull();
  });
});

describe("POST /auth/refresh", () => {
  const UID = "001094.refresh";

  it("自前セッション JWT を 1 年の新しいトークンに替える", async () => {
    await insertUser(UID);
    const res = await callJson("POST", "/auth/refresh", { headers: await bearer(UID) });
    expect(res.status).toBe(200);
    expect(Object.keys(res.body).sort()).toEqual(["expiresIn", "isAdmin", "sessionToken", "uid"]);
    expect(res.body).toMatchObject({ uid: UID, isAdmin: false, expiresIn: YEAR });
  });

  it("期限切れでも 90 日以内なら再発行、それより古いと 401", async () => {
    await insertUser(UID);
    // 1 年前に発行したトークンなので、アカウントはそれより前からある。
    await exec("UPDATE users SET created_at = datetime('now', '-2 years') WHERE id = ?", UID);
    const within = await signHs256(sessionPayload(UID, { iat: nowSec() - YEAR, exp: nowSec() - 89 * 86400 }));
    expect((await callJson("POST", "/auth/refresh", { headers: { Authorization: `Bearer ${within}` } })).status)
      .toBe(200);
    const beyond = await signHs256(sessionPayload(UID, { iat: nowSec() - YEAR, exp: nowSec() - 91 * 86400 }));
    expect((await callJson("POST", "/auth/refresh", { headers: { Authorization: `Bearer ${beyond}` } })).status)
      .toBe(401);
  });

  it("Bearer 無し・Apple のトークン・署名違い・aud 違いは 401", async () => {
    await insertUser(UID);
    const cases = [
      undefined,
      `Bearer ${await appleToken(UID)}`,
      `Bearer ${await signHs256(sessionPayload(UID), "another-secret-that-is-long-enough!!")}`,
      `Bearer ${await signHs256(sessionPayload(UID, { aud: "other" }))}`,
    ];
    for (const auth of cases) {
      const res = await callJson("POST", "/auth/refresh", { headers: auth ? { Authorization: auth } : {} });
      expect(res.status).toBe(401);
      expect(res.body).toEqual({ error: "Unauthorized" });
    }
  });

  it("IP ごとに 1 日 500 回まで", async () => {
    await exec(
      "INSERT INTO rate_limits (user_id, date, action, count) VALUES (?, ?, 'auth_refresh', 500)",
      `ip:${TEST_IP}`, TODAY()
    );
    const res = await callJson("POST", "/auth/refresh", { headers: await bearer(UID) });
    expect(res.status).toBe(429);
    expect(res.body).toMatchObject({ error: "rate_limit_exceeded", limit: 500 });
  });
});

describe("GET /auth/me とトークンの検証", () => {
  const UID = "001094.me";

  it("プロフィールと貢献の 2 指標を返す", async () => {
    await insertUser(UID, { displayName: "わたし" });
    await exec("UPDATE users SET avatar_url = 'https://example.com/a.png', contribution_count = 2 WHERE id = ?", UID);
    await insertUser("001094.fan");
    await exec(
      `INSERT INTO edit_batch (id, editor_id, source, op, cloudkit_ok, created_at) VALUES
         (1, ?, 'app', 'update', 1, 1), (2, ?, 'revert', 'revert', 1, 2)`,
      UID, UID
    );
    await exec("INSERT INTO edit_good (batch_id, user_id, created_at) VALUES (1, '001094.fan', 1), (2, '001094.fan', 2)");

    const res = await callJson("GET", "/auth/me", { headers: await bearer(UID) });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      uid: UID, displayName: "わたし", avatarUrl: "https://example.com/a.png",
      isAdmin: false, isBanned: false, editCount: 2, goodsReceived: 1,
    });
  });

  it("admin は env の許可リストか users.is_admin", async () => {
    await insertUser(UID);
    const byEnv = await callJson("GET", "/auth/me", { headers: await bearer(UID), env: makeEnv({ ADMIN_USER_IDS: UID }) });
    expect(byEnv.body.isAdmin).toBe(true);
    await exec("UPDATE users SET is_admin = 1 WHERE id = ?", UID);
    expect((await callJson("GET", "/auth/me", { headers: await bearer(UID) })).body.isAdmin).toBe(true);
  });

  it("users の行は 1 回だけ読む (admin の判定もその行と env の許可リストで済ませる)", async () => {
    await insertUser(UID);
    await exec("UPDATE users SET is_admin = 1 WHERE id = ?", UID);
    const m = meterD1();
    const res = await callJson("GET", "/auth/me", { headers: await bearer(UID), env: makeEnv({ DB: m.db }) });
    expect(res.body.isAdmin).toBe(true);
    expect(m.usage.log.filter((l) => /FROM users/.test(l.sql))).toHaveLength(1);
  });

  it("未ログイン・期限切れ・aud 無し・alg 違い・未来の iat は 401", async () => {
    await insertUser(UID);
    const tokens = [
      await signHs256(sessionPayload(UID, { exp: nowSec() - 1 })),
      await signHs256(sessionPayload(UID, { aud: undefined })),
      await signHs256(sessionPayload(UID), TEST_SECRET, { alg: "none", typ: "JWT" }),
      await signHs256(sessionPayload(UID, { iat: nowSec() + 3600 })),
    ];
    expect((await callJson("GET", "/auth/me")).status).toBe(401);
    for (const token of tokens) {
      const res = await callJson("GET", "/auth/me", { headers: { Authorization: `Bearer ${token}` } });
      expect(res.status).toBe(401);
    }
  });

  it("Apple の ID トークンをそのまま Bearer に使える (移行期間の互換)", async () => {
    await insertUser("apple-direct");
    const res = await callJson("GET", "/auth/me", { headers: { Authorization: `Bearer ${await appleToken("apple-direct")}` } });
    expect(res.status).toBe(200);
    expect(res.body.uid).toBe("apple-direct");
  });
});

describe("POST /users/me (表示名の変更)", () => {
  const UID = "001094.rename";

  it("未ログインは 401。本文を検証する (長さはコードポイントで 40)", async () => {
    expect((await callJson("POST", "/users/me", { body: { display_name: "x" } })).status).toBe(401);
    await insertUser(UID);
    const cases: Array<[unknown, string]> = [
      [{}, "display_name is required"],
      [{ display_name: 1 }, "display_name is required"],
      [{ display_name: "   " }, "display_name must not be empty"],
      [{ display_name: "あ".repeat(41) }, "display_name too long (max 40)"],
    ];
    for (const [body, message] of cases) {
      const res = await callJson("POST", "/users/me", { headers: await bearer(UID), body });
      expect(res.status).toBe(400);
      expect(res.body).toEqual({ error: message });
    }
    const emoji = await callJson("POST", "/users/me", { headers: await bearer(UID), body: { display_name: "🎤".repeat(40) } });
    expect(emoji.status).toBe(200);
  });

  it("変更後の表示名を返す。BAN は 403、行の無いユーザー (退会済みのセッション) は 401、1 日 3 回まで", async () => {
    await insertUser(UID);
    const res = await callJson("POST", "/users/me", { headers: await bearer(UID), body: { display_name: " 新しい名前 " } });
    expect(res.body).toEqual({ displayName: "新しい名前" });
    expect(await row("SELECT display_name FROM users WHERE id = ?", UID)).toEqual({ display_name: "新しい名前" });

    await callJson("POST", "/users/me", { headers: await bearer(UID), body: { display_name: "2" } });
    await callJson("POST", "/users/me", { headers: await bearer(UID), body: { display_name: "3" } });
    const limited = await callJson("POST", "/users/me", { headers: await bearer(UID), body: { display_name: "4" } });
    expect(limited.status).toBe(429);
    expect(limited.body).toMatchObject({ error: "rate_limit_exceeded", limit: 3, used: 4 });

    await insertUser("001094.banned", { isBanned: true });
    expect((await callJson("POST", "/users/me", {
      headers: await bearer("001094.banned"), body: { display_name: "x" },
    })).status).toBe(403);

    // 行の無いセッションは退会済みとして 401 (Q-10。以前は UPDATE が 0 件で 404)。
    const ghost = await callJson("POST", "/users/me", { headers: await bearer("001094.ghost"), body: { display_name: "x" } });
    expect(ghost.status).toBe(401);
    expect(ghost.body).toEqual({ error: "Unauthorized" });
  });
});

describe("DELETE /users/me (退会)", () => {
  const UID = "001094.leaving";
  const OTHER = "001094.staying";

  it("未ログインは 401", async () => {
    expect((await callJson("DELETE", "/users/me")).status).toBe(401);
  });

  it("本人に紐づく行を消し、他人の行から本人への参照を外す。共有の集計は残す", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    await exec("INSERT INTO rate_limits (user_id, date, action, count) VALUES (?, '2026-01-01', 'edit', 1)", UID);
    await exec("INSERT INTO setlist_performer_prediction_votes (show_id, song_id, idol_id, user_id) VALUES ('sh', 's', 'i', ?)", UID);
    await exec("INSERT INTO poll_votes (poll_id, entity_id, user_id) VALUES ('p', 's', ?)", UID);
    await exec("INSERT INTO poll_entries (poll_id, entity_id, vote_count) VALUES ('p', 's', 1)");
    await exec("INSERT INTO setlist_song_likes (show_id, song_id, user_id) VALUES ('sh', 's', ?)", UID);
    await exec(
      `INSERT INTO edit_batch (id, editor_id, source, op, cloudkit_ok, created_at, reverted_by) VALUES
         (1, ?, 'app', 'update', 1, 1, NULL),
         (2, ?, 'revert', 'revert', 1, 2, NULL),
         (3, ?, 'app', 'update', 1, 3, ?)`,
      UID, OTHER, OTHER, UID
    );
    await exec("UPDATE edit_batch SET reverts_batch_id = 1 WHERE id = 2");
    await exec(
      `INSERT INTO edit_history (batch_id, record_type, record_name, op, modified_at, created_at)
       VALUES (1, 'Song', 's', 'update', 1, 1), (3, 'Song', 's', 'update', 3, 3)`
    );
    await exec("INSERT INTO edit_good (batch_id, user_id, created_at) VALUES (3, ?, 1), (1, ?, 1)", UID, OTHER);
    await exec("INSERT INTO call_edit_history (song_id, user_id, call_lines_before, call_lines_after, call_count_before, call_count_after) VALUES ('s', ?, 0, 1, 0, 1)", UID);
    await exec("INSERT INTO song_call_stats (song_id, call_lines, call_count, updated_by_uid) VALUES ('s', 1, 1, ?)", UID);

    const res = await callJson("DELETE", "/users/me", { headers: await bearer(UID) });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ deleted: true });

    for (const table of ["rate_limits", "setlist_performer_prediction_votes", "poll_votes", "setlist_song_likes", "call_edit_history"]) {
      expect(await rows(`SELECT * FROM ${table}`), table).toEqual([]);
    }
    expect(await rows("SELECT id FROM users")).toEqual([{ id: OTHER }]);
    expect(await rows("SELECT id, reverts_batch_id, reverted_by FROM edit_batch ORDER BY id")).toEqual([
      { id: 2, reverts_batch_id: null, reverted_by: null },
      { id: 3, reverts_batch_id: null, reverted_by: null },
    ]);
    expect(await rows("SELECT batch_id FROM edit_history")).toEqual([{ batch_id: 3 }]);
    expect(await rows("SELECT * FROM edit_good")).toEqual([]);
    expect(await row("SELECT updated_by_uid FROM song_call_stats")).toEqual({ updated_by_uid: null });
    // お題の集計は共有データなので残る。
    expect(await row("SELECT vote_count FROM poll_entries")).toEqual({ vote_count: 1 });
  });
});

describe("App Attest のゲート (コミュニティ集計の読み取り)", () => {
  it("enforce: アプリ証明トークンもログインも無ければ 401", async () => {
    const env = makeEnv({ APP_ATTEST_MODE: "enforce" });
    const res = await callJson("GET", "/favorites/ranking", { env });
    expect(res.status).toBe(401);
    expect(res.body).toEqual({ error: "app attestation required" });

    const withApp = await call("GET", "/favorites/ranking?app=1", {
      env, headers: { "X-App-Token": await mintAppToken("key-1", TEST_SECRET) },
    });
    expect(withApp.status).toBe(200);
    const withLogin = await call("GET", "/favorites/ranking?login=1", { env, headers: await bearer("001094.x") });
    expect(withLogin.status).toBe(200);
  });

  it("monitor (既定): 通してログだけ出す。集計以外の読み取りはゲートしない", async () => {
    const logs: string[] = [];
    vi.spyOn(console, "log").mockImplementation((msg: unknown) => void logs.push(String(msg)));
    const env = makeEnv({ APP_ATTEST_MODE: undefined });
    expect((await call("GET", "/favorites/ranking", { env })).status).toBe(200);
    expect(logs).toContain("[appattest:monitor] ungated community read /favorites/ranking");
    const enforce = makeEnv({ APP_ATTEST_MODE: "enforce" });
    expect((await call("GET", "/", { env: enforce })).status).toBe(200);
    vi.restoreAllMocks();
  });
});
