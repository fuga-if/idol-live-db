// iOS・Android・Web はそれぞれ許諾取得済み。/music-token は鍵が無ければ 503。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser } from "./support/d1";

const UID = "001094.platform";
const LINES = [{ id: "ll_1", ord: 0, kind: "lyric", text: "テスト", section: null, start_ms: null }];

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(UID);
  await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json, rights_org) VALUES ('jas', 'src', 'published', ?, '')", JSON.stringify(LINES));
  await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json, rights_org) VALUES ('nex', 'src', 'published', ?, 'nextone')", JSON.stringify(LINES));
});
afterEach(() => vi.restoreAllMocks());

describe("歌詞の端末ごとの許諾", () => {
  it.each(["android", "web", "ios"])("%s は JASRAC・NexTone の公開曲を no-store で返す", async (platform) => {
    const headers = { ...(await bearer(UID)), "X-Client-Platform": platform };
    for (const id of ["jas", "nex"]) {
      const response = await callJson("GET", `/songs/${id}/lyrics`, { headers });
      expect(response.status).toBe(200);
      expect(response.res.headers.get("Cache-Control")).toContain("no-store");
    }
  });

  it("Web の匿名取得でも公開曲だけを no-store で返す", async () => {
    const response = await callJson("GET", "/songs/jas/lyrics");
    expect(response.status).toBe(200);
    expect(response.res.headers.get("Cache-Control")).toContain("no-store");
    await exec("UPDATE song_lyrics SET status = 'draft' WHERE song_id = 'jas'");
    expect((await callJson("GET", "/songs/jas/lyrics")).status).toBe(404);
  });

  it("名乗りの無い端末 (iOS) は従来どおり全曲", async () => {
    expect((await callJson("GET", "/songs/jas/lyrics", { headers: await bearer(UID) })).status).toBe(200);
  });
});

describe("GET /music-token", () => {
  it("鍵が無ければ 503", async () => {
    expect((await callJson("GET", "/music-token")).status).toBe(503);
  });
});
