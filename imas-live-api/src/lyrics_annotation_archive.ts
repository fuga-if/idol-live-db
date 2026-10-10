// lyrics_annotation_archive.ts — 歌詞を消したときに退避した注釈 (歌割・タイミング・コール・ここ好き) を、
// 歌詞が入り直したときに付け直す。
//
// 2026-10-06 に歌詞本文を全削除したとき、利用者が付けた注釈だけを行 id/ord で退避した
// (lyric_annotation_archive、migrations/0049)。投稿で歌詞が入り直しても storeLyrics は
// 「同じ曲の既存の行」からしか引き継がないので、退避分はどこからも読まれず歌割が消えたままだった。
//
// ⚠️ 退避には歌詞本文が無い (anchorText も持たない)。投稿された歌詞は空行の置き方が元と違うことが
//    あるので、行は ord そのままではなく「ord + ずれ」で突き合わせる (alignArchive)。手がかりは
//    行の種類・コールや途中の区切りがその行に収まるか・行末に付いた追っかけの位置が行の長さと一致するか。
//    ずれの変わり目が決めきれない行は付けない (ずれた歌割を出すより、無い方がまし)。
// ⚠️ 本文と同じ文言だったコールは退避のとき text を除いてある。被せ (over) で幅のあるものは
//    「その箇所を一緒に叫ぶ」コールなので、投稿された本文の同じ箇所を text に戻す。
//    それ以外 (追っかけ・幅ゼロ) は文言が分からないので捨てる。

import { countCallAnnotations } from "./call_stats";
import { carryOverAnnotation, scalarLength, scalarSlice } from "./lyrics_calls";
import type { LyricLineRow, LyricPartBreak } from "./routes/lyrics";

/** 退避した 1 行ぶん。行 id は元の id (端末のここ好き・記録したタイミングが指している)。 */
export interface ArchivedLine {
  id: string;
  ord: number;
  kind: string;
  start_ms?: number | null;
  clap?: unknown;
  layer?: "overlay" | "main";
  singers?: string[] | null;
  partBreaks?: LyricPartBreak[] | null;
  calls?: ArchivedCall[] | null;
}

type ArchivedCall = {
  id?: string; start?: number; end?: number; text?: string | null;
  emphasis?: string; timing?: string; startMs?: number; stale?: boolean;
};

/** 行に利用者の注釈が 1 つでもあるか。あれば退避分で上書きしない。 */
export function hasAnnotations(lines: readonly LyricLineRow[]): boolean {
  return lines.some((l) =>
    (l.start_ms ?? l.startMs ?? null) !== null || !!l.clap || !!l.calls?.length
    || !!l.singers?.length || !!l.partBreaks?.length || !!l.layer);
}

/** 突き合わせで見る ord のずれの幅 (空行の足し引きで生じる程度)。 */
const MAX_SHIFT = 6;
/** ずれが変わるたびの減点。行末の追っかけ 1 つの一致 (加点 1) より重くして、加点目当ての乗り換えをさせない。 */
const SHIFT_CHANGE_COST = 2;

/** 退避した行が新しい行 (長さ length) に収まるか。 */
function fits(a: ArchivedLine, line: LyricLineRow | undefined): boolean {
  if (!line || line.kind !== a.kind) return false;
  const length = scalarLength(line.text);
  if ((a.partBreaks ?? []).some((b) => !(b.at > 0 && b.at < length))) return false;
  return (a.calls ?? []).every((c) => Math.max(c.start ?? 0, c.end ?? 0) <= length);
}

/** 行末の追っかけ (幅ゼロで行の長さちょうど) の数。行が合っている強い手がかり。 */
function endMatches(a: ArchivedLine, line: LyricLineRow): number {
  const length = scalarLength(line.text);
  return (a.calls ?? []).filter((c) => c.start === c.end && c.end === length).length;
}

/**
 * 退避した行 (ord 昇順) を新しい行の位置に突き合わせる。ord + ずれ の位置に置き、全体の得点
 * (行末の一致 − ずれの変わり目) が最大の並べ方を探す。最大の並べ方が複数あって位置が割れる行は
 * 結果に入れない。どう並べても収まらなければ null。
 */
export function alignArchive(lines: readonly LyricLineRow[], archived: readonly ArchivedLine[]): Map<ArchivedLine, number> | null {
  const items = [...archived].sort((x, y) => x.ord - y.ord);
  const shifts = Array.from({ length: MAX_SHIFT * 2 + 1 }, (_, i) => i - MAX_SHIFT);
  const NONE = -Infinity;
  // fwd[i][k]: items[0..i] を並べ、items[i] をずれ shifts[k] に置いたときの最大得点。bwd は後ろ側。
  const gain = items.map((a) => shifts.map((d) => {
    const line = lines[a.ord + d];
    return line && fits(a, line) ? endMatches(a, line) : NONE;
  }));
  const step = (i: number, k: number, j: number, kk: number) =>
    items[i]!.ord + shifts[k]! < items[j]!.ord + shifts[kk]! ? (k === kk ? 0 : -SHIFT_CHANGE_COST) : NONE;
  const fwd = items.map(() => shifts.map(() => NONE));
  const bwd = items.map(() => shifts.map(() => NONE));
  items.forEach((_, i) => shifts.forEach((__, k) => {
    if (gain[i]![k] === NONE) return;
    // 最初の行は、ずれの無い置き方を僅かに優先する (他の手がかりが同点のとき)。
    let best = i === 0 ? -Math.abs(shifts[k]!) * 1e-3 : NONE;
    if (i > 0) shifts.forEach((___, kk) => {
      if (fwd[i - 1]![kk] !== NONE) best = Math.max(best, fwd[i - 1]![kk]! + step(i - 1, kk, i, k));
    });
    if (best !== NONE) fwd[i]![k] = best + gain[i]![k]!;
  }));
  for (let i = items.length - 1; i >= 0; i--) shifts.forEach((_, k) => {
    if (gain[i]![k] === NONE) return;
    let best = i === items.length - 1 ? 0 : NONE;
    if (i < items.length - 1) shifts.forEach((__, kk) => {
      if (bwd[i + 1]![kk] !== NONE) best = Math.max(best, bwd[i + 1]![kk]! + gain[i + 1]![kk]! + step(i, k, i + 1, kk));
    });
    bwd[i]![k] = best;
  });
  const total = Math.max(...fwd[items.length - 1]!);
  if (total === NONE) return null;
  const out = new Map<ArchivedLine, number>();
  items.forEach((a, i) => {
    const on = shifts.filter((_, k) => fwd[i]![k] !== NONE && bwd[i]![k] !== NONE
      && Math.abs(fwd[i]![k]! + bwd[i]![k]! - total) < 1e-6);
    if (on.length === 1) out.set(a, a.ord + on[0]!);
  });
  return out;
}

const BRACKETS: Record<string, string> = {
  "(": ")", "（": "）", "《": "》", "〈": "〉", "「": "」", "『": "』", "[": "]", "［": "］", "【": "】",
};
/** 括弧の中身の位置 [start, end) とのずれがこれ以内なら同じ箇所とみなす。 */
const BRACKET_SLACK = 2;

/** [start, end) に近い括弧の中身の位置。無ければ null。 */
function nearestBracket(text: string, start: number, end: number): [number, number] | null {
  const chars = Array.from(text);
  const stack: Array<[string, number]> = [];
  let best: [number, number] | null = null;
  chars.forEach((ch, i) => {
    if (BRACKETS[ch]) stack.push([BRACKETS[ch]!, i + 1]);
    else if (stack.length && stack[stack.length - 1]![0] === ch) {
      const open = stack.pop()![1];
      const off = Math.abs(open - start) + Math.abs(i - end);
      if (Math.abs(open - start) <= BRACKET_SLACK && Math.abs(i - end) <= BRACKET_SLACK && i > open
        && (!best || off < Math.abs(best[0] - start) + Math.abs(best[1] - end))) best = [open, i];
    }
  });
  return best;
}

/** 退避したコールを新しい行の本文に当てる。文言の分からないものは捨てる。 */
function restoreCalls(calls: readonly ArchivedCall[], text: string): Array<ArchivedCall & { anchorText: string }> {
  const out: Array<ArchivedCall & { anchorText: string }> = [];
  for (const c of calls) {
    const start = c.start ?? 0;
    const end = c.end ?? start;
    const anchorText = scalarSlice(text, start, end);
    if (typeof c.text === "string" && c.text) {
      // 退避時点で既にずれていたコール (stale) は印を残す。
      out.push({ ...c, anchorText: c.stale ? "" : anchorText });
    } else if (!c.stale && c.timing === "over" && end > start) {
      // 一緒に叫ぶ箇所は括弧で括られている。元の本文と 1〜2 字ずれることがあるので、近い括弧の中身に合わせる。
      // 近くに括弧が無ければ、どこまでが叫ぶ箇所か決められないので付けない。
      const span = nearestBracket(text, start, end);
      if (span) {
        const shout = scalarSlice(text, span[0], span[1]);
        out.push({ ...c, start: span[0], end: span[1], text: shout, anchorText: shout });
      }
    }
  }
  return out;
}

/**
 * 退避した注釈を新しい行に付け直す。1 行も付けられなければ null (何も変えない)。
 * 行 id は退避した元の id に戻す (端末ローカルのここ好き・タイミングの記録が再びつながる)。
 */
export function applyAnnotationArchive(
  lines: readonly LyricLineRow[],
  archived: readonly ArchivedLine[]
): LyricLineRow[] | null {
  if (!archived.length || new Set(archived.map((a) => a.id)).size !== archived.length) return null;
  const aligned = alignArchive(lines, archived);
  if (!aligned || aligned.size === 0) return null;
  const byIndex = new Map([...aligned].map(([a, i]) => [i, a]));
  const ids = new Set([...aligned.keys()].map((a) => a.id));

  return lines.map((line, i) => {
    const a = byIndex.get(i);
    if (!a) return ids.has(line.id) ? { ...line, id: "ll_" + crypto.randomUUID() } : line;
    const annotation = carryOverAnnotation({ clap: a.clap, calls: restoreCalls(a.calls ?? [], line.text) }, line.text);
    const { singers: _s, partBreaks: _p, layer: _l, ...rest } = line;
    return {
      ...rest,
      id: a.id,
      start_ms: a.start_ms ?? null,
      ...(a.layer ? { layer: a.layer } : {}),
      ...(a.singers?.length ? { singers: [...a.singers] } : {}),
      ...(a.partBreaks?.length ? { partBreaks: a.partBreaks.map((b) => ({ at: b.at, singers: [...b.singers] })) } : {}),
      clap: annotation.clap,
      calls: annotation.calls,
    };
  });
}

/** 退避したここ好きの数 ({行 id: 人数}) を、付け直した行にあるものだけ残して今の数に足す。 */
export function mergeArchivedLikes(
  current: Record<string, number>,
  archived: Record<string, number>,
  lines: readonly LyricLineRow[]
): Record<string, number> {
  const present = new Set(lines.map((l) => l.id));
  const out: Record<string, number> = {};
  for (const [id, n] of Object.entries(current)) if (present.has(id)) out[id] = n;
  for (const [id, n] of Object.entries(archived)) {
    if (present.has(id) && Number.isInteger(n) && n > 0) out[id] = (out[id] ?? 0) + n;
  }
  return out;
}

/** 退避したここ好きの JSON を読む。壊れていれば空。 */
function parseLikes(json: string | null): Record<string, number> {
  try {
    const v = JSON.parse(json ?? "{}");
    return v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, number> : {};
  } catch {
    return {};
  }
}

/**
 * storeLyrics から呼ぶ。まだ付け直していない退避があり、新しい行に合えば、付け直した行と
 * 同じ batch に積む文 (ここ好き・整備状況の数・退避の消し込み) を返す。無い・合わなければ null。
 * 呼び出し側は、行に利用者の注釈が無いとき (hasAnnotations が false) だけ呼ぶこと。
 */
export async function restoreFromArchive(
  db: D1Database,
  songId: string,
  lines: readonly LyricLineRow[]
): Promise<{ lines: LyricLineRow[]; statements: D1PreparedStatement[] } | null> {
  const row = await db.prepare(
    "SELECT lines_json, likes_json FROM lyric_annotation_archive WHERE song_id = ? AND restored_at IS NULL"
  ).bind(songId).first<{ lines_json: string; likes_json: string | null }>();
  if (!row) return null;
  let archived: ArchivedLine[];
  try {
    archived = JSON.parse(row.lines_json) as ArchivedLine[];
  } catch {
    return null;
  }
  const restored = applyAnnotationArchive(lines, Array.isArray(archived) ? archived : []);
  if (!restored) return null;

  const current = await db.prepare("SELECT likes_json FROM song_lyrics WHERE song_id = ?")
    .bind(songId).first<{ likes_json: string | null }>();
  const likes = mergeArchivedLikes(parseLikes(current?.likes_json ?? null), parseLikes(row.likes_json), restored);
  const partLines = restored.filter((l) => l.singers?.length || l.partBreaks?.length).length;
  const timedLines = restored.filter((l) => typeof l.start_ms === "number").length;
  const timedCalls = restored.reduce((n, l) => n + (l.calls ?? []).filter((c) => typeof c.startMs === "number").length, 0);
  const { callLines, callCount } = countCallAnnotations(restored);

  return {
    lines: restored,
    statements: [
      // song_lyrics の行は storeLyrics の最初の文で必ずできている (UPSERT)。
      db.prepare("UPDATE song_lyrics SET likes_json = ? WHERE song_id = ?").bind(JSON.stringify(likes), songId),
      db.prepare("UPDATE lyric_annotation_archive SET restored_at = datetime('now') WHERE song_id = ?").bind(songId),
      db.prepare(
        `INSERT INTO song_part_stats (song_id, part_lines, updated_at) VALUES (?, ?, datetime('now'))
         ON CONFLICT(song_id) DO UPDATE SET part_lines = excluded.part_lines`
      ).bind(songId, partLines),
      db.prepare(
        `INSERT INTO song_timing_stats (song_id, timed_lines, timed_calls) VALUES (?, ?, ?)
         ON CONFLICT(song_id) DO UPDATE SET timed_lines = excluded.timed_lines, timed_calls = excluded.timed_calls`
      ).bind(songId, timedLines, timedCalls),
      db.prepare(
        `INSERT INTO song_call_stats (song_id, call_lines, call_count) VALUES (?, ?, ?)
         ON CONFLICT(song_id) DO UPDATE SET call_lines = excluded.call_lines, call_count = excluded.call_count`
      ).bind(songId, callLines, callCount),
    ],
  };
}
