// PUT /songs/:id/calls の応答は保存後の歌詞全文なので、歌詞の読み取り (lyrics_read) として数える。
// 数えるのはユーザー (admin のセッション JWT を含む) の保存だけで、運用者トークンでの一括投入と、
// 保存しなかった要求 (400 / 404) は数えない。

import { afterEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser } from "./support/d1";

const UID = "001094.caller";
const SONG = "sg_calls";
const PUSH_TOKEN = "push-token-for-test";
const LINES = [
  { id: "ll_1", ord: 0, kind: "lyric", text: "テストのぎょう", section: null, start_ms: null, clap: null, calls: [] },
];
const BODY = { lines: [{ id: "ll_1", clap: "back_beat", calls: [] }] };

async function seed(status = "published") {
  await exec(
    "INSERT INTO song_lyrics (song_id, source, status, lines_json) VALUES (?, 'src', ?, ?)",
    SONG, status, JSON.stringify(LINES)
  );
}

function lyricsReads(): () => unknown[] {
  const spy = vi.spyOn(console, "log").mockImplementation(() => undefined);
  return () =>
    spy.mock.calls
      .map((args) => String(args[0]))
      .filter((line) => line.includes("lyrics_read"))
      .map((line) => JSON.parse(line));
}

afterEach(() => vi.restoreAllMocks());

describe("PUT /songs/:id/calls と lyrics_read", () => {
  it("ユーザーの保存は 1 回数える", async () => {
    await seed();
    await insertUser(UID);
    const reads = lyricsReads();
    const res = await callJson("PUT", `/songs/${SONG}/calls`, { headers: await bearer(UID), body: BODY });
    expect(res.status).toBe(200);
    expect(reads()).toEqual([{ event: "lyrics_read", song_id: SONG }]);
  });

  it("admin のセッション JWT の保存も数える (未公開の歌詞も admin は保存できる)", async () => {
    await seed("draft");
    await insertUser(UID, { isAdmin: true });
    const reads = lyricsReads();
    const res = await callJson("PUT", `/songs/${SONG}/calls`, {
      headers: await bearer(UID), body: BODY, env: makeEnv({ ADMIN_USER_IDS: UID }),
    });
    expect(res.status).toBe(200);
    expect(reads()).toEqual([{ event: "lyrics_read", song_id: SONG }]);
  });

  it("運用者トークンでの保存は数えない", async () => {
    await seed();
    const reads = lyricsReads();
    const res = await callJson("PUT", `/songs/${SONG}/calls`, {
      headers: { "X-Push-Token": PUSH_TOKEN }, body: BODY, env: makeEnv({ LYRICS_PUSH_TOKEN: PUSH_TOKEN }),
    });
    expect(res.status).toBe(200);
    expect(reads()).toEqual([]);
  });

  it("保存しなかった要求 (本文の誤り・歌詞の無い曲) は数えない", async () => {
    await seed();
    await insertUser(UID);
    const reads = lyricsReads();
    const bad = await callJson("PUT", `/songs/${SONG}/calls`, { headers: await bearer(UID), body: { lines: "x" } });
    expect(bad.status).toBe(400);
    const missing = await callJson("PUT", "/songs/none/calls", { headers: await bearer(UID), body: BODY });
    expect(missing.status).toBe(404);
    expect(reads()).toEqual([]);
  });
});
