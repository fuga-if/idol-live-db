// lyrics_structure.ts — 歌詞の行の区切りを動かす (くっつける / 切り離す)。
//
// **歌詞の文字は書き換えない。** 動かせるのは行の区切りだけで、くっつけるときに挟めるのは
// 空白 (なし / 半角 / 全角) だけ。だからログインしていれば誰でも操作できる
// (コールの編集と同じ扱い。本文の投入 PUT /admin/lyrics とは権限が違う)。
//
// 行に付いているものの扱い:
//   コール … くっつける: 後ろの行のコールを前の行へ、位置をずらして移す。
//            切り離す: 切る位置より後ろに掛かるコールを新しい行へ移す。またぐコールは
//            前の行に残し、範囲を丸めて stale を立てる (選び直してもらう)。
//   時刻   … 前の行のものを残す。切り離した後ろの行は記録なし。
//   手拍子・被せ指定 … 前の行のものを残す。
//   ここ好き … 行 ID に付くので、くっつけて消えた行の分は数えられなくなる (消しはしない)。
//
// 純粋関数だけを置く (D1 も Request も触らない)。routes/lyric_structure.ts が使う。

import type { LyricLineRow, LyricPartBreak } from "./routes/lyrics";
import { scalarLength, scalarSlice, toScalars } from "./lyrics_calls";

export type StructureOp =
  | { op: "merge"; lineId: string; joiner: "" | " " | "　" }
  | { op: "split"; lineId: string; at: number }
  // 振り仮名にする / やめる。`at` は括弧 (「（」「(」) か「《」の位置。記号を入れ替えるだけで文字数は変わらない。
  // `base` を渡すと親字の頭をそこにする (当て字・漢字のまとまりの一部)。無ければ直前の漢字のまとまり。
  | { op: "ruby"; lineId: string; at: number; base?: number }
  | { op: "unruby"; lineId: string; at: number }
  // 振り仮名の親字の頭を決め直す。`at` は「《」の位置、`base` は親字の頭の位置 (「｜」を置く)。
  // 漢字のまとまりの一部だけに掛ける (記憶｜抱《イダ》) ときと、漢字でない親字 (｜ＳＴＡＲ《ほし》) に使う。
  | { op: "rubyBase"; lineId: string; at: number; base: number };

export type StructureResult = { ok: true; lines: LyricLineRow[] } | { ok: false; error: string };

const JOINERS = new Set(["", " ", "　"]);

/** ボディを検証して操作にする。 */
export function parseStructureOp(body: unknown): StructureOp | string {
  if (!body || typeof body !== "object") return "body must be an object";
  const b = body as Record<string, unknown>;
  // iOS の APIClient はキーを snake_case にして送る (lineId → line_id)。両方を受ける。
  const lineId = b.lineId ?? b.line_id;
  if (typeof lineId !== "string" || !lineId) return "lineId must be a string";
  if (b.op === "merge") {
    const joiner = b.joiner ?? " ";
    if (typeof joiner !== "string" || !JOINERS.has(joiner)) return "joiner must be '', ' ' or '　'";
    return { op: "merge", lineId, joiner: joiner as "" | " " | "　" };
  }
  if (b.op === "split") {
    if (typeof b.at !== "number" || !Number.isInteger(b.at)) return "at must be an integer";
    return { op: "split", lineId, at: b.at };
  }
  if (b.op === "ruby" || b.op === "unruby") {
    if (typeof b.at !== "number" || !Number.isInteger(b.at)) return "at must be an integer";
    if (b.op === "ruby" && b.base !== undefined && b.base !== null) {
      if (typeof b.base !== "number" || !Number.isInteger(b.base)) return "base must be an integer";
      return { op: "ruby", lineId, at: b.at, base: b.base };
    }
    return { op: b.op, lineId, at: b.at };
  }
  if (b.op === "rubyBase") {
    if (typeof b.at !== "number" || !Number.isInteger(b.at)) return "at must be an integer";
    if (typeof b.base !== "number" || !Number.isInteger(b.base)) return "base must be an integer";
    return { op: "rubyBase", lineId, at: b.at, base: b.base };
  }
  return "op must be merge, split, ruby, unruby or rubyBase";
}

/** 行の区切りを動かした後の行の並び。ord は振り直す。 */
export function applyStructureOp(
  lines: LyricLineRow[],
  op: StructureOp,
  newId: () => string
): StructureResult {
  const i = lines.findIndex((l) => l.id === op.lineId);
  if (i < 0) return { ok: false, error: "line not found" };
  const line = lines[i];
  if (line.kind !== "lyric") return { ok: false, error: "only lyric lines can be edited" };

  let next: LyricLineRow[];
  if (op.op === "rubyBase") {
    const r = setRubyBase(line, op.at, op.base);
    if (typeof r === "string") return { ok: false, error: r };
    next = [...lines.slice(0, i), r, ...lines.slice(i + 1)];
  } else if (op.op === "ruby" || op.op === "unruby") {
    const scalars = toScalars(line.text);
    const [open, close] = op.op === "ruby" ? [["（", "("], ["）", ")"]] : [["《"], ["》"]];
    if (!open.includes(scalars[op.at] ?? "")) return { ok: false, error: "at must point at an opening bracket" };
    const end = scalars.findIndex((c, k) => k > op.at && close.includes(c));
    if (end < 0 || end === op.at + 1) return { ok: false, error: "the bracket must be closed and not empty" };
    if (op.op === "ruby") {
      // 親字は直前の漢字のまとまり。漢字の直後でない括弧は親字の頭 (`base`) を選んでもらう。
      if (op.at === 0 || (op.base === undefined && !isKanji(scalars[op.at - 1]))) {
        return { ok: false, error: "ruby must follow kanji" };
      }
      scalars[op.at] = "《"; scalars[end] = "》";
    } else {
      scalars[op.at] = "（"; scalars[end] = "）";
    }
    const text = scalars.join("");
    // 文字数は変わらないので位置はそのまま。掛かっている語の控えだけ直す。
    const calls = (line.calls ?? []).map((c) =>
      scalarSlice(line.text, c.start, c.end) === c.anchorText ? { ...c, anchorText: scalarSlice(text, c.start, c.end) } : c
    );
    let changed: LyricLineRow = { ...line, text, calls };
    if (op.op === "ruby" && op.base !== undefined) {
      const r = setRubyBase(changed, op.at, op.base);
      if (typeof r === "string") return { ok: false, error: r };
      changed = r;
    }
    next = [...lines.slice(0, i), changed, ...lines.slice(i + 1)];
  } else if (op.op === "merge") {
    const following = lines[i + 1];
    if (!following || following.kind !== "lyric") {
      return { ok: false, error: "the next line must be a lyric line" };
    }
    const shift = scalarLength(line.text) + scalarLength(op.joiner);
    // パート: 後ろの行の歌う人が違えば、つなぎ目に区切りを置く。後ろの行の区切りはずらして持ってくる。
    const lastSingers = (line.partBreaks?.length ? line.partBreaks[line.partBreaks.length - 1].singers : line.singers) ?? [];
    const followingSingers = following.singers ?? [];
    const breaks: LyricPartBreak[] = [
      ...(line.partBreaks ?? []),
      ...(sameSingers(lastSingers, followingSingers) ? [] : [{ at: shift, singers: [...followingSingers] }]),
      ...(following.partBreaks ?? []).map((b) => ({ ...b, at: b.at + shift })),
    ];
    const { partBreaks: _drop, ...lineRest } = line;
    const merged: LyricLineRow = {
      ...lineRest,
      ...(breaks.length ? { partBreaks: breaks } : {}),
      text: line.text + op.joiner + following.text,
      calls: [
        ...(line.calls ?? []),
        ...(following.calls ?? []).map((c) => ({ ...c, start: c.start + shift, end: c.end + shift })),
      ],
    };
    next = [...lines.slice(0, i), merged, ...lines.slice(i + 2)];
  } else {
    const scalars = toScalars(line.text);
    if (op.at <= 0 || op.at >= scalars.length) return { ok: false, error: "at must be inside the line" };
    // 切る位置まわりの空白は落とす (「夢を 見てた」を「夢を」「見てた」に)。文字は足さない。
    const head = scalars.slice(0, op.at).join("").replace(/[ 　]+$/u, "");
    const tailRaw = scalars.slice(op.at).join("");
    const tail = tailRaw.replace(/^[ 　]+/u, "");
    if (!head || !tail) return { ok: false, error: "both sides must have text" };
    const tailOffset = op.at + (scalarLength(tailRaw) - scalarLength(tail));
    const headLength = scalarLength(head);
    const headCalls = [];
    const tailCalls = [];
    for (const c of line.calls ?? []) {
      if (c.start >= op.at && c.end >= c.start) {
        const start = Math.max(0, c.start - tailOffset);
        const end = Math.max(start, c.end - tailOffset);
        const stale = scalarSlice(tail, start, end) !== c.anchorText;
        tailCalls.push({ ...c, start, end, ...(stale ? { stale: true } : {}) });
      } else {
        const start = Math.min(c.start, headLength);
        const end = Math.min(Math.max(c.end, start), headLength);
        const stale = scalarSlice(head, start, end) !== c.anchorText;
        headCalls.push({ ...c, start, end, ...(stale ? { stale: true } : {}) });
      }
    }
    // パート: 切る位置で歌っている人が後ろの行の頭を歌う。区切りは前後に振り分ける。
    const breaks = line.partBreaks ?? [];
    const tailSingers = [...breaks].reverse().find((b) => b.at <= tailOffset)?.singers ?? line.singers ?? [];
    const headBreaks = breaks.filter((b) => b.at < headLength);
    const tailBreaks = breaks
      .filter((b) => b.at > tailOffset)
      .map((b) => ({ ...b, at: b.at - tailOffset }));
    const { partBreaks: _drop, ...lineRest } = line;
    const first: LyricLineRow = {
      ...lineRest, text: head, calls: headCalls, ...(headBreaks.length ? { partBreaks: headBreaks } : {}),
    };
    const second: LyricLineRow = {
      id: newId(), ord: 0, kind: "lyric", text: tail, section: line.section,
      start_ms: null, clap: null, calls: tailCalls,
      ...(tailSingers.length ? { singers: [...tailSingers] } : {}),
      ...(tailBreaks.length ? { partBreaks: tailBreaks } : {}),
    };
    next = [...lines.slice(0, i), first, second, ...lines.slice(i + 1)];
  }
  return { ok: true, lines: next.map((l, ord) => ({ ...l, ord })) };
}

/**
 * 「《」の親字の頭に「｜」を置く。前に置いてあった「｜」は外す。
 * 親字は前の「》」(か行頭) より後ろで、「《」の手前に 1 文字以上。コールは文字のずれに合わせて動かす。
 */
function setRubyBase(line: LyricLineRow, at: number, base: number): LyricLineRow | string {
  const scalars = toScalars(line.text);
  if (scalars[at] !== "《") return "at must point at 《";
  if (!scalars.slice(at + 1).includes("》")) return "the bracket must be closed";
  const segmentStart = scalars.slice(0, at).lastIndexOf("》") + 1;
  if (base < segmentStart || base >= at) return "base must be before 《 and after the previous ruby";
  const oldMarker = scalars.slice(segmentStart, at).lastIndexOf("｜");
  const removed = oldMarker >= 0 ? segmentStart + oldMarker : -1;
  if (removed >= 0 && base > removed) base -= 1; // 外した「｜」の分だけ前に詰まる
  const without = removed >= 0 ? [...scalars.slice(0, removed), ...scalars.slice(removed + 1)] : scalars;
  if (without[base] === "｜") return "base must point at a character";
  // 親字が直前の漢字のまとまりそのものなら「｜」は要らない (書かなくても同じに読める)。
  const open = removed >= 0 ? at - 1 : at;
  let natural = open;
  while (natural > 0 && isKanji(without[natural - 1])) natural -= 1;
  if (natural === base) {
    if (removed < 0) return line;
    const text = without.join("");
    const calls = (line.calls ?? []).map((c) => {
      const start = c.start > removed ? c.start - 1 : c.start;
      const end = Math.max(start, c.end > removed ? c.end - 1 : c.end);
      const stale = scalarSlice(text, start, end) !== c.anchorText;
      return { ...c, start, end, ...(stale ? { stale: true } : {}) };
    });
    const partBreaks = line.partBreaks?.map((b) => ({ ...b, at: b.at > removed ? b.at - 1 : b.at }));
    return { ...line, text, calls, ...(partBreaks ? { partBreaks } : {}) };
  }
  const text = [...without.slice(0, base), "｜", ...without.slice(base)].join("");
  // 元の位置 → 新しい位置 (外した「｜」の後ろは 1 つ詰め、置いた「｜」の後ろは 1 つ送る)。
  const move = (k: number) => {
    const shifted = removed >= 0 && k > removed ? k - 1 : k;
    return shifted >= base ? shifted + 1 : shifted;
  };
  const calls = (line.calls ?? []).map((c) => {
    const start = move(c.start);
    const end = Math.max(start, move(c.end));
    const stale = scalarSlice(text, start, end) !== c.anchorText;
    return { ...c, start, end, ...(stale ? { stale: true } : {}) };
  });
  const partBreaks = line.partBreaks?.map((b) => ({ ...b, at: move(b.at) }));
  return { ...line, text, calls, ...(partBreaks ? { partBreaks } : {}) };
}

function sameSingers(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((x, i) => x === b[i]);
}

function isKanji(c: string | undefined): boolean {
  return !!c && /[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF々〆ヶ]/u.test(c);
}
