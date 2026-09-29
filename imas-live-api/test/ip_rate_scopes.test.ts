// IP の分の枠は用途 (歌詞 / 編集フィード / 端末集計の書き込み) ごとに別に数える。
// 会場の NAT で大勢が同じ IP から歌詞を読んでも、同じ IP のお気に入り・タグ・フィードは 429 にしない。
// 曲詳細の束ねに入る歌詞は、単体の GET /songs/:id/lyrics と同じ枠・同じ上限で数える。

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bearer, call, callJson, device } from "./support/worker";
import { exec } from "./support/d1";

const IP = "198.51.100.20";
const LINES = JSON.stringify([{ id: "ll_1", ord: 0, kind: "lyric", text: "てすと", section: null }]);

beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-09-23T10:00:05Z"));
  vi.spyOn(console, "log").mockImplementation(() => {});
});
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

const readLyrics = () => call("GET", "/songs/s1/lyrics", { headers: { "CF-Connecting-IP": IP } });
const favorite = (i: number) =>
  call("POST", "/favorites/toggle", {
    headers: { ...device(`dev-${i}`), "CF-Connecting-IP": IP },
    body: { song_id: `s${i}`, value: true },
  });
const feed = (i: number) => call("GET", `/edits?page=${i + 1}`, { headers: { "CF-Connecting-IP": IP } });

async function detailLyrics(auth: Record<string, string>, n: number) {
  const res = await callJson("GET", `/songs/s1/detail?n=${n}`, { headers: { ...auth, "CF-Connecting-IP": IP } });
  return res.body.lyrics;
}

describe("IP の枠は用途ごとに別", () => {
  it("歌詞を 1 分の上限まで読んでも、同じ IP のお気に入りとフィードは通る", async () => {
    await exec("INSERT INTO song_lyrics (song_id, status, lines_json) VALUES ('s1', 'published', ?)", LINES);
    for (let i = 0; i < 120; i++) expect((await readLyrics()).status).toBe(200);
    expect((await readLyrics()).status).toBe(429);
    expect((await favorite(0)).status).toBe(200);
    expect((await feed(0)).status).toBe(200);
  });

  it("フィードを 1 分の上限まで読んでも、同じ IP の書き込みは通る", async () => {
    for (let i = 0; i < 30; i++) expect((await feed(i)).status).toBe(200);
    expect((await feed(30)).status).toBe(429);
    expect((await favorite(0)).status).toBe(200);
  });
});

describe("曲詳細の束ねの歌詞", () => {
  it("1 分の上限は単体の GET と同じ 120 で、同じ枠を数える", async () => {
    await exec("INSERT INTO song_lyrics (song_id, status, lines_json) VALUES ('s1', 'published', ?)", LINES);
    const auth = await bearer("001094.reader");
    for (let i = 0; i < 60; i++) expect(await detailLyrics(auth, i)).not.toBeNull();
    for (let i = 0; i < 60; i++) expect((await readLyrics()).status).toBe(200);
    // 束ね 60 + 単体 60 で上限。以降は束ねの歌詞が null (応答全体は 200)、単体は 429。
    expect(await detailLyrics(auth, 60)).toBeNull();
    expect((await readLyrics()).status).toBe(429);
  });
});
