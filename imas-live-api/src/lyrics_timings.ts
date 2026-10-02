// lyrics_timings.ts — 歌詞行の再生位置 (start_ms) のドメインロジック。
//
// 再生位置は歌詞行 (song_lyrics.lines_json) の start_ms に入れる。別テーブルにしない理由は
// コールと同じ (migration 0027: 歌詞 1 曲の取得を D1 の行読み取り 1 回に収める)。
//
// 値はユーザーが Apple Music のフル再生を聴きながら行をタップして記録する (iOS の
// 「タイミングを記録」)。歌詞本文には触れない — ボディは行 ID と startMs だけ。
//
// このファイルは純粋関数だけを置く (D1 も Request も触らない)。routes/timings.ts が使う。

/** 1 曲の長さの上限。メドレーや長尺曲でも 20 分を超えるものは無い。 */
export const MAX_START_MS = 20 * 60 * 1000;

export type TimingsResult =
  | { ok: true; timings: Map<string, number | null> }
  | { ok: false; error: string };

/**
 * PUT /songs/:id/timings のボディを検証し、行 ID → startMs の対応に正規化する。
 *
 * ボディ: `{ lines: [{ id, startMs }] }`。PUT = 曲全体の全置換で、ボディに無い行は null に戻る。
 * `knownIds` はその曲の既存行 ID。知らない ID は 400 (行の追加・本文の改変はできない)。
 */
export function validateTimingsBody(body: unknown, knownIds: ReadonlySet<string>): TimingsResult {
  if (!body || typeof body !== "object") return { ok: false, error: "body must be an object" };
  const { lines } = body as Record<string, unknown>;
  if (!Array.isArray(lines)) return { ok: false, error: "lines must be an array" };
  if (lines.length > knownIds.size) return { ok: false, error: "too many lines" };

  const timings = new Map<string, number | null>();
  for (const raw of lines) {
    if (!raw || typeof raw !== "object") return { ok: false, error: "line must be an object" };
    // iOS の APIClient はキーを snake_case にして送る (startMs → start_ms)。両方を受ける。
    const r = raw as Record<string, unknown>;
    const id = r.id;
    const startMs = r.startMs !== undefined ? r.startMs : r.start_ms;
    if (typeof id !== "string" || !knownIds.has(id)) return { ok: false, error: "unknown line id" };
    if (timings.has(id)) return { ok: false, error: "duplicate line id" };
    if (startMs === null || startMs === undefined) {
      timings.set(id, null);
      continue;
    }
    if (typeof startMs !== "number" || !Number.isInteger(startMs) ||
        startMs < 0 || startMs > MAX_START_MS) {
      return { ok: false, error: "startMs must be an integer in range" };
    }
    timings.set(id, startMs);
  }
  return { ok: true, timings };
}
