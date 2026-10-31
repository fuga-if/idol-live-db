/**
 * 歌詞の行の置き方 — **差し替え可能な import 面 (配管であって規則ではない)**。
 *
 * 振り仮名 (`親字《よみ》` / `｜親字《よみ》`) の読み方、括弧で書いた脇の字 (被せ)、
 * パート分け (歌う人) のひと続き、歌詞と同じ文字のコールの判定は、すべて
 * `imas_core::domain::lyric_display::lyric_line_display` が決める (アプリと同じ部品を組んだもの)。
 * 実体は `web/wasm/imas-query-wasm` の `lyric_lines_display_json`。ここがやるのは
 * 「wasm をロードし、返ってきた JSON 文字列を parse する」ことだけ
 * (`src/lib/card/decode.ts` と同じ流儀)。
 *
 * 歌詞は押されたときに 1 曲ぶんだけ取りに行くので、静的な JSON に置き方を落としておけない。
 * だからブラウザで wasm を呼ぶ。
 */

/** 画面に置く字のひと続き。形は Rust の `LyricRun` と 1:1 (型注釈だけ)。 */
export interface LyricRun {
  /** 元の本文のスカラー位置 (`end` は排他)。行を隙間なく敷き詰める。 */
  start: number;
  end: number;
  /** 出す字 (振り仮名の記号と読みは外してある)。 */
  text: string;
  /** 親字の上に乗せる読み。 */
  ruby: string | null;
  /** 括弧で書いた脇の字 (被せ・コーラス)。 */
  aside: boolean;
  /** 歌う人 (原唱者の id、原唱者の並び)。 */
  singers: string[];
}

/** 1 行ぶんの置き方。形は Rust の `LyricLineDisplay` と 1:1。 */
export interface LyricLineDisplay {
  runs: LyricRun[];
  /** コールごと (行の calls と同じ順)。true は歌詞と同じ文字 (行に並べず、歌詞の側を濃く敷く)。 */
  echoes: boolean[];
  /** 行の下に添える歌う人のまとまり (id)。 */
  partGroups: string[][];
}

let cached: Promise<typeof import("../query/imas_query_wasm")> | null = null;

function loadModule(): Promise<typeof import("../query/imas_query_wasm")> {
  cached ??= (async () => {
    const mod = await import("../query/imas_query_wasm");
    await mod.default();
    return mod;
  })();
  return cached;
}

/**
 * 行ごとの置き方。`lines` は Worker が返した `lines` をそのまま、`cast` はパート分けを出す
 * 原唱者の id (ソロ曲などは空)。失敗したら例外をそのまま投げる (呼び出し側が素の本文に倒す)。
 */
export async function lyricLinesDisplay(lines: unknown[], cast: string[]): Promise<LyricLineDisplay[]> {
  const mod = await loadModule();
  return JSON.parse(mod.lyric_lines_display_json(JSON.stringify(lines), JSON.stringify(cast))) as LyricLineDisplay[];
}
