// apply.ts — Cron (scheduled) ハンドラ。
//
// 旧 submission-apply パイプライン (approved submission を CloudKit へ反映) は
// 即時オープン編集 (POST /edits, Phase 1-3) への移行と submissions/votes テーブル DROP (0014)
// により完全に廃止された。Cron に残る恒常タスクは rate_limits の日次掃除のみ。

export interface ApplyEnv {
  DB: D1Database;
}

/**
 * Cron 起動時の恒常メンテナンス。
 * 7 日以上前の rate_limits レコードを掃除する (テーブル肥大化防止)。
 */
export async function handleScheduled(env: ApplyEnv): Promise<void> {
  await env.DB.prepare(
    "DELETE FROM rate_limits WHERE date < date('now', '-7 days')"
  ).run();
}
