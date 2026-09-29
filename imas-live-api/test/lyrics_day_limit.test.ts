// 歌詞の IP の日の上限 (LYRICS_IP_LIMITS.perDay = 1,000) が効くこと (Q-09)。
//   - 単体の GET・歌詞検索・曲詳細の束ね (歌詞を同梱するとき) が同じ枠を使う
//   - 日の行は 5 分の掃除で消えない
//   - 1 リクエストあたりの IP 枠の読み書き行数 (api_rate_limits の文だけ)

import { env } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { LYRICS_IP_LIMITS } from "../src/routes/lyrics";
import { bearer, callJson, fetchWorker, makeEnv, request, runScheduled, TEST_IP } from "./support/worker";
import { exec, insertUser, meterD1, row } from "./support/d1";

const UID = "001094.day-limit";
const KEY = `lyrics:${TEST_IP}`;
const LINES = [{ id: "ll_1", ord: 0, kind: "lyric", text: "テスト", section: null, start_ms: null, clap: null, calls: [] }];

const sec = () => Math.floor(Date.now() / 1000);
const minuteBucket = () => Math.floor(sec() / 60);
const dayBucket = () => -Math.floor(sec() / 86400);

async function seedSong(songId: string) {
  await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json) VALUES (?, 'src', 'published', ?)",
    songId, JSON.stringify(LINES));
}

async function setDayCount(count: number) {
  await exec("INSERT INTO api_rate_limits (ip, minute_bucket, count) VALUES (?, ?, ?)", KEY, dayBucket(), count);
}

async function dayCount(): Promise<number | undefined> {
  return (await row<{ count: number }>(
    "SELECT count FROM api_rate_limits WHERE ip = ? AND minute_bucket = ?", KEY, dayBucket()
  ))?.count;
}

beforeEach(async () => {
  // 分・日の境目をまたがないよう時刻を止める。
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date("2026-09-23T03:00:10Z"));
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(UID);
});
afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("歌詞の日の上限", () => {
  it("単体の GET: 日の上限に達したら 429。それまでは数える", async () => {
    await seedSong("s1");
    await setDayCount(LYRICS_IP_LIMITS.perDay - 1);
    expect((await callJson("GET", "/songs/s1/lyrics")).status).toBe(200);
    expect(await dayCount()).toBe(LYRICS_IP_LIMITS.perDay);
    const limited = await callJson("GET", "/songs/s1/lyrics?again=1");
    expect(limited.status).toBe(429);
    expect(limited.body).toEqual({ error: "rate_limit_exceeded" });
    expect(await dayCount()).toBe(LYRICS_IP_LIMITS.perDay);
  });

  it("歌詞検索も同じ日の枠", async () => {
    await setDayCount(LYRICS_IP_LIMITS.perDay);
    expect((await callJson("GET", "/lyrics/search?q=テスト")).status).toBe(429);
  });

  it("曲詳細の束ね: 歌詞を同梱したら日の枠を数え、上限なら歌詞だけ null (全体は 200)", async () => {
    await seedSong("s2");
    const auth = await bearer(UID);
    const ok = await callJson("GET", "/songs/s2/detail", { headers: auth });
    expect(ok.status).toBe(200);
    expect(ok.body.lyrics).not.toBeNull();
    expect(await dayCount()).toBe(1);

    await exec("UPDATE api_rate_limits SET count = ? WHERE ip = ? AND minute_bucket = ?",
      LYRICS_IP_LIMITS.perDay, KEY, dayBucket());
    const limited = await callJson("GET", "/songs/s2/detail?again=1", { headers: auth });
    expect(limited.status).toBe(200);
    expect(limited.body.lyrics).toBeNull();
    expect(limited.body.tags).not.toBeNull();
  });

  it("日の行は 5 分の掃除で消えない", async () => {
    await seedSong("s3");
    await callJson("GET", "/songs/s3/lyrics");
    await runScheduled("*/5 * * * *");
    expect(await dayCount()).toBe(1);
  });
});

describe("IP 枠の読み書き行数 (api_rate_limits の文だけ)", () => {
  /** 1 リクエストぶんの、api_rate_limits に触る文の読み書き行数。 */
  async function rateUsage(path: string, headers: Record<string, string> = {}) {
    const m = meterD1(env.DB);
    const res = await fetchWorker(request("GET", path, { headers }), makeEnv({ DB: m.db }));
    await res.text();
    const log = m.usage.log.filter((l) => l.sql.includes("api_rate_limits"));
    return {
      status: res.status,
      read: log.reduce((n, l) => n + l.rowsRead, 0),
      written: log.reduce((n, l) => n + l.rowsWritten, 0),
    };
  }

  it.each([
    ["単体の GET", "lyrics", false],
    ["曲詳細の束ね", "detail", true],
  ] as const)("%s", async (_, kind, withAuth) => {
    const headers = withAuth ? await bearer(UID) : {};
    for (const id of ["a", "b", "c", "d"]) await seedSong(`${kind}_${id}`);

    // その日の最初: 分・日とも行が無い。
    expect(await rateUsage(`/songs/${kind}_a/${kind}`, headers)).toMatchObject({ read: 0, written: 6 });
    // 分をまたいだ 2 回目 (たまに開く人): 日の行だけある。
    await exec("DELETE FROM api_rate_limits WHERE minute_bucket = ?", minuteBucket());
    expect(await rateUsage(`/songs/${kind}_b/${kind}`, headers)).toMatchObject({ read: 2, written: 4 });
    // 同じ分の続けての要求: 分・日とも行がある。
    expect(await rateUsage(`/songs/${kind}_c/${kind}`, headers)).toMatchObject({ read: 4, written: 2 });
    // 日の上限: 数えずに断る (単体は 429、束ねは歌詞だけ外す)。
    await exec("UPDATE api_rate_limits SET count = ? WHERE minute_bucket = ?", LYRICS_IP_LIMITS.perDay, dayBucket());
    await exec("DELETE FROM api_rate_limits WHERE minute_bucket = ?", minuteBucket());
    expect(await rateUsage(`/songs/${kind}_d/${kind}`, headers))
      .toMatchObject({ status: kind === "lyrics" ? 429 : 200, read: 1, written: 0 });
  });
});
