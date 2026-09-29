// 書き込みの経路で users の行を作るとき、メールアドレスを表示名として保存しない。
// メールが Bearer に載るのは Apple の ID トークンをそのまま使う互換の経路だけなので、それで試す。

import { fetchMock } from "cloudflare:test";
import { beforeAll, describe, expect, it } from "vitest";
import { callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";
import { APPLE_JWKS_PATH, APPLE_ORIGIN, FakeIdProvider, nowSec } from "./support/jwt";

const SUB = "001094.newcomer";
const EMAIL = "newcomer@example.com";

let apple: FakeIdProvider;

beforeAll(async () => {
  apple = await FakeIdProvider.create("apple-kid");
  fetchMock.get(APPLE_ORIGIN).intercept({ path: APPLE_JWKS_PATH }).reply(200, () => ({ keys: [apple.jwk] })).persist();
});

async function appleBearer(): Promise<Record<string, string>> {
  const iat = nowSec();
  const token = await apple.sign({
    iss: "https://appleid.apple.com", aud: "com.fugaif.ImasLiveDB", sub: SUB, iat, exp: iat + 600, email: EMAIL,
  });
  return { Authorization: `Bearer ${token}` };
}

async function displayName(): Promise<string | undefined> {
  return (await row<{ display_name: string }>("SELECT display_name FROM users WHERE id = ?", SUB))?.display_name;
}

async function seedPoll() {
  await exec(
    "INSERT INTO polls (id, title, target_type, created_by, ends_at) VALUES ('p', 't', 'song', 'u', datetime('now', '+1 day'))"
  );
}

describe("書き込みで作る users の行の表示名", () => {
  it("お題の作成", async () => {
    const res = await callJson("POST", "/polls", { headers: await appleBearer(), body: { title: "t", target_type: "song" } });
    expect(res.status).toBe(201);
    expect(await displayName()).toBe("匿名");
  });

  it("お題への投票", async () => {
    await seedPoll();
    const res = await callJson("POST", "/polls/p/votes", { headers: await appleBearer(), body: { entity_id: "s1" } });
    expect(res.status).toBe(201);
    expect(await displayName()).toBe("匿名");
  });

  it("出演者予想", async () => {
    const res = await callJson("POST", "/shows/sh1/songs/s1/performers", {
      headers: await appleBearer(), body: { idol_id: "i1" },
    });
    expect(res.status).toBe(201);
    expect(await displayName()).toBe("匿名");
  });

  it("セトリのいいね", async () => {
    const res = await callJson("POST", "/shows/sh1/songs/s1/like", { headers: await appleBearer() });
    expect(res.status).toBe(200);
    expect(await displayName()).toBe("匿名");
  });

  it("編集への Good", async () => {
    await insertUser("001094.editor");
    await exec(
      "INSERT INTO edit_batch (id, editor_id, source, op, cloudkit_ok, created_at) VALUES (1, '001094.editor', 'app', 'update', 1, 1)"
    );
    const res = await callJson("POST", "/edits/1/good", { headers: await appleBearer() });
    expect(res.status).toBe(200);
    expect(await displayName()).toBe("匿名");
  });

  it("既にある行の表示名は変えない", async () => {
    await insertUser(SUB, { displayName: "設定した名前" });
    await seedPoll();
    await callJson("POST", "/polls/p/votes", { headers: await appleBearer(), body: { entity_id: "s1" } });
    expect(await displayName()).toBe("設定した名前");
  });
});
