// apply.ts — Cron (scheduled) ハンドラ。
//
// 旧 submission-apply パイプライン (approved submission を CloudKit へ反映) は
// 即時オープン編集 (POST /edits, Phase 1-3) への移行と submissions/votes テーブル DROP (0014)
// により完全に廃止された。Cron に残る恒常タスクは保持期間の掃除と日次集計だけ。

export interface ApplyEnv {
  DB: D1Database;
}

/**
 * 1 日 1 回の恒常メンテナンス。
 *   - 7 日以上前の rate_limits レコードを掃除する (テーブル肥大化防止)。
 *   - 180 日以上前のコール編集履歴を掃除する (下記)。
 *   - song_tag_counts を数え直す (下記)。
 *
 * 5 分 cron から日次 cron に移したのは、rate_limits の DELETE が rows_read を
 * 食っていたため。date にインデックスが無かった頃は 1 回 1,006 行 (= 実質フルスキャン)
 * を 283 回/日 走らせて 285,000 行/日 を消費していた (実削除は 1 日 173 行)。
 * idx_rate_limits_date を張り、さらに頻度を 1/288 に落としてある。
 * ここに入っているのはいずれも保持期間の掃除と集計で、5 分精度は要らない。
 */
export async function handleScheduled(env: ApplyEnv): Promise<void> {
  await env.DB.prepare(
    "DELETE FROM rate_limits WHERE date < date('now', '-7 days')"
  ).run();

  // コール編集履歴 (migrations/0032_call_guide_stats) は「最近の編集」にしか使わない。
  // GET /calls/dashboard が読むのは常に直近 30 件なので、古い行は誰も見ない。
  // 無限に積むと荒らしで肥大しうるため 180 日で切る。
  await env.DB.prepare(
    "DELETE FROM call_edit_history WHERE at < datetime('now', '-180 days')"
  ).run();

  await refreshTagCounts(env);
}

/**
 * song_tag_counts (その曲に付いている有効タグの本数) を全曲ぶん数え直す。
 *
 * GET /songs/:id/similar のスコアの分母に使う値。タグ付け / 取り外しのときは
 * その曲だけ即時に更新している (routes/tags.ts の recountSongTags) が、
 * モデレーターがタグ自体を removed にした場合はそのタグが付いた全曲に効くので、
 * 日次でまとめて辻褄を合わせる。
 */
export async function refreshTagCounts(env: ApplyEnv): Promise<void> {
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO song_tag_counts (song_id, tag_count)
       SELECT s.song_id, COUNT(*)
         FROM song_tags s
         JOIN tags t ON t.id = s.tag_id AND t.status != 'removed'
        GROUP BY s.song_id
       ON CONFLICT(song_id) DO UPDATE SET tag_count = excluded.tag_count`
    ),
    // タグが 1 本も残っていない曲の行は残さない (分母は COALESCE で保険が効く)。
    env.DB.prepare(
      "DELETE FROM song_tag_counts WHERE song_id NOT IN (SELECT song_id FROM song_tags)"
    ),
  ]);
}
