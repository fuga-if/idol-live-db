// apply.ts — Cron (scheduled) ハンドラ。
//
// 旧 submission-apply パイプライン (approved submission を CloudKit へ反映) は
// 即時オープン編集 (POST /edits, Phase 1-3) への移行と submissions/votes テーブル DROP (0014)
// により完全に廃止された。Cron に残る恒常タスクは rate_limits の日次掃除のみ。

export interface ApplyEnv {
  DB: D1Database;
}

/**
 * 1 日 1 回の恒常メンテナンス。
 * 7 日以上前の rate_limits レコードを掃除する (テーブル肥大化防止)。
 *
 * 5 分 cron から日次 cron に移したのは、この DELETE が rows_read を食っていたため。
 * date にインデックスが無かった頃は 1 回 1,006 行 (= 実質フルスキャン) を
 * 283 回/日 走らせて 285,000 行/日 を消費していた (実削除は 173 行)。
 * 0032 で idx_rate_limits_date を張り、さらに頻度を 1/288 に落としてある。
 * 7 日保持の掃除に 5 分精度は要らない。
 */
export async function handleScheduled(env: ApplyEnv): Promise<void> {
  await env.DB.prepare(
    "DELETE FROM rate_limits WHERE date < date('now', '-7 days')"
  ).run();
}
