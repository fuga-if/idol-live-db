// PUT /songs/:id/parts — パート分け。本文を変えず、応答に本文を返さず、全置換する。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { validatePartsBody } from "../src/routes/parts";
import { applyStructureOp } from "../src/lyrics_structure";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";

const UID = "001094.parts";
const LINES = [
  { id: "ll_1", ord: 0, kind: "lyric", text: "テスト 一", section: null, start_ms: 1000, singers: ["old"] },
  { id: "ll_2", ord: 1, kind: "lyric", text: "テスト二", section: null, start_ms: null },
];

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(UID);
  await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json) VALUES ('s1', 'src', 'published', ?)", JSON.stringify(LINES));
});
afterEach(() => vi.restoreAllMocks());

describe("PUT /songs/:id/parts", () => {
  it("行ごとの歌唱者を全置換で書き、歌詞の応答に singers で載る", async () => {
    const r = await callJson("PUT", "/songs/s1/parts", {
      headers: await bearer(UID), body: { lines: [{ id: "ll_2", singers: ["765as_天海春香", "765as_天海春香", "765as_如月千早"] }] },
    });
    expect(r.status).toBe(200);
    expect(JSON.stringify(r.body)).not.toContain("テスト");
    const saved = JSON.parse((await row<{ lines_json: string }>("SELECT lines_json FROM song_lyrics WHERE song_id = 's1'"))!.lines_json);
    expect(saved[0]).not.toHaveProperty("singers");
    expect(saved[1].singers).toEqual(["765as_天海春香", "765as_如月千早"]);
    expect(await row<{ part_lines: number }>("SELECT part_lines FROM song_part_stats WHERE song_id = 's1'")).toEqual({ part_lines: 1 });
    expect(saved[0].start_ms).toBe(1000);
    const lyrics = await callJson("GET", "/songs/s1/lyrics", { headers: await bearer(UID) });
    expect(lyrics.body.lines.map((l: { singers: string[] }) => l.singers)).toEqual([[], ["765as_天海春香", "765as_如月千早"]]);
  });

  it("知らない行・不正な id は 400、未ログインは 401", async () => {
    expect(validatePartsBody({ lines: [{ id: "x", singers: [] }] }, new Map([["a", 4]])).ok).toBe(false);
    expect(validatePartsBody({ lines: [{ id: "a", singers: [1] }] }, new Map([["a", 4]])).ok).toBe(false);
    // 区切りは行の中で昇順
    const len = new Map([["a", 4]]);
    expect(validatePartsBody({ lines: [{ id: "a", singers: [], breaks: [{ at: 4, singers: [] }] }] }, len).ok).toBe(false);
    expect(validatePartsBody({ lines: [{ id: "a", singers: [], breaks: [{ at: 2, singers: [] }, { at: 2, singers: [] }] }] }, len).ok).toBe(false);
    expect(validatePartsBody({ lines: [{ id: "a", singers: ["x"], breaks: [{ at: 2, singers: ["y"] }] }] }, len).ok).toBe(true);
    expect((await callJson("PUT", "/songs/s1/parts", { body: { lines: [] } })).status).toBe(401);
  });

  it("行を切り離すと、後ろの行も同じ歌唱者を引き継ぐ", () => {
    const r = applyStructureOp(LINES as any, { op: "split", lineId: "ll_1", at: 4 }, () => "ll_new");
    expect(r.ok && r.lines[1]).toMatchObject({ id: "ll_new", text: "一", singers: ["old"] });
  });

  it("行の途中の区切りを保存し、送らなければ残す", async () => {
    const r = await callJson("PUT", "/songs/s1/parts", {
      headers: await bearer(UID), body: { lines: [{ id: "ll_2", singers: ["a"], breaks: [{ at: 2, singers: ["b", "c"] }] }] },
    });
    expect(r.status).toBe(200);
    expect(JSON.stringify(r.body)).not.toContain("テスト");
    const lyrics = await callJson("GET", "/songs/s1/lyrics", { headers: await bearer(UID) });
    expect(lyrics.body.lines[1].partBreaks).toEqual([{ at: 2, singers: ["b", "c"] }]);
    // breaks を送らない古いアプリは区切りを消さない
    await callJson("PUT", "/songs/s1/parts", { headers: await bearer(UID), body: { lines: [{ id: "ll_2", singers: ["z"] }] } });
    const saved = JSON.parse((await row<{ lines_json: string }>("SELECT lines_json FROM song_lyrics WHERE song_id = 's1'"))!.lines_json);
    expect(saved[1]).toMatchObject({ singers: ["z"], partBreaks: [{ at: 2, singers: ["b", "c"] }] });
  });

  it("行をくっつける・切り離すと区切りも付いていく", () => {
    const lines = [
      { id: "a", ord: 0, kind: "lyric", text: "あいう", section: null, start_ms: null, singers: ["x"], calls: [] },
      { id: "b", ord: 1, kind: "lyric", text: "えおか", section: null, start_ms: null, singers: ["y"], partBreaks: [{ at: 1, singers: ["z"] }], calls: [] },
    ];
    const merged = applyStructureOp(lines as any, { op: "merge", lineId: "a", joiner: "" }, () => "n");
    expect(merged.ok && merged.lines[0]).toMatchObject({ text: "あいうえおか", singers: ["x"],
      partBreaks: [{ at: 3, singers: ["y"] }, { at: 4, singers: ["z"] }] });
    const split = applyStructureOp((merged as any).lines, { op: "split", lineId: "a", at: 4 }, () => "n");
    expect(split.ok && split.lines[0]).toMatchObject({ text: "あいうえ", partBreaks: [{ at: 3, singers: ["y"] }] });
    expect(split.ok && split.lines[1]).toMatchObject({ text: "おか", singers: ["z"] });
    expect(split.ok && split.lines[1].partBreaks).toBeUndefined();
  });
});
