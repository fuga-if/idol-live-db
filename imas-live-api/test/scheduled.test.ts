// cron (scheduled) の特性テスト。
//   - 5 分 cron: api_rate_limits の 1 日より古い分のバケットと、期限切れの引き継ぎコードを消す。
//     日のバケット (負の鍵) は消さない (Q-09: 消すと IP の日の上限が 5 分ごとに 0 に戻る)。
//   - 日次 cron (17 15 * * *): 上に加えて前の日までの日のバケット・rate_limits の 7 日超・
//     コール編集履歴の 180 日超を消し、song_tag_counts を数え直す。

import { describe, expect, it } from "vitest";
import { runScheduled } from "./support/worker";
import { exec, rows } from "./support/d1";

const FIVE_MIN = "*/5 * * * *";
const DAILY = "17 15 * * *";

const nowMinute = () => Math.floor(Date.now() / 60000);
const today = () => -Math.floor(Date.now() / 86400000);

async function seedRateBuckets() {
  const m = nowMinute();
  await exec(
    `INSERT INTO api_rate_limits (ip, minute_bucket, count) VALUES
       ('old', ?, 1), ('edge', ?, 1), ('recent', ?, 1), ('day', ?, 1), ('yesterday', ?, 1)`,
    m - 1441, m - 1440, m, today(), today() + 1
  );
}

async function seedTransferCodes() {
  const iso = (offsetMs: number) => new Date(Date.now() + offsetMs).toISOString();
  await exec(
    `INSERT INTO transfer_codes (code, user_id, payload, created_at, expires_at) VALUES
       ('EXPIRED', 'u', '{}', ?, ?), ('ALIVE', 'u', '{}', ?, ?)`,
    iso(-2 * 86400_000), iso(-60_000), iso(0), iso(86400_000)
  );
}

async function seedDailyTargets() {
  const date = (days: number) => new Date(Date.now() - days * 86400_000).toISOString().slice(0, 10);
  await exec(
    `INSERT INTO rate_limits (user_id, date, action, count) VALUES
       ('u', ?, 'edit', 1), ('u', ?, 'edit', 1)`,
    date(8), date(6)
  );
  await exec(
    `INSERT INTO call_edit_history (song_id, user_id, at, call_lines_before, call_lines_after,
                                    call_count_before, call_count_after)
     VALUES ('old', 'u', datetime('now', '-181 days'), 0, 1, 0, 1),
            ('new', 'u', datetime('now', '-179 days'), 0, 1, 0, 1)`
  );
  await exec("INSERT INTO tags (id, name, created_by, created_at, updated_at, status) VALUES ('t1', 't1', 'd', 1, 1, 'active'), ('t2', 't2', 'd', 1, 1, 'removed')");
  await exec("INSERT INTO song_tags (song_id, tag_id, vote_count) VALUES ('s1', 't1', 1), ('s1', 't2', 1), ('s2', 't2', 1)");
  await exec("INSERT INTO song_tag_counts (song_id, tag_count) VALUES ('s1', 5), ('gone', 3)");
}

describe("5 分 cron", () => {
  it("1 日より古い分のバケットだけを消す。日のバケット (負の鍵) は残す", async () => {
    await seedRateBuckets();
    await runScheduled(FIVE_MIN);
    expect((await rows("SELECT ip FROM api_rate_limits ORDER BY ip")).map((r) => r.ip))
      .toEqual(["day", "edge", "recent", "yesterday"]);
  });

  it("日次の掃除と数え直しはしない", async () => {
    await seedDailyTargets();
    await runScheduled(FIVE_MIN);
    expect(await rows("SELECT date FROM rate_limits")).toHaveLength(2);
    expect(await rows("SELECT song_id FROM call_edit_history")).toHaveLength(2);
    expect(await rows("SELECT song_id, tag_count FROM song_tag_counts ORDER BY song_id"))
      .toEqual([{ song_id: "gone", tag_count: 3 }, { song_id: "s1", tag_count: 5 }]);
  });
});

describe("日次 cron (17 15 * * *)", () => {
  it("5 分 cron の掃除に加えて、古い日次枠と履歴を消し、song_tag_counts を数え直す", async () => {
    await seedRateBuckets();
    await seedTransferCodes();
    await seedDailyTargets();
    await runScheduled(DAILY);

    // 前の日の日のバケットは消え、今日の分は残る。
    expect((await rows("SELECT ip FROM api_rate_limits ORDER BY ip")).map((r) => r.ip)).toEqual(["day", "edge", "recent"]);
    expect(await rows("SELECT code FROM transfer_codes")).toEqual([{ code: "ALIVE" }]);
    expect(await rows("SELECT date FROM rate_limits")).toHaveLength(1);
    expect(await rows("SELECT song_id FROM call_edit_history")).toEqual([{ song_id: "new" }]);
    // 削除済みタグは数えない。タグが 1 本も無い曲の行は消える。
    expect(await rows("SELECT song_id, tag_count FROM song_tag_counts ORDER BY song_id"))
      .toEqual([{ song_id: "s1", tag_count: 1 }]);
  });
});
