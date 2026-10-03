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

import type { LyricLineRow } from "./routes/lyrics";
import { scalarLength, scalarSlice, toScalars } from "./lyrics_calls";

export type StructureOp =
  | { op: "merge"; lineId: string; joiner: "" | " " | "　" }
  | { op: "split"; lineId: string; at: number };

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
  return "op must be merge or split";
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
  if (op.op === "merge") {
    const following = lines[i + 1];
    if (!following || following.kind !== "lyric") {
      return { ok: false, error: "the next line must be a lyric line" };
    }
    const shift = scalarLength(line.text) + scalarLength(op.joiner);
    const merged: LyricLineRow = {
      ...line,
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
    const first: LyricLineRow = { ...line, text: head, calls: headCalls };
    const second: LyricLineRow = {
      id: newId(), ord: 0, kind: "lyric", text: tail, section: line.section,
      start_ms: null, clap: null, calls: tailCalls,
      // パートは切り離した後ろの行も同じ人が歌う (1 行を割っただけなので)。
      ...(line.singers?.length ? { singers: [...line.singers] } : {}),
    };
    next = [...lines.slice(0, i), first, second, ...lines.slice(i + 1)];
  }
  return { ok: true, lines: next.map((l, ord) => ({ ...l, ord })) };
}
