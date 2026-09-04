import { describe, expect, it } from "vitest";
import {
  buildCallEditSummary,
  countCallAnnotations,
  isCallAnnotationUnchanged,
} from "../src/call_stats";
import type { LyricLineRow } from "../src/routes/lyrics";

// 数え方の定義はここが唯一の正 (migration 0032 の backfill SQL も同じ規則を SQL で書いたもの)。
// 数え方が変わると「コールガイドがある曲」の母集合そのものが変わるので、規則を固定する。

function line(over: Partial<LyricLineRow> = {}): LyricLineRow {
  return { id: "ll_1", ord: 0, kind: "lyric", text: "あ", section: null, start_ms: null, ...over };
}

function call(over: Partial<NonNullable<LyricLineRow["calls"]>[number]> = {}) {
  return {
    id: "cl_1",
    start: 0,
    end: 1,
    anchorText: "あ",
    text: "ハイ！",
    emphasis: "normal" as const,
    timing: "after" as const,
    ...over,
  };
}

describe("countCallAnnotations", () => {
  it("行が無ければ 0 件", () => {
    expect(countCallAnnotations([])).toEqual({ callLines: 0, callCount: 0 });
  });

  it("コールのある行数とコール総数を別々に数える", () => {
    const lines = [
      line({ id: "a", calls: [call(), call({ id: "cl_2" })] }),
      line({ id: "b", calls: [call(), call({ id: "cl_3" }), call({ id: "cl_4" })] }),
      line({ id: "c" }),
    ];
    expect(countCallAnnotations(lines)).toEqual({ callLines: 2, callCount: 5 });
  });

  it("clap だけの行も整備済みとして行数に数える (コール総数には入れない)", () => {
    const lines = [
      line({ id: "a", clap: "back_beat", calls: [] }),
      line({ id: "b", clap: "none" }),
      line({ id: "c", clap: null, calls: [] }),
    ];
    // 「ここは叩かない」も積極的な指定なので整備済み。未指定 (null) だけが未整備。
    expect(countCallAnnotations(lines)).toEqual({ callLines: 2, callCount: 0 });
  });

  it("calls が欠けている / 壊れている行があっても落ちない", () => {
    // 0027 以前に書かれた行や、壊れた JSON から parseLines が返した行を想定。
    const lines = [
      line({ id: "a", calls: undefined }),
      line({ id: "b", calls: null as unknown as [] }),
      line({ id: "c", calls: "nope" as unknown as [] }),
      line({ id: "d", calls: [call()] }),
    ];
    expect(countCallAnnotations(lines)).toEqual({ callLines: 1, callCount: 1 });
  });
});

describe("buildCallEditSummary", () => {
  const c = (callLines: number, callCount: number) => ({ callLines, callCount });

  it("新規に書いた / 増やした / 全部消した の 3 パターン", () => {
    expect(buildCallEditSummary(c(0, 0), c(18, 42))).toBe("calls 0->42, lines 0->18");
    expect(buildCallEditSummary(c(10, 28), c(18, 42))).toBe("calls 28->42, lines 10->18");
    expect(buildCallEditSummary(c(18, 42), c(0, 0))).toBe("calls 42->0, lines 18->0");
  });

  it("ASCII の機械文字列である (表示文言はクライアントが組み立てる契約)", () => {
    expect(buildCallEditSummary(c(1, 2), c(3, 4))).toMatch(/^[\x20-\x7e]+$/);
  });
});

describe("isCallAnnotationUnchanged", () => {
  const base = [line({ id: "a", clap: "back_beat", calls: [call()] }), line({ id: "b" })];

  it("同じ内容なら無変更", () => {
    expect(isCallAnnotationUnchanged(base, structuredClone(base))).toBe(true);
  });

  it("call の id だけ違うのは無変更 (サーバが保存のたびに採番しうるため)", () => {
    const next = structuredClone(base);
    next[0].calls![0].id = "cl_regenerated";
    expect(isCallAnnotationUnchanged(base, next)).toBe(true);
  });

  it("件数が同じでも文言を直したら変更 (履歴に残す)", () => {
    const next = structuredClone(base);
    next[0].calls![0].text = "フー！";
    expect(isCallAnnotationUnchanged(base, next)).toBe(false);
  });

  it("stale を落とす保存 (アンカーの貼り直し) も変更として扱う", () => {
    const staleBefore = structuredClone(base);
    staleBefore[0].calls![0].stale = true;
    // 件数も文言も同じだが、人がアンカーを貼り直した本物の編集。
    expect(isCallAnnotationUnchanged(staleBefore, base)).toBe(false);
  });

  it("clap を変えたら変更", () => {
    const next = structuredClone(base);
    next[0].clap = "ppph";
    expect(isCallAnnotationUnchanged(base, next)).toBe(false);
  });

  it("コールを消したら変更", () => {
    const next = structuredClone(base);
    next[0].calls = [];
    expect(isCallAnnotationUnchanged(base, next)).toBe(false);
  });
});
