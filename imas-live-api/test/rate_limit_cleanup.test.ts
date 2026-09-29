// IP の枠の掃除 (api_rate_limits) が、消す行だけを読むこと (表全体を走査しないこと)。
// 分のバケット (正の鍵) と日のバケット (負の鍵) を idx_api_rate_limits_bucket の範囲で引く。

import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { makeEnv, runScheduled } from "./support/worker";
import { exec, meterD1, rows } from "./support/d1";

const FIVE_MIN = "*/5 * * * *";
const DAILY = "17 15 * * *";

async function seed(): Promise<{ minute: number; day: number }> {
  const sec = Math.floor(Date.now() / 1000);
  const minute = Math.floor(sec / 60);
  const day = -Math.floor(sec / 86400);
  // 残る行: 今日の日のバケット 40 本と、今の分のバケット 40 本。
  for (let i = 0; i < 40; i++) {
    await exec("INSERT INTO api_rate_limits (ip, minute_bucket, count) VALUES (?, ?, 1), (?, ?, 1)",
      `lyrics:10.0.0.${i}`, day, `lyrics:10.0.0.${i}`, minute);
  }
  // 消える行: 2 日前の分のバケット 3 本と、前の日の日のバケット 3 本。
  for (let i = 0; i < 3; i++) {
    await exec("INSERT INTO api_rate_limits (ip, minute_bucket, count) VALUES (?, ?, 1), (?, ?, 1)",
      `lyrics:10.1.0.${i}`, minute - 2880, `lyrics:10.1.0.${i}`, day + 1);
  }
  return { minute, day };
}

function deleteReads(log: Array<{ sql: string; rowsRead: number; rowsWritten: number }>) {
  return log.filter((l) => l.sql.startsWith("DELETE FROM api_rate_limits"));
}

describe("api_rate_limits の掃除", () => {
  it("5 分 cron: 古い分のバケットだけを消し、読むのは消す行の分だけ", async () => {
    await seed();
    const m = meterD1(env.DB);
    await runScheduled(FIVE_MIN, makeEnv({ DB: m.db }));
    const [minuteDelete] = deleteReads(m.usage.log);
    expect(minuteDelete.rowsWritten).toBeGreaterThan(0);
    // 消す 3 行 + 範囲の端で止まるための 1 行。表の 83 行は読まない。
    expect(minuteDelete.rowsRead).toBeLessThanOrEqual(4);
    expect(await rows("SELECT * FROM api_rate_limits WHERE minute_bucket >= 0")).toHaveLength(40);
    expect(await rows("SELECT * FROM api_rate_limits WHERE minute_bucket < 0")).toHaveLength(43);
  });

  it("日次 cron: 前の日の日のバケットだけを消し、読むのは消す行の分だけ。今日の行は残す", async () => {
    const { day } = await seed();
    const m = meterD1(env.DB);
    await runScheduled(DAILY, makeEnv({ DB: m.db }));
    const deletes = deleteReads(m.usage.log);
    expect(deletes).toHaveLength(2);
    for (const d of deletes) expect(d.rowsRead).toBeLessThanOrEqual(4);
    const left = await rows<{ minute_bucket: number }>("SELECT minute_bucket FROM api_rate_limits WHERE minute_bucket < 0");
    expect(left).toHaveLength(40);
    expect(new Set(left.map((r) => r.minute_bucket))).toEqual(new Set([day]));
  });
});
