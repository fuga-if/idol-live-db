// 歌詞行の「ここ好き」: 付け外しで人数が数え直され、歌詞の応答の likeCount に載ること。
// 退会で本人の分が消えて人数が戻ること。実際の D1 (miniflare) で SQL ごと確かめる。

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";

const A = "001094.like-a";
const B = "001094.like-b";
const LINES = [
  { id: "ll_1", ord: 0, kind: "lyric", text: "テスト一", section: null, start_ms: 1000, clap: null, calls: [] },
  { id: "ll_2", ord: 1, kind: "lyric", text: "テスト二", section: null, start_ms: 5000, clap: null, calls: [] },
];

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(A);
  await insertUser(B);
  await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json) VALUES ('s1', 'src', 'published', ?)",
    JSON.stringify(LINES));
});
afterEach(() => vi.restoreAllMocks());

const likes = async () =>
  JSON.parse((await row<{ likes_json: string }>("SELECT likes_json FROM song_lyrics WHERE song_id = 's1'"))!.likes_json);

describe("PUT/DELETE /songs/:id/lyric-likes/:line", () => {
  it("2 人が付けて 1 人が外すと 1、同じ人の二度押しは数えない", async () => {
    let r = await callJson("PUT", "/songs/s1/lyric-likes/ll_1", { headers: await bearer(A) });
    expect(r.status).toBe(200);
    expect(r.body).toEqual({ songId: "s1", lineId: "ll_1", liked: true, likeCount: 1 });
    r = await callJson("PUT", "/songs/s1/lyric-likes/ll_1", { headers: await bearer(A) });
    expect(r.body.likeCount).toBe(1);
    r = await callJson("PUT", "/songs/s1/lyric-likes/ll_1", { headers: await bearer(B) });
    expect(r.body.likeCount).toBe(2);
    r = await callJson("DELETE", "/songs/s1/lyric-likes/ll_1", { headers: await bearer(A) });
    expect(r.body).toMatchObject({ liked: false, likeCount: 1 });
    expect(await likes()).toEqual({ ll_1: 1 });
    expect(JSON.stringify(r.body)).not.toContain("テスト");
  });

  it("歌詞の応答に likeCount が載る", async () => {
    await callJson("PUT", "/songs/s1/lyric-likes/ll_2", { headers: await bearer(A) });
    const r = await callJson("GET", "/songs/s1/lyrics", { headers: await bearer(B) });
    expect(r.status).toBe(200);
    expect(r.body.lines.map((l: { likeCount: number }) => l.likeCount)).toEqual([0, 1]);
  });

  it("未ログインは 401、無い行は 404、記号入りの id は 400", async () => {
    expect((await callJson("PUT", "/songs/s1/lyric-likes/ll_1")).status).toBe(401);
    expect((await callJson("PUT", "/songs/s1/lyric-likes/ll_9", { headers: await bearer(A) })).status).toBe(404);
    expect((await callJson("PUT", "/songs/s1/lyric-likes/a%22b", { headers: await bearer(A) })).status).toBe(400);
  });

  it("退会すると本人の分が消えて人数が戻る", async () => {
    await callJson("PUT", "/songs/s1/lyric-likes/ll_1", { headers: await bearer(A) });
    await callJson("PUT", "/songs/s1/lyric-likes/ll_1", { headers: await bearer(B) });
    await callJson("PUT", "/songs/s1/lyric-likes/ll_2", { headers: await bearer(A) });
    const r = await callJson("DELETE", "/users/me", { headers: await bearer(A) });
    expect(r.status).toBe(200);
    expect(await likes()).toEqual({ ll_1: 1 });
    expect(await row("SELECT 1 FROM lyric_line_likes WHERE user_id = ?", A)).toBeNull();
  });
});
