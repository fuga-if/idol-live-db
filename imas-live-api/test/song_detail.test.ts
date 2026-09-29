// GET /songs/:id/detail (曲詳細の束ね) の歌詞と admin 判定。ローカル D1 で通す。
//   - 公開済みの歌詞は、ログインしていれば誰にでも同梱する。admin かどうかは見ない。
//   - 未公開 (draft) の歌詞は admin にだけ同梱する。admin の判定 (users の読み取り) は
//     行が draft のときだけ行う。

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser, meterD1 } from "./support/d1";

const UID = "001094.reader";
const ADMIN = "001094.admin";
const LINES = JSON.stringify([{ id: "ll_1", ord: 0, kind: "lyric", text: "てすと", section: null }]);

beforeEach(() => void vi.spyOn(console, "log").mockImplementation(() => {}));
afterEach(() => vi.restoreAllMocks());

async function seedLyrics(status: "published" | "draft") {
  await exec("INSERT INTO song_lyrics (song_id, status, lines_json) VALUES ('s1', ?, ?)", status, LINES);
}

describe("GET /songs/:id/detail の歌詞", () => {
  it("公開済みはログインしていれば同梱し、no-store", async () => {
    await seedLyrics("published");
    await insertUser(UID);
    const res = await callJson("GET", "/songs/s1/detail", { headers: await bearer(UID) });
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe("no-store");
    expect(res.body.lyrics).toMatchObject({ songId: "s1", status: "published" });
    expect(Object.keys(res.body).sort()).toEqual(["lyrics", "penlight", "similar", "songId", "tags"]);
  });

  it("未公開は admin にだけ同梱する (env の許可リスト / users.is_admin)", async () => {
    await seedLyrics("draft");
    await insertUser(UID);
    await insertUser(ADMIN, { isAdmin: true });
    expect((await callJson("GET", "/songs/s1/detail", { headers: await bearer(UID) })).body.lyrics).toBeNull();
    expect((await callJson("GET", "/songs/s1/detail?a=1", { headers: await bearer(ADMIN) })).body.lyrics)
      .toMatchObject({ status: "draft" });
    const byEnv = await callJson("GET", "/songs/s1/detail?a=2", {
      headers: await bearer(UID), env: makeEnv({ ADMIN_USER_IDS: UID }),
    });
    expect(byEnv.body.lyrics).toMatchObject({ status: "draft" });
  });

  it("公開済みの歌詞・歌詞の無い曲では、admin の判定のために users を読まない", async () => {
    await seedLyrics("published");
    await insertUser(UID);
    const m = meterD1();
    const env = makeEnv({ DB: m.db });
    await callJson("GET", "/songs/s1/detail", { headers: await bearer(UID), env });
    expect(m.usage.log.filter((l) => /FROM users/.test(l.sql))).toEqual([]);
    m.reset();
    await callJson("GET", "/songs/none/detail", { headers: await bearer(UID), env });
    expect(m.usage.log.filter((l) => /FROM users/.test(l.sql))).toEqual([]);
  });
});
