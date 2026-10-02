// Android 版は NexTone 管理曲だけ歌詞を返す (lyricsAllowedForClient)。/music-token は鍵が無ければ 503。
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
  it("Android は JASRAC 曲を 451 で断り、NexTone 曲は返す", async () => {
    const android = { ...(await bearer(UID)), "X-Client-Platform": "android" };
    expect((await callJson("GET", "/songs/jas/lyrics", { headers: android })).status).toBe(451);
    expect((await callJson("GET", "/songs/nex/lyrics", { headers: android })).status).toBe(200);
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
