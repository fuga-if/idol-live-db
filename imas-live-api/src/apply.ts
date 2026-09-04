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
 *   - 7 日以上前の rate_limits レコードを掃除する (テーブル肥大化防止)。
 *   - 180 日以上前のコール編集履歴を掃除する (下記)。
 */
export async function handleScheduled(env: ApplyEnv): Promise<void> {
  await env.DB.prepare(
    "DELETE FROM rate_limits WHERE date < date('now', '-7 days')"
  ).run();

  // コール編集履歴 (migrations/0032) は「最近の編集」にしか使わない。
  // GET /calls/dashboard が読むのは常に直近 30 件なので、古い行は誰も見ない。
  // 無限に積むと荒らしで肥大しうるため 180 日で切る。
  await env.DB.prepare(
    "DELETE FROM call_edit_history WHERE at < datetime('now', '-180 days')"
  ).run();
}
