// 歌詞の行のくっつけ / 切り離し: 文字が変わらないこと、コール・時刻の付け替え、検索用本文の更新。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { applyStructureOp, parseStructureOp } from "../src/lyrics_structure";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";

const call = (id: string, start: number, end: number, anchorText: string) =>
  ({ id, start, end, anchorText, text: "Hi!", emphasis: "normal" as const, timing: "after" as const });

const LINES = [
  { id: "ll_1", ord: 0, kind: "lyric", text: "夢を 見てた", section: null, start_ms: 1000, clap: "ppph" as const,
    calls: [call("c1", 0, 2, "夢を"), call("c2", 3, 6, "見てた")] },
  { id: "ll_2", ord: 1, kind: "lyric", text: "君と", section: null, start_ms: 5000, clap: null,
    calls: [call("c3", 0, 2, "君と")] },
  { id: "ll_3", ord: 2, kind: "marker", text: "間奏", section: null, start_ms: null },
];
let n = 0;
const newId = () => `ll_new${++n}`;

describe("applyStructureOp", () => {
  it("くっつける: 文字は空白だけ足し、後ろの行のコールをずらして移す", () => {
    const r = applyStructureOp(LINES as any, { op: "merge", lineId: "ll_1", joiner: "　" }, newId);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.lines.map((l) => l.text)).toEqual(["夢を 見てた　君と", "間奏"]);
    expect(r.lines[0]).toMatchObject({ id: "ll_1", start_ms: 1000, clap: "ppph", ord: 0 });
    expect(r.lines[0].calls!.find((c) => c.id === "c3")).toMatchObject({ start: 7, end: 9 });
    expect(r.lines[1].ord).toBe(1);
  });

  it("切り離す: 前後の空白だけ落とし、後ろのコールを新しい行へ。時刻は前の行に残す", () => {
    const r = applyStructureOp(LINES as any, { op: "split", lineId: "ll_1", at: 3 }, newId);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.lines.map((l) => l.text)).toEqual(["夢を", "見てた", "君と", "間奏"]);
    expect(r.lines[0].calls!.map((c) => c.id)).toEqual(["c1"]);
    expect(r.lines[1]).toMatchObject({ start_ms: null, calls: [{ id: "c2", start: 0, end: 3 }] });
    expect(r.lines[1].calls![0]).not.toHaveProperty("stale");
  });

  it("またぐコールは前の行に残して stale を立てる", () => {
    const lines = [{ ...LINES[0], calls: [call("cx", 1, 5, "を 見て")] }];
    const r = applyStructureOp(lines as any, { op: "split", lineId: "ll_1", at: 3 }, newId);
    expect(r.ok && r.lines[0].calls![0]).toMatchObject({ id: "cx", start: 1, end: 2, stale: true });
  });

  it("歌詞でない行・最後の行・行の端では断る", () => {
    expect(applyStructureOp(LINES as any, { op: "merge", lineId: "ll_2", joiner: "" }, newId).ok).toBe(false);
    expect(applyStructureOp(LINES as any, { op: "split", lineId: "ll_1", at: 0 }, newId).ok).toBe(false);
    expect(applyStructureOp(LINES as any, { op: "split", lineId: "ll_3", at: 1 }, newId).ok).toBe(false);
    expect(parseStructureOp({ op: "merge", lineId: "ll_1", joiner: "x" })).toBeTypeOf("string");
    expect(parseStructureOp({ op: "rewrite", lineId: "ll_1" })).toBeTypeOf("string");
  });
});

describe("POST /songs/:id/lyric-structure", () => {
  const UID = "001094.structure";
  beforeEach(async () => {
    vi.spyOn(console, "log").mockImplementation(() => undefined);
    await insertUser(UID);
    await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json, body) VALUES ('s1', 'src', 'published', ?, ?)",
      JSON.stringify(LINES), "夢を 見てた\n君と");
  });
  afterEach(() => vi.restoreAllMocks());

  it("保存して検索用本文も直し、応答に本文を返さない", async () => {
    const r = await callJson("POST", "/songs/s1/lyric-structure",
      { headers: await bearer(UID), body: { op: "split", lineId: "ll_1", at: 3 } });
    expect(r.status).toBe(200);
    expect(JSON.stringify(r.body)).not.toContain("夢");
    const saved = await row<{ lines_json: string; body: string }>("SELECT lines_json, body FROM song_lyrics WHERE song_id = 's1'");
    expect(saved!.body).toBe("夢を\n見てた\n君と");
    expect(JSON.parse(saved!.lines_json)).toHaveLength(4);
  });

  it("未ログインは 401", async () => {
    const r = await callJson("POST", "/songs/s1/lyric-structure", { body: { op: "split", lineId: "ll_1", at: 3 } });
    expect(r.status).toBe(401);
  });
});
