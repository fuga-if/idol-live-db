// 1 行だけ直す (PUT /songs/:id/lyric-lines/:line_id) と、本文の突き合わせで注釈を引き継ぐこと。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { matchLines } from "../src/lyrics_line_match";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";

const UID = "001094.lineedit";
const LINES = [
  { id: "ll_a", ord: 0, kind: "lyric", text: "はじまりの歌", section: null, start_ms: 1000, singers: ["x"] },
  { id: "ll_b", ord: 1, kind: "lyric", text: "まちがいの行", section: null, start_ms: 2000, singers: ["y"],
    calls: [{ id: "c1", start: 0, end: 3, anchorText: "まちが", text: "(Fu!)", emphasis: "normal", timing: "over" }] },
  { id: "ll_c", ord: 2, kind: "blank", text: "", section: null, start_ms: null },
  { id: "ll_d", ord: 3, kind: "lyric", text: "おわりの歌", section: null, start_ms: 3000, singers: ["z"] },
];
const saved = async () =>
  JSON.parse((await row<{ lines_json: string }>("SELECT lines_json FROM song_lyrics WHERE song_id = 's1'"))!.lines_json);

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(UID);
  await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json) VALUES ('s1', 'みんなの投稿', 'published', ?)", JSON.stringify(LINES));
});
afterEach(() => vi.restoreAllMocks());

describe("PUT /songs/:id/lyric-lines/:line_id", () => {
  it("1 行だけ直し、行 id・タイミング・歌割・コールをその行に残す。前の版も残す", async () => {
    const r = await callJson("PUT", "/songs/s1/lyric-lines/ll_b", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "まちがえた行 " },
    });
    expect(r.status).toBe(200);
    expect(r.body.published).toBe(true);
    expect(JSON.stringify(r.body)).not.toContain("まちがえた");
    const lines = await saved();
    expect(lines.map((l: { id: string }) => l.id)).toEqual(["ll_a", "ll_b", "ll_c", "ll_d"]);
    expect(lines[1]).toMatchObject({ text: "まちがえた行", start_ms: 2000, singers: ["y"] });
    expect(lines[1].calls[0]).toMatchObject({ id: "c1", text: "(Fu!)" });
    expect(lines[3]).toMatchObject({ start_ms: 3000, singers: ["z"] });
    expect(await row("SELECT COUNT(*) AS n FROM song_lyrics_versions WHERE song_id = 's1'")).toEqual({ n: 1 });
    expect(await row("SELECT user_id, body, line_count FROM lyric_submissions WHERE id = ?", r.body.id))
      .toEqual({ user_id: UID, body: "はじまりの歌\nまちがえた行\n\nおわりの歌", line_count: 4 });
  });

  it("複数行・同意なし・知らない行・空行は受け付けない。未ログインは 401", async () => {
    const put = async (lineId: string, body: unknown, auth = true) =>
      (await callJson("PUT", `/songs/s1/lyric-lines/${lineId}`, { headers: auth ? await bearer(UID) : {}, body })).status;
    expect(await put("ll_b", { agreed_to_guideline: true, text: "一\n二" })).toBe(400);
    expect(await put("ll_b", { agreed_to_guideline: false, text: "一" })).toBe(400);
    expect(await put("ll_x", { agreed_to_guideline: true, text: "一" })).toBe(404);
    expect(await put("ll_c", { agreed_to_guideline: true, text: "一" })).toBe(404);
    expect(await put("ll_b", { agreed_to_guideline: true, text: "一" }, false)).toBe(401);
  });
});

describe("全文の差し替えでの引き継ぎ", () => {
  it("抜けていた行を足しても、後ろの行の注釈はずれない", async () => {
    const r = await callJson("POST", "/songs/s1/lyric-submissions", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "はじまりの歌\n足した行\nまちがいの行\n\nおわりの歌" },
    });
    expect(r.body.published).toBe(true);
    const lines = await saved();
    expect(lines.map((l: { id: string }) => l.id).filter((id: string) => id !== lines[1].id)).toEqual(["ll_a", "ll_b", "ll_c", "ll_d"]);
    expect(lines[1]).toMatchObject({ text: "足した行", start_ms: null });
    expect(lines[1].singers).toBeUndefined();
    expect(lines[2]).toMatchObject({ id: "ll_b", start_ms: 2000, singers: ["y"] });
    expect(lines[4]).toMatchObject({ id: "ll_d", singers: ["z"] });
  });

  it("matchLines: 同じ本文を先に組にし、間は位置順に組にする", () => {
    const L = (t: string) => ({ kind: t ? "lyric" : "blank", text: t });
    expect(matchLines(["a", "b", "", "c"].map(L), ["a", "b2", "", "c"].map(L))).toEqual([0, 1, 2, 3]);
    expect(matchLines(["a", "b", "c"].map(L), ["a", "x", "b", "c"].map(L))).toEqual([0, undefined, 1, 2]);
    expect(matchLines(["a", "b", "c"].map(L), ["a", "c"].map(L))).toEqual([0, 2]);
    expect(matchLines(["a", "", "b"].map(L), ["a", "b"].map(L))).toEqual([0, 2]);
    expect(matchLines([], ["a"].map(L))).toEqual([undefined]);
  });
});
