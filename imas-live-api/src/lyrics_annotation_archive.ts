// lyrics_annotation_archive.ts — 歌詞を消したときに退避した注釈 (歌割・タイミング・コール・ここ好き) を、
// 歌詞が入り直したときに付け直す。
//
// 2026-10-06 に歌詞本文を全削除したとき、利用者が付けた注釈だけを行 id/ord で退避した
// (lyric_annotation_archive、migrations/0049)。投稿で歌詞が入り直しても storeLyrics は
// 「同じ曲の既存の行」からしか引き継がないので、退避分はどこからも読まれず歌割が消えたままだった。
//
// ⚠️ 退避には歌詞本文が無い (anchorText も持たない)。行が合っているかは本文で確かめられないので、
//    退避した全行が「同じ ord に lyric 行があり、コールの位置や途中の区切りがその行に収まる」
//    ときだけ付け直す。1 行でも外れたら何もしない (ずれた歌割を出すより、無い方がまし)。
// ⚠️ 本文由来で除去したコール (text が無いもの) は戻せないので捨てる。

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
  calls?: Array<{
    id?: string; start?: number; end?: number; text?: string | null;
    emphasis?: string; timing?: string; startMs?: number; stale?: boolean;
  }> | null;
}

/** 行に利用者の注釈が 1 つでもあるか。あれば退避分で上書きしない。 */
export function hasAnnotations(lines: readonly LyricLineRow[]): boolean {
  return lines.some((l) =>
    (l.start_ms ?? l.startMs ?? null) !== null || !!l.clap || !!l.calls?.length
    || !!l.singers?.length || !!l.partBreaks?.length || !!l.layer);
}

/**
 * 退避した注釈を新しい行に付け直す。合わなければ null (何も変えない)。
 * 行 id は退避した元の id に戻す (端末ローカルのここ好き・タイミングの記録が再びつながる)。
 */
export function applyAnnotationArchive(
  lines: readonly LyricLineRow[],
  archived: readonly ArchivedLine[]
): LyricLineRow[] | null {
  if (!archived.length) return null;
  const byOrd = new Map<number, ArchivedLine>();
  for (const a of archived) {
    const line = lines[a.ord];
    if (!line || line.kind !== a.kind || line.kind !== "lyric" || byOrd.has(a.ord)) return null;
    const length = scalarLength(line.text);
    for (const b of a.partBreaks ?? []) if (!(b.at > 0 && b.at < length)) return null;
    for (const c of a.calls ?? []) if ((c.end ?? c.start ?? 0) > length) return null;
    byOrd.set(a.ord, a);
  }
  const ids = new Set(archived.map((a) => a.id));
  if (ids.size !== archived.length) return null;

  return lines.map((line, i) => {
    const a = byOrd.get(i);
    if (!a) return ids.has(line.id) ? { ...line, id: "ll_" + crypto.randomUUID() } : line;
    // 退避に anchorText は無い。今の本文の同じ位置を当てる (行が合っていることは上で確かめた)。
    // 退避時点で既にずれていたコール (stale) は印を残す。
    const calls = (a.calls ?? [])
      .filter((c) => typeof c.text === "string" && c.text)
      .map((c) => ({ ...c, anchorText: c.stale ? "" : scalarSlice(line.text, c.start ?? 0, c.end ?? c.start ?? 0) }));
    const annotation = carryOverAnnotation({ clap: a.clap, calls }, line.text);
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
