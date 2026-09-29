// scheduled.ts — cron (scheduled) の掃除と集計。
//
// 旧 submission-apply パイプライン (approved submission を CloudKit へ反映) は
// 即時オープン編集 (POST /edits) への移行と submissions/votes テーブル DROP (0014) で廃止済み。
// cron に残っているのは保持期間の掃除と日次の集計だけ。
//
// タスクは互いに独立している (触る表が違い、どれも冪等)。1 つが失敗しても残りは走らせ、
// 失敗は 1 行の JSON (event: "cron_task_failed") でログに出す。最後に失敗をまとめて投げ直すので、
// cron の実行としても失敗が記録される。

import { postDiscordDigest } from "./discord_digest";
import { postPollResults } from "./discord_poll_results";
import { createLiveThreads } from "./discord_live_threads";
import { postAppRelease, postDevWeekly } from "./discord_releases";
import type { Env } from "./env";

/**
 * 日次メンテナンス用の cron 式。wrangler.jsonc の crons と 1 文字でも
 * ずれると日次タスクが一生走らないので、両方を触るときは必ず対で直すこと。
 */
export const DAILY_CRON = "17 15 * * *";

// DB 以外 (Discord / CloudKit の設定) は通知のタスクだけが読む。無ければそのタスクは何もしない。
type ScheduledEnv = Pick<Env, "DB"> & Partial<Env>;

interface CronTask {
  /** ログに出す名前。 */
  name: string;
  run: (env: ScheduledEnv) => Promise<unknown>;
}

/**
 * 5 分ごと (日次の回も含む) に回すもの。インデックスが効いていて 1 回あたり数行しか読まない掃除だけ。
 * フルスキャン気味の掃除 (rate_limits) は日次に分けてある。
 */
const EVERY_RUN: CronTask[] = [
  {
    name: "api_rate_limits",
    // 1 日より古い分のバケット (正の鍵)。日のバケット (負の鍵) はここでは消さない —
    // 消すと IP の日の上限 (歌詞の 1,000/日) が 5 分ごとに 0 に戻って効かなくなる。
    // idx_api_rate_limits_bucket の範囲で引くので、読むのは消す行と範囲の端の 1 行だけ。
    run: (env) =>
      env.DB.prepare("DELETE FROM api_rate_limits WHERE minute_bucket >= 0 AND minute_bucket < ?")
        .bind(Math.floor(Date.now() / 1000 / 60) - 1440)
        .run(),
  },
  {
    name: "transfer_codes",
    // 期限切れの引き継ぎコード。
    run: (env) =>
      env.DB.prepare("DELETE FROM transfer_codes WHERE expires_at < ?")
        .bind(new Date().toISOString())
        .run(),
  },
  {
    name: "discord_oauth_states",
    // 期限切れの Discord / GitHub の OAuth state (routes/discord.ts)。
    run: (env) =>
      env.DB.prepare("DELETE FROM discord_oauth_states WHERE expires_at < ?")
        .bind(new Date().toISOString())
        .run(),
  },
  {
    name: "discord_digest",
    // #更新通知 へのまとめ投稿。rowid の範囲で新しい行だけ読む (discord_digest.ts)。
    run: postDiscordDigest,
  },
  {
    name: "discord_poll_results",
    // 締め切ったお題の結果を #投票結果 へ。idx_polls_status_ends の範囲で新しく締まった分だけ読む。
    run: postPollResults,
  },
  {
    name: "discord_app_release",
    // App Store に新しいバージョンが出たら #お知らせ へ (discord_releases.ts)。D1 は位置 1 行だけ。
    run: postAppRelease,
  },
];

/**
 * 1 日 1 回の恒常メンテナンス。
 *
 * 5 分 cron から日次 cron に移したのは、rate_limits の DELETE が rows_read を
 * 食っていたため。date にインデックスが無かった頃は 1 回 1,006 行 (= 実質フルスキャン)
 * を 283 回/日 走らせて 285,000 行/日 を消費していた (実削除は 1 日 173 行)。
 * idx_rate_limits_date を張り、さらに頻度を 1/288 に落としてある。
 * ここに入っているのはいずれも保持期間の掃除と集計で、5 分精度は要らない。
 */
const DAILY: CronTask[] = [
  {
    name: "discord_live_threads",
    // 今日 (JST) の公演ごとに #ライブ実況・感想 にスレッドを立てる (discord_live_threads.ts)。
    run: (env) => createLiveThreads(env),
  },
  {
    name: "discord_dev_weekly",
    // JST の月曜だけ、develop に入った変更を #開発中 へまとめる (discord_releases.ts)。
    run: (env) => postDevWeekly(env),
  },
  {
    name: "api_rate_limits_days",
    // 前の日までの日のバケット (負の鍵 -floor(秒/86400))。今日の行 (-今日) は残す。
    // 前の日の行は -今日 より大きい負の数なので、この範囲 (索引で引く) に入る。
    run: (env) =>
      env.DB.prepare("DELETE FROM api_rate_limits WHERE minute_bucket < 0 AND minute_bucket > ?")
        .bind(-Math.floor(Date.now() / 1000 / 86400))
        .run(),
  },
  {
    name: "rate_limits",
    // 7 日以上前の日次枠 (テーブル肥大化防止)。
    run: (env) => env.DB.prepare("DELETE FROM rate_limits WHERE date < date('now', '-7 days')").run(),
  },
  {
    name: "call_edit_history",
    // コール編集履歴 (migrations/0032_call_guide_stats) は「最近の編集」にしか使わない。
    // GET /calls/dashboard が読むのは常に直近 30 件なので、古い行は誰も見ない。
    // 無限に積むと荒らしで肥大しうるため 180 日で切る。
    run: (env) => env.DB.prepare("DELETE FROM call_edit_history WHERE at < datetime('now', '-180 days')").run(),
  },
  { name: "song_tag_counts", run: refreshTagCounts },
];

/** cron の 1 回ぶん。cron 式が日次なら日次のタスクも走らせる。 */
export async function runScheduledTasks(cron: string, env: ScheduledEnv): Promise<void> {
  const tasks = cron === DAILY_CRON ? [...EVERY_RUN, ...DAILY] : EVERY_RUN;
  // async で包み、同期的に投げたタスクも他を止めずに rejected として受ける。
  const results = await Promise.allSettled(tasks.map(async (task) => task.run(env)));
  const failures: unknown[] = [];
  results.forEach((result, i) => {
    if (result.status === "fulfilled") return;
    failures.push(result.reason);
    console.error(JSON.stringify({
      event: "cron_task_failed",
      cron,
      task: tasks[i].name,
      error: result.reason instanceof Error ? result.reason.message : String(result.reason),
    }));
  });
  if (failures.length > 0) throw new AggregateError(failures, `${failures.length} cron task(s) failed`);
}

/**
 * song_tag_counts (その曲に付いている有効タグの本数) を全曲ぶん数え直す。
 *
 * GET /songs/:id/similar のスコアの分母に使う値。タグ付け / 取り外しのときは
 * その曲だけ即時に更新している (routes/tags.ts の recountSongTags) が、
 * モデレーターがタグ自体を removed にした場合はそのタグが付いた全曲に効くので、
 * 日次でまとめて辻褄を合わせる。
 */
export async function refreshTagCounts(env: ScheduledEnv): Promise<void> {
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
