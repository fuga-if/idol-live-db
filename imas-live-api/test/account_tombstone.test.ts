// 退会 (DELETE /users/me) したあとのセッション JWT と、共有データに残った uid (Q-10)。
//   - users の行が無いセッションは、書き込みの経路・/auth/me・/auth/refresh で 401
//     (行を読んでいる所で判定する。読み取りだけの GET は期限まで通る)
//   - 退会したあと同じ人がまた登録しても、それより前に発行したトークンは 401
//   - お題・予想・タグの語彙と履歴に残った uid は "deleted" に置き換わる
//   - Apple の ID トークンをそのまま使う互換の経路は対象外 (行が無ければ今までどおり作る)

import { fetchMock } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser, meterD1, row, rows } from "./support/d1";
import { APPLE_JWKS_PATH, APPLE_ORIGIN, FakeIdProvider, nowSec, sessionPayload, signHs256 } from "./support/jwt";

const UID = "001094.leaver";

async function seedPoll(id = "p1", createdBy = "001094.someone") {
  await exec(
    "INSERT INTO polls (id, title, target_type, created_by, ends_at) VALUES (?, 't', 'song', ?, datetime('now', '+1 day'))",
    id, createdBy
  );
}

async function deleteAccount(headers: Record<string, string>) {
  const res = await callJson("DELETE", "/users/me", { headers });
  expect(res.status).toBe(200);
}

describe("退会したアカウントのセッション JWT", () => {
  it("書き込みの経路・/auth/me・/auth/refresh は 401。users の行は作り直さない", async () => {
    await insertUser(UID);
    await seedPoll();
    const auth = await bearer(UID);
    await deleteAccount(auth);

    const writes: Array<[string, string, unknown]> = [
      ["POST", "/polls", { title: "t", target_type: "song" }],
      ["POST", "/polls/p1/votes", { entity_id: "s1" }],
      ["POST", "/users/me", { display_name: "x" }],
      ["POST", "/shows/sh1/songs/s1/performers", { idol_id: "i1" }],
      ["POST", "/shows/sh1/songs/s1/like", undefined],
      ["POST", "/transfer", { payload: "x" }],
    ];
    for (const [method, path, body] of writes) {
      const res = await callJson(method, path, { headers: auth, body });
      expect(res.status, `${method} ${path}`).toBe(401);
      expect(res.body).toEqual({ error: "Unauthorized" });
    }
    expect((await callJson("GET", "/auth/me", { headers: auth })).status).toBe(401);
    expect((await callJson("POST", "/auth/refresh", { headers: auth })).status).toBe(401);
    expect(await rows("SELECT id FROM users")).toEqual([]);

    // 読み取りだけの GET は、トークンの期限まで通る (行を読まない経路なので、読み足さない)。
    expect((await callJson("GET", "/polls", { headers: auth })).status).toBe(200);
  });

  it("また登録したあとでも、退会より前に発行したトークンは 401。新しいトークンは通る (時計のずれは 10 分まで許す)", async () => {
    await insertUser(UID); // 作り直した行 (created_at は今)
    const old = await signHs256(sessionPayload(UID, { iat: nowSec() - 3600 }));
    const skewed = await signHs256(sessionPayload(UID, { iat: nowSec() - 300 }));
    for (const token of [old]) {
      const auth = { Authorization: `Bearer ${token}` };
      expect((await callJson("GET", "/auth/me", { headers: auth })).status).toBe(401);
      expect((await callJson("POST", "/users/me", { headers: auth, body: { display_name: "x" } })).status).toBe(401);
      expect((await callJson("POST", "/auth/refresh", { headers: auth })).status).toBe(401);
    }
    const ok = { Authorization: `Bearer ${skewed}` };
    expect((await callJson("GET", "/auth/me", { headers: ok })).status).toBe(200);
    expect((await callJson("POST", "/users/me", { headers: ok, body: { display_name: "x" } })).status).toBe(200);
  });

  it("refresh は users の行を 1 回だけ読む (admin の判定もその行で済ませる)", async () => {
    await insertUser(UID, { isAdmin: true });
    const m = meterD1();
    const res = await callJson("POST", "/auth/refresh", { headers: await bearer(UID), env: makeEnv({ DB: m.db }) });
    expect(res.status).toBe(200);
    expect(res.body.isAdmin).toBe(true);
    expect(m.usage.log.filter((l) => /FROM users/.test(l.sql))).toHaveLength(1);
  });
});

describe("Apple の ID トークンの互換の経路", () => {
  let apple: FakeIdProvider;
  beforeAll(async () => {
    apple = await FakeIdProvider.create("apple-kid");
    fetchMock.get(APPLE_ORIGIN).intercept({ path: APPLE_JWKS_PATH }).reply(200, () => ({ keys: [apple.jwk] })).persist();
  });

  it("行が無くても今までどおり書き込め、行を作る", async () => {
    await seedPoll();
    const iat = nowSec();
    const token = await apple.sign({
      iss: "https://appleid.apple.com", aud: "com.fugaif.ImasLiveDB", sub: "001094.apple-direct", iat, exp: iat + 600,
    });
    const res = await callJson("POST", "/polls/p1/votes", { headers: { Authorization: `Bearer ${token}` }, body: { entity_id: "s1" } });
    expect(res.status).toBe(201);
    expect(await row("SELECT id FROM users WHERE id = '001094.apple-direct'")).toEqual({ id: "001094.apple-direct" });
  });
});

describe("退会で共有データに残った uid", () => {
  it("お題・予想・タグの語彙と履歴の uid は deleted に、引き継ぎコードは消す。他人の値はそのまま", async () => {
    await insertUser(UID);
    await seedPoll("mine", UID);
    await seedPoll("theirs", "001094.other");
    await exec("INSERT INTO poll_entries (poll_id, entity_id, vote_count, first_voted_by) VALUES ('theirs', 's1', 1, ?), ('theirs', 's2', 1, 'x')", UID);
    await exec("INSERT INTO setlist_performer_predictions (show_id, song_id, idol_id, vote_count, first_voted_by) VALUES ('sh', 's', 'i', 1, ?)", UID);
    for (const [table, history] of [["tags", "tag_description_history"], ["idol_tag_master", "idol_tag_description_history"], ["unit_tag_master", "unit_tag_description_history"]]) {
      await exec(`INSERT INTO ${table} (id, name, created_by, created_at, updated_by, updated_at) VALUES ('t', 't', 'dev-1', 1, ?, 1)`, UID);
      await exec(`INSERT INTO ${history} (tag_id, description, edited_by, edited_at) VALUES ('t', 'd', ?, 1), ('t', 'e', 'dev-2', 2)`, UID);
    }
    await exec("INSERT INTO transfer_codes (code, user_id, payload, created_at, expires_at) VALUES ('C1', ?, 'p', 'x', '2099-01-01'), ('C2', 'other', 'p', 'x', '2099-01-01')", UID);

    await deleteAccount(await bearer(UID));

    expect(await rows("SELECT id, created_by FROM polls ORDER BY id")).toEqual([
      { id: "mine", created_by: "deleted" }, { id: "theirs", created_by: "001094.other" },
    ]);
    expect(await rows("SELECT entity_id, first_voted_by FROM poll_entries ORDER BY entity_id")).toEqual([
      { entity_id: "s1", first_voted_by: "deleted" }, { entity_id: "s2", first_voted_by: "x" },
    ]);
    expect(await row("SELECT first_voted_by FROM setlist_performer_predictions")).toEqual({ first_voted_by: "deleted" });
    for (const [table, history] of [["tags", "tag_description_history"], ["idol_tag_master", "idol_tag_description_history"], ["unit_tag_master", "unit_tag_description_history"]]) {
      expect(await row(`SELECT created_by, updated_by FROM ${table}`), table).toEqual({ created_by: "dev-1", updated_by: "deleted" });
      expect(await rows(`SELECT edited_by FROM ${history} ORDER BY edited_at`), history)
        .toEqual([{ edited_by: "deleted" }, { edited_by: "dev-2" }]);
    }
    expect(await rows("SELECT code FROM transfer_codes")).toEqual([{ code: "C2" }]);
  });
});
