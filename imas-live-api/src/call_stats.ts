// call_stats.ts — コールガイドの「数え方」と、派生メタデータ (migrations/0032) の書き込み。
//
// 置き場所について: 数え方の定義はここが唯一の正。ルート (routes/calls.ts /
// routes/lyrics.ts) は「いつ数えるか」だけを決め、「何を数えるか」は持たない。
// lyrics_calls.ts と同じ立ち位置 (ルート非依存) だが、こちらは D1 の文を組み立てる
// ぶんだけ D1Database に依存する。Request / Response は触らない。
//
// ⚠️ この 2 表は「コール本文の第二の置き場所」ではない。件数と時刻と編集者しか持たない。
//    コール本文・アンカー文字列 (= 歌詞の断片) を足さないこと。足した瞬間に、
//    歌詞と同じ枠 (認証必須・1リクエスト1曲・no-store) の外に歌詞の断片が出る。

import type { LyricLineRow } from "./routes/lyrics";

/** コールガイドの整備量。API 応答の callLines / callCount と 1:1。 */
export interface CallCounts {
  /** clap か calls が付いている行数。0 は「コールガイド無し」。 */
  callLines: number;
  /** コール (calls[]) の総数。clap だけの行はここには入らない。 */
  callCount: number;
}

export const ZERO_CALL_COUNTS: CallCounts = { callLines: 0, callCount: 0 };

/**
 * 行配列からコール件数を数える。**数え方の定義はここが唯一の正**
 * (migration 0032 の backfill SQL はこの関数と同じ規則を SQL で書いたもの)。
 *
 * clap だけの行も callLines に数える: 「コールは無いが手拍子だけ指定した曲」も
 * 整備済みであって、未整備の曲と同じ扱いにすると一覧から消えてしまう。
 */
export function countCallAnnotations(lines: readonly LyricLineRow[]): CallCounts {
  let callLines = 0;
  let callCount = 0;
  for (const line of lines) {
    // 保存済みデータは検証済みだが、0027 以前の行や壊れた JSON も通るので防御的に見る。
    const calls = Array.isArray(line?.calls) ? line.calls.length : 0;
    const hasClap = line?.clap != null;
    if (calls > 0 || hasClap) callLines++;
    callCount += calls;
  }
  return { callLines, callCount };
}

/**
 * 履歴 1 行の要約を 4 つの数から組み立てる。edits.ts の buildSummary と同じ
 * **ASCII の機械文字列**で、監査・ログ用。表示文言はクライアントが数から組み立てる
 * (表示文字列をサーバに持たせると、文言を直すたびに過去の履歴が書き換わる/割れる)。
 *
 *   "calls 0->42, lines 0->18" / "calls 28->42, lines 10->18" / "calls 42->0, lines 18->0"
 */
export function buildCallEditSummary(before: CallCounts, after: CallCounts): string {
  return (
    `calls ${before.callCount}->${after.callCount}, ` +
    `lines ${before.callLines}->${after.callLines}`
  );
}

/**
 * 人がコールを編集したときの統計行を作る/更新する文 (batch 用)。
 *
 * 歌詞本文の UPDATE と**同じ batch に入れて**呼ぶこと。batch は 1 トランザクションなので、
 * 歌詞側だけ書けて統計が古いまま、という状態が構造的に起きない。
 *
 * @param uid 編集者 (users.id)。運用者トークン経由の一括投入は NULL
 *            (「みんなの編集」ではないので編集者として記録しない)。
 */
export function callStatsUpsertStatement(
  db: D1Database,
  songId: string,
  counts: CallCounts,
  uid: string | null
): D1PreparedStatement {
  return db
    .prepare(
      `INSERT INTO song_call_stats (song_id, call_lines, call_count, updated_at, updated_by_uid)
       VALUES (?, ?, ?, datetime('now'), ?)
       ON CONFLICT(song_id) DO UPDATE SET
         call_lines     = excluded.call_lines,
         call_count     = excluded.call_count,
         updated_at     = excluded.updated_at,
         updated_by_uid = excluded.updated_by_uid`
    )
    .bind(songId, counts.callLines, counts.callCount, uid);
}

/**
 * 歌詞差し替え (PUT /admin/lyrics/:song_id) に伴う数え直しの文 (batch 用)。
 *
 * **UPSERT ではなく UPDATE**。行が無い = その曲にはコールが一度も書かれていない、
 * ということなので、歌詞を入れ直しただけで「コールガイドのある曲」の表に
 * 0 件の行が生えるのは間違い (一覧の母集合が歌詞投入で汚れる)。
 *
 * updated_at / updated_by_uid も動かさない: 「最後にコールを書いた人」が
 * 歌詞の再投入で消えては履歴の意味が無くなる。
 */
export function syncCallStatsStatement(
  db: D1Database,
  songId: string,
  counts: CallCounts
): D1PreparedStatement {
  return db
    .prepare(
      "UPDATE song_call_stats SET call_lines = ?, call_count = ? WHERE song_id = ?"
    )
    .bind(counts.callLines, counts.callCount, songId);
}

/** 同じ人が続けて保存し直したときに 1 行にまとめる時間幅。 */
const MERGE_WINDOW = "-30 minutes";

/**
 * コール編集を履歴に積む。
 *
 * 同じ人が同じ曲を続けて保存し直すのは 1 回の作業なので、直近の履歴行が
 * **同じ人のもの**で 30 分以内なら、その行の after 側だけを更新して 1 行に見せる
 * (「保存を 10 回押した人」が最近の編集を埋め尽くすのを防ぐ。可読性の話であって
 *  荒らし対策ではない)。間に別の人の編集が挟まっていたら必ず新しい行を積む
 * — まとめてしまうと、他人の編集を自分の差分に飲み込んだ履歴になる。
 *
 * ⚠️ before 側は最初の保存の値のまま残す。まとめた行の差分は「作業前 → 現在」を指す。
 *
 * 呼び出し側は try/catch で包むこと。履歴は副次データなので、書けなくても
 * ユーザーの保存を失敗扱いにしない (routes/lyrics.ts の索引更新と同じ方針)。
 */
export async function appendCallEditHistory(
  db: D1Database,
  songId: string,
  uid: string,
  before: CallCounts,
  after: CallCounts
): Promise<void> {
  // 直近行は「曲ごとの最新」を id 降順で 1 行だけ見る (idx_call_edit_history_song)。
  // user_id の一致を副問い合わせの中ではなく外側の条件に置くのが要点:
  //   中に入れると「自分の最新行」を拾ってしまい、間に挟まった他人の編集を無視して
  //   まとめてしまう。外に置けば、直近が他人ならヒット 0 件 → 新規 INSERT になる。
  const merged = await db
    .prepare(
      `UPDATE call_edit_history
          SET at = datetime('now'),
              call_lines_after = ?,
              call_count_after = ?
        WHERE id = (SELECT id FROM call_edit_history
                     WHERE song_id = ? ORDER BY id DESC LIMIT 1)
          AND user_id = ?
          AND at >= datetime('now', '${MERGE_WINDOW}')`
    )
    .bind(after.callLines, after.callCount, songId, uid)
    .run();
  if (merged.meta.changes > 0) return;

  await db
    .prepare(
      `INSERT INTO call_edit_history
         (song_id, user_id, at, call_lines_before, call_lines_after,
          call_count_before, call_count_after)
       VALUES (?, ?, datetime('now'), ?, ?, ?, ?)`
    )
    .bind(
      songId,
      uid,
      before.callLines,
      after.callLines,
      before.callCount,
      after.callCount
    )
    .run();
}

/**
 * 保存前後でコール注釈が変わっていないか。
 *
 * 無変更の保存 (編集画面を開いて何もせず保存する等) で履歴を積むと、「最近の編集」が
 * 中身の無い行で埋まる。JSON 文字列の一致だけでは、キー順や省略キーの違いで
 * 「変わっていないのに変わった」と判定されうるので、注釈の中身どうしも突き合わせる。
 *
 * 件数の一致だけでは足りない: コール文言だけを直した編集 (件数は同じ) は本物の編集なので、
 * text / emphasis / timing / 位置まで見て初めて「無変更」と言える。
 */
export function isCallAnnotationUnchanged(
  before: readonly LyricLineRow[],
  after: readonly LyricLineRow[]
): boolean {
  if (before.length !== after.length) return false;
  for (let i = 0; i < before.length; i++) {
    if (!sameAnnotation(before[i], after[i])) return false;
  }
  return true;
}

function sameAnnotation(a: LyricLineRow, b: LyricLineRow): boolean {
  if (a?.id !== b?.id) return false;
  if ((a?.clap ?? null) !== (b?.clap ?? null)) return false;
  const ac = Array.isArray(a?.calls) ? a.calls : [];
  const bc = Array.isArray(b?.calls) ? b.calls : [];
  if (ac.length !== bc.length) return false;
  for (let i = 0; i < ac.length; i++) {
    // call の id は保存のたびにサーバが採番しうる (クライアントが送らなければ新 UUID)。
    // 内容が同じなら同じ編集結果なので、id は比較に入れない。
    if (
      ac[i]?.start !== bc[i]?.start ||
      ac[i]?.end !== bc[i]?.end ||
      ac[i]?.text !== bc[i]?.text ||
      ac[i]?.emphasis !== bc[i]?.emphasis ||
      ac[i]?.timing !== bc[i]?.timing
    ) {
      return false;
    }
  }
  return true;
}
