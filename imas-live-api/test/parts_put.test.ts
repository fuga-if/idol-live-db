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
    expect(saved[0].start_ms).toBe(1000);
    const lyrics = await callJson("GET", "/songs/s1/lyrics", { headers: await bearer(UID) });
    expect(lyrics.body.lines.map((l: { singers: string[] }) => l.singers)).toEqual([[], ["765as_天海春香", "765as_如月千早"]]);
  });

  it("知らない行・不正な id は 400、未ログインは 401", async () => {
    expect(validatePartsBody({ lines: [{ id: "x", singers: [] }] }, new Set(["a"])).ok).toBe(false);
    expect(validatePartsBody({ lines: [{ id: "a", singers: [1] }] }, new Set(["a"])).ok).toBe(false);
    expect((await callJson("PUT", "/songs/s1/parts", { body: { lines: [] } })).status).toBe(401);
  });

  it("行を切り離すと、後ろの行も同じ歌唱者を引き継ぐ", () => {
    const r = applyStructureOp(LINES as any, { op: "split", lineId: "ll_1", at: 4 }, () => "ll_new");
    expect(r.ok && r.lines[1]).toMatchObject({ id: "ll_new", text: "一", singers: ["old"] });
  });
});
