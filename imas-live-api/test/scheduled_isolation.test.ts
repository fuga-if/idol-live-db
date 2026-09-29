// cron のタスクは互いに独立している。1 つが失敗しても残りは走り、失敗は JSON 1 行でログに出す。
// 最後に失敗をまとめて投げ直す (cron の実行としても失敗が記録される)。

import { env } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { makeEnv, runScheduled } from "./support/worker";
import { exec, rows } from "./support/d1";

const FIVE_MIN = "*/5 * * * *";
const DAILY = "17 15 * * *";

/** sql に needle を含む文だけ失敗させる D1。 */
function failingOn(needle: string): D1Database {
  return {
    ...env.DB,
    prepare: (sql: string) => {
      if (sql.includes(needle)) throw new Error(`D1_ERROR: boom (${needle})`);
      return env.DB.prepare(sql);
    },
    batch: env.DB.batch.bind(env.DB),
  } as unknown as D1Database;
}

function captureErrors(): string[] {
  const lines: string[] = [];
  vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => void lines.push(args.map(String).join(" ")));
  return lines;
}

afterEach(() => vi.restoreAllMocks());

describe("cron のタスクの独立", () => {
  it("引き継ぎコードの掃除が失敗しても、分のバケットは消える。失敗は JSON でログに出て、最後に投げる", async () => {
    const minute = Math.floor(Date.now() / 60000);
    await exec("INSERT INTO api_rate_limits (ip, minute_bucket, count) VALUES ('old', ?, 1)", minute - 1441);
    const errors = captureErrors();

    await expect(runScheduled(FIVE_MIN, makeEnv({ DB: failingOn("transfer_codes") }))).rejects.toThrow();

    expect(await rows("SELECT * FROM api_rate_limits")).toEqual([]);
    expect(errors.map((l) => JSON.parse(l))).toEqual([
      { event: "cron_task_failed", cron: FIVE_MIN, task: "transfer_codes", error: "D1_ERROR: boom (transfer_codes)" },
    ]);
  });

  it("日次: rate_limits の掃除が失敗しても、履歴の掃除とタグ数の数え直しは走る", async () => {
    await exec(
      `INSERT INTO call_edit_history (song_id, user_id, at, call_lines_before, call_lines_after,
                                      call_count_before, call_count_after)
       VALUES ('old', 'u', datetime('now', '-181 days'), 0, 1, 0, 1)`
    );
    await exec("INSERT INTO song_tag_counts (song_id, tag_count) VALUES ('gone', 3)");
    const errors = captureErrors();

    await expect(runScheduled(DAILY, makeEnv({ DB: failingOn("FROM rate_limits") }))).rejects.toThrow();

    expect(await rows("SELECT * FROM call_edit_history")).toEqual([]);
    expect(await rows("SELECT * FROM song_tag_counts")).toEqual([]);
    expect(errors.map((l) => JSON.parse(l).task)).toEqual(["rate_limits"]);
  });
});
