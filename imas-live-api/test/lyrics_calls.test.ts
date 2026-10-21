// コールの保存ボディの検証 (validateCallsBody) と、歌詞差し替え時の引き継ぎ (carryOverAnnotation)。
// どちらも純粋関数なので、HTTP を通さず表で確かめる。HTTP の経路は test/calls_put.test.ts にある。
// 本文には実在の歌詞を使わない (意味の無い文字列だけ)。

import { describe, expect, it } from "vitest";
import {
  carryOverAnnotation,
  MAX_CALL_ID_CHARS,
  MAX_CALL_TEXT_CHARS,
  MAX_CALLS_PER_LINE,
  MAX_CALLS_PER_SONG,
  validateCallsBody,
} from "../src/lyrics_calls";

// 「𠮷」はサロゲートペア (UTF-16 で 2 単位、スカラーで 1)。位置はスカラーで数える。
const LINES = new Map([
  ["l1", "あいう𠮷えお"],
  ["l2", "かきく"],
]);

const call = (overrides: Record<string, unknown> = {}) => ({ start: 0, end: 2, text: "はい", ...overrides });
const body = (calls: unknown[], extra: Record<string, unknown> = {}) => ({ lines: [{ id: "l1", calls, ...extra }] });

describe("validateCallsBody", () => {
  it("位置はスカラーで数え、anchorText はサーバが本文から切り出す。既定は normal / after", () => {
    const r = validateCallsBody(body([call({ start: 2, end: 4, anchor_text: "う𠮷", id: "cl_keep" })], { clap: "ppph" }), LINES);
    expect(r).toEqual({
      ok: true,
      lines: [{
        id: "l1",
        clap: "ppph",
        calls: [{ id: "cl_keep", start: 2, end: 4, anchorText: "う𠮷", text: "はい", emphasis: "normal", timing: "after" }],
      }],
    });
  });

  it("id の無いコールは cl_ で採番する。幅ゼロは over を送っても after にする。空配列は全消し", () => {
    const r = validateCallsBody(body([call({ start: 1, end: 1, timing: "over" }), call({ timing: "over", emphasis: "optional" })]), LINES);
    if (!r.ok) throw new Error(r.error);
    const [zero, over] = r.lines[0].calls;
    expect(zero.id).toMatch(/^cl_/);
    expect(zero.timing).toBe("after");
    expect(over).toMatchObject({ timing: "over", emphasis: "optional" });
    expect(validateCallsBody({ lines: [] }, LINES)).toEqual({ ok: true, lines: [] });
    expect(validateCallsBody({ lines: [{ id: "l2" }] }, LINES)).toEqual({ ok: true, lines: [{ id: "l2", clap: null, calls: [] }] });
  });

  it.each<[string, unknown, string]>([
    ["ボディが配列", [], "body must be an object"],
    ["lines が無い", {}, "lines must be an array"],
    ["行が多すぎる", { lines: [{ id: "l1" }, { id: "l2" }, { id: "l3" }] }, "too many lines (3 > 2)"],
    ["行がオブジェクトでない", { lines: ["l1"] }, "lines[0] must be an object"],
    ["行の id が空", { lines: [{ id: "" }] }, "lines[0].id must be a string"],
    ["知らない行", { lines: [{ id: "zz" }] }, "lines[0].id is not a line of this song"],
    ["行の重複", { lines: [{ id: "l1" }, { id: "l1" }] }, "lines[1].id is duplicated"],
    ["clap が不正", body([], { clap: "clap" }), "lines[0].clap must be null or one of back_beat/four_on_floor/ppph/none"],
    ["calls が配列でない", body([], { calls: {} }), "lines[0].calls must be an array"],
    ["1 行のコールが多すぎる", body(Array(MAX_CALLS_PER_LINE + 1).fill(call())), `lines[0].calls too many (${MAX_CALLS_PER_LINE + 1} > ${MAX_CALLS_PER_LINE})`],
    ["コールがオブジェクトでない", body([1]), "lines[0].calls[0] must be an object"],
    ["コールの id が長すぎる", body([call({ id: "x".repeat(MAX_CALL_ID_CHARS + 1) })]), `lines[0].calls[0].id must be a string (1-${MAX_CALL_ID_CHARS} chars)`],
    ["コールの id が数値", body([call({ id: 3 })]), `lines[0].calls[0].id must be a string (1-${MAX_CALL_ID_CHARS} chars)`],
    ["start が負", body([call({ start: -1 })]), "lines[0].calls[0].start / lines[0].calls[0].end must be non-negative integers"],
    ["end が小数", body([call({ end: 1.5 })]), "lines[0].calls[0].start / lines[0].calls[0].end must be non-negative integers"],
    ["start > end", body([call({ start: 3, end: 2 })]), "lines[0].calls[0].start must be <= lines[0].calls[0].end"],
    ["end が行の長さを超える", body([call({ end: 7 })]), "lines[0].calls[0].end out of range (line has 6 chars)"],
    ["anchorText が文字列でない", body([call({ anchorText: 1 })]), "lines[0].calls[0].anchorText must be a string"],
    ["text が空", body([call({ text: "" })]), "lines[0].calls[0].text must be a non-empty string"],
    ["text に改行", body([call({ text: "は\nい" })]), "lines[0].calls[0].text must not contain a newline"],
    ["text が長すぎる", body([call({ text: "あ".repeat(MAX_CALL_TEXT_CHARS + 1) })]), `lines[0].calls[0].text too long (max ${MAX_CALL_TEXT_CHARS})`],
    ["emphasis が不正", body([call({ emphasis: "loud" })]), "lines[0].calls[0].emphasis must be one of normal/optional/performer_request"],
    ["timing が不正", body([call({ timing: "before" })]), "lines[0].calls[0].timing must be one of over/after"],
  ])("%s は 400 の文言", (_label, input, error) => {
    expect(validateCallsBody(input, LINES)).toEqual({ ok: false, error });
  });

  it("anchorText が本文の切り出しと食い違えば、期待値を添えて落とす (UTF-16 で数えた位置を検出する)", () => {
    // UTF-16 で数えると [3,5) は「𠮷」の 2 単位になるが、スカラーでは「𠮷え」
    const r = validateCallsBody(body([call({ start: 3, end: 5, anchorText: "𠮷" })]), LINES);
    expect(r).toEqual({
      ok: false,
      error: 'lines[0].calls[0].anchorText does not match line text at [3,5) (expected "𠮷え"); positions are counted in Unicode scalars',
    });
  });

  it("曲全体のコール数に上限がある", () => {
    const many = new Map(Array.from({ length: 31 }, (_, i) => [`m${i}`, "あいう"] as [string, string]));
    const lines = [...many.keys()].map((id) => ({ id, calls: Array(MAX_CALLS_PER_LINE).fill(call()) }));
    expect(validateCallsBody({ lines }, many)).toEqual({ ok: false, error: `too many calls in this song (max ${MAX_CALLS_PER_SONG})` });
  });
});

describe("carryOverAnnotation", () => {
  it("本文が同じならそのまま引き継ぎ、stale は立てない", () => {
    const prev = { clap: "ppph", calls: [{ id: "c1", start: 0, end: 2, anchorText: "かき", text: "はい", emphasis: "optional", timing: "over", startMs: 1200 }] };
    expect(carryOverAnnotation(prev, "かきく")).toEqual({
      clap: "ppph",
      calls: [{ id: "c1", start: 0, end: 2, anchorText: "かき", text: "はい", emphasis: "optional", timing: "over", startMs: 1200 }],
    });
  });

  it("アンカーの文字列が変わったら stale を立て、位置は新しい本文の長さに丸める (消さない)", () => {
    const prev = { calls: [{ id: "c1", start: 2, end: 6, anchorText: "くけこさ", text: "はい" }] };
    expect(carryOverAnnotation(prev, "かきX")).toEqual({
      clap: null,
      calls: [{ id: "c1", start: 2, end: 3, anchorText: "くけこさ", text: "はい", emphasis: "normal", timing: "after", stale: true }],
    });
  });

  it("壊れた保存値でも落ちない: 不明な clap / emphasis / timing は既定、text の無いコールと非オブジェクトは捨てる", () => {
    const prev = {
      clap: "unknown",
      calls: [
        "junk",
        { start: 0, end: 1, text: "" },
        { start: "x", end: -1, anchorText: 5, text: "はい", emphasis: "loud", timing: "before" },
        { start: 1, end: 3, anchorText: "きく", text: "おい", timing: "sideways" },
      ],
    };
    const r = carryOverAnnotation(prev, "かきく");
    expect(r.clap).toBeNull();
    expect(r.calls).toHaveLength(2);
    // start も end も読めない → 幅ゼロ (0,0)。幅ゼロは after、anchorText は空として突き合わせる
    expect(r.calls[0]).toMatchObject({ start: 0, end: 0, anchorText: "", emphasis: "normal", timing: "after" });
    expect(r.calls[0].id).toMatch(/^cl_/);
    expect(r.calls[0]).not.toHaveProperty("stale");
    expect(r.calls[1]).toMatchObject({ start: 1, end: 3, timing: "after" });
  });

  it("前の行が無ければ空", () => {
    expect(carryOverAnnotation(undefined, "かきく")).toEqual({ clap: null, calls: [] });
    expect(carryOverAnnotation({ calls: "not-array" }, "かきく")).toEqual({ clap: null, calls: [] });
  });
});
