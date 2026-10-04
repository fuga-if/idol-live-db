// lyrics_ruby.ts — 歌詞の振り仮名 (ルビ) の記法。
//
// 本文では振り仮名を青空文庫と同じ `五輪咲《ごりん》` で書く (親字が漢字のまとまりでないときは
// `｜親字《よみ》`)。括弧 （） () は被せ・コーラスの印だけに使う。描き方と読み方はコア
// (imas-core domain/lyric_sync.rs の ruby_spans) が持つ。
//
// 歌詞サイトの本文は振り仮名も括弧で書いてあるので、取り込むときに「漢字の直後の、かなだけの
// 括弧」を《》に直す。括弧 1 字を記号 1 字に置き換えるだけなので、行の文字数は変わらない
// (コールの位置がずれない)。

const KANJI = "\\u3400-\\u4DBF\\u4E00-\\u9FFF\\uF900-\\uFAFF々〆ヶ";
const KANA = "\\u3041-\\u309F\\u30A1-\\u30FF";
const BRACKET_RUBY = new RegExp(
  `([${KANJI}])[（(]([${KANA} 　]*[${KANA}][${KANA} 　]*)[）)]`,
  "gu"
);

/** 振り仮名の括弧を《》に直す (文字数は変わらない)。 */
export function toRubyNotation(text: string): string {
  return text.replace(BRACKET_RUBY, "$1《$2》");
}

/** 検索用の平文から振り仮名を外す (「五輪咲《ごりん》駆動」→「五輪咲駆動」)。 */
export function stripRuby(text: string): string {
  return text.replace(/《[^《》]*》/gu, "").replace(/｜/gu, "");
}

type RubyLine = { kind?: string; text: string; calls?: Array<{ start: number; end: number; anchorText: string }> };

/**
 * 行の並びの振り仮名の括弧を《》に直す。コールの位置はそのまま (文字数が変わらない)、
 * 掛かっている語の控え (anchorText) だけ直した本文に合わせる。直した行の数を返す。
 */
export function convertLinesToRubyNotation<L extends RubyLine>(lines: L[]): { lines: L[]; changed: number } {
  let changed = 0;
  const next = lines.map((line) => {
    if (line.kind && line.kind !== "lyric") return line;
    const text = toRubyNotation(line.text);
    if (text === line.text) return line;
    changed += 1;
    const scalars = Array.from(text);
    const before = Array.from(line.text);
    const calls = line.calls?.map((c) => {
      const old = before.slice(c.start, c.end).join("");
      return old === c.anchorText ? { ...c, anchorText: scalars.slice(c.start, c.end).join("") } : c;
    });
    return { ...line, text, ...(calls ? { calls } : {}) };
  });
  return { lines: next, changed };
}

/** 行の中の《》振り仮名 (見直し用)。`at` は「《」のスカラー位置、`base` は直前の漢字のまとまり (｜があればそこから)。 */
export function listRuby(text: string): Array<{ at: number; base: string; ruby: string }> {
  const chars = Array.from(text);
  const out: Array<{ at: number; base: string; ruby: string }> = [];
  const kanji = new RegExp(`[${KANJI}]`, "u");
  let segmentStart = 0;
  for (let j = 0; j < chars.length; j++) {
    if (chars[j] !== "》") continue;
    // 閉じの直前の「《」(いちばん内側) と組にする (コアの ruby_spans と同じ読み方)。
    const open = chars.lastIndexOf("《", j);
    if (open < segmentStart) continue;
    const marker = chars.lastIndexOf("｜", open);
    let start = open;
    if (marker >= segmentStart) start = marker + 1;
    else while (start > segmentStart && kanji.test(chars[start - 1])) start--;
    if (start < open && open + 1 < j) {
      out.push({ at: open, base: chars.slice(start, open).join(""), ruby: chars.slice(open + 1, j).join("") });
      segmentStart = j + 1;
    }
  }
  return out;
}
