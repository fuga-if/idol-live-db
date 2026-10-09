// lyrics_line_match.ts — 歌詞を差し替えるとき、新しい各行が前のどの行の続きかを決める。
//
// 行 id・タイミング・歌割・コールは「同じ行」に引き継ぐ。前は ord (何行目か) で引き継いでいたので、
// 抜けていた 1 行を足すだけで、その行から後ろの注釈が全部 1 行ずつずれていた。
// いまは本文の同じ行を先に組にし (最長共通部分列)、組にならなかった間だけ、間の中での位置で組にする
// (1 行だけ直した・数行を書き換えた、はこちらで同じ行に残る)。
//
// 純粋関数だけを置く (D1 も Request も触らない)。routes/lyrics.ts の storeLyrics が使う。

/** 突き合わせに使う行の形 (種類と本文だけ見る)。 */
export interface MatchableLine {
  kind?: string | null;
  text: string;
}

/**
 * `next[i]` が続きにあたる `prev` の添字 (無ければ undefined) を返す。
 * 本文と種類が同じ行を最長共通部分列で組にし、その間に挟まれた行は種類が同じものだけ位置順に組にする。
 */
export function matchLines(prev: readonly MatchableLine[], next: readonly MatchableLine[]): Array<number | undefined> {
  const same = (a: MatchableLine, b: MatchableLine) => (a.kind ?? "lyric") === (b.kind ?? "lyric") && a.text === b.text;
  const n = prev.length;
  const m = next.length;
  // lcs[i][j] = prev[i..] と next[j..] の最長共通部分列の長さ。
  const lcs = Array.from({ length: n + 1 }, () => new Array<number>(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lcs[i]![j] = same(prev[i]!, next[j]!) ? lcs[i + 1]![j + 1]! + 1 : Math.max(lcs[i + 1]![j]!, lcs[i]![j + 1]!);
    }
  }
  const out = new Array<number | undefined>(m).fill(undefined);
  // 組にならなかった間 (prev[pi..i), next[nj..j)) を、種類が同じものだけ位置順に組にする。
  const pairGap = (pi: number, i: number, nj: number, j: number) => {
    for (let a = pi, b = nj; a < i && b < j;) {
      if ((prev[a]!.kind ?? "lyric") === (next[b]!.kind ?? "lyric")) out[b++] = a++;
      else if (i - a > j - b) a++;
      else b++;
    }
  };
  let i = 0, j = 0, pi = 0, nj = 0;
  while (i < n && j < m) {
    if (same(prev[i]!, next[j]!) && lcs[i]![j] === lcs[i + 1]![j + 1]! + 1) {
      pairGap(pi, i, nj, j);
      out[j] = i;
      pi = ++i;
      nj = ++j;
    } else if (lcs[i + 1]![j]! >= lcs[i]![j + 1]!) i++;
    else j++;
  }
  pairGap(pi, n, nj, m);
  return out;
}
