// レート制限の特性テスト。
//   - ユーザー/主体ごとの日次枠 (rate_limits): 429 は使用量と reset_at と Retry-After を返す。
//   - IP の分の枠 (api_rate_limits): 成功したリクエストだけを数える。429 は Retry-After: 60。

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { checkRateLimit } from "../src/rate_limit";
import { call, callJson, device } from "./support/worker";
import { exec, row } from "./support/d1";
import { env } from "cloudflare:test";

describe("checkRateLimit (日次枠)", () => {
  it("呼ぶたびに +1 し、上限までは allowed。翌 UTC 0 時に戻る", async () => {
    const results = [];
    for (let i = 0; i < 4; i++) results.push(await checkRateLimit(env.DB, "u1", "profile"));
    expect(results.map((r) => [r.allowed, r.used, r.limit])).toEqual([
      [true, 1, 3], [true, 2, 3], [true, 3, 3], [false, 4, 3],
    ]);
    const reset = new Date(results[0].reset_at);
    expect(reset.getUTCHours()).toBe(0);
    expect(reset.getTime()).toBeGreaterThan(Date.now());
    expect(reset.getTime() - Date.now()).toBeLessThanOrEqual(86400_000);
    // 主体と action ごとに別枠。
    expect((await checkRateLimit(env.DB, "u2", "profile")).used).toBe(1);
    expect((await checkRateLimit(env.DB, "u1", "poll")).used).toBe(1);
  });
});

/** 分の境目をまたいで数が戻らないよう、時計を 1 分の途中に止める (D1 の時刻には効かない)。 */
function freezeClock() {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(new Date("2026-09-23T10:00:05Z"));
  });
  afterEach(() => vi.useRealTimers());
}

describe("IP の分の枠 (端末集計の書き込み)", () => {
  freezeClock();

  async function favorite(i: number, ip = "198.51.100.1") {
    return call("POST", "/favorites/toggle", {
      headers: { ...device(`dev-${i}`), "CF-Connecting-IP": ip },
      body: { song_id: `s${i}`, value: true },
    });
  }

  it("1 分に 30 回まで。31 回目は 429 と Retry-After: 60。別の IP は別枠", async () => {
    for (let i = 0; i < 30; i++) expect((await favorite(i)).status).toBe(200);
    const limited = await favorite(30);
    expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBe("60");
    expect(await limited.json()).toEqual({ error: "rate_limit_exceeded" });
    expect((await favorite(31, "198.51.100.2")).status).toBe(200);
  });

  it("ペンライトとタグの書き込みも同じ枠を使う", async () => {
    for (let i = 0; i < 29; i++) expect((await favorite(i)).status).toBe(200);
    const penlight = await call("POST", "/penlight/vote", {
      headers: { ...device("dev-p"), "CF-Connecting-IP": "198.51.100.1" },
      body: { song_id: "s1", colors: ["#FF0000"] },
    });
    expect(penlight.status).toBe(200);
    const tag = await call("POST", "/tags", {
      headers: { ...device("dev-t"), "CF-Connecting-IP": "198.51.100.1" },
      body: { name: "limited" },
    });
    expect(tag.status).toBe(429);
  });

  it("本文が不正で 400 になったリクエストは数えない", async () => {
    for (let i = 0; i < 40; i++) {
      const res = await call("POST", "/favorites/toggle", {
        headers: { ...device("dev-x"), "CF-Connecting-IP": "198.51.100.1" },
        body: { song_id: "s1", value: "yes" },
      });
      expect(res.status).toBe(400);
    }
    expect((await favorite(0)).status).toBe(200);
  });
});

describe("IP の分の枠 (歌詞)", () => {
  freezeClock();
  // 歌詞を返すたびに出る lyrics_read のログで出力が埋まるので黙らせる。
  beforeEach(() => void vi.spyOn(console, "log").mockImplementation(() => {}));
  afterEach(() => vi.restoreAllMocks());

  const LINES = JSON.stringify([{ id: "ll_1", ord: 0, kind: "lyric", text: "てすと", section: null }]);

  async function lyrics(songId: string, ip = "198.51.100.9") {
    return call("GET", `/songs/${songId}/lyrics`, { headers: { "CF-Connecting-IP": ip } });
  }

  it("1 分に 120 回まで (会場の NAT 向けに既定より広い)。121 回目は 429", async () => {
    await exec("INSERT INTO song_lyrics (song_id, status, lines_json) VALUES ('s1', 'published', ?)", LINES);
    for (let i = 0; i < 120; i++) expect((await lyrics("s1")).status).toBe(200);
    const limited = await lyrics("s1");
    expect(limited.status).toBe(429);
    expect(limited.headers.get("Retry-After")).toBe("60");
  });

  it("歌詞の無い曲 (404) は数えない", async () => {
    await exec("INSERT INTO song_lyrics (song_id, status, lines_json) VALUES ('s1', 'published', ?)", LINES);
    for (let i = 0; i < 130; i++) expect((await lyrics("none")).status).toBe(404);
    expect((await lyrics("s1")).status).toBe(200);
  });
});

describe("日次枠の 429 の形 (rateLimitResponse)", () => {
  it("error / limit / used / reset_at と、翌 UTC 0 時までの Retry-After", async () => {
    await exec(
      "INSERT INTO rate_limits (user_id, date, action, count) VALUES ('ip:198.51.100.3', ?, 'auth_login', 500)",
      new Date().toISOString().slice(0, 10)
    );
    const res = await callJson("POST", "/auth/login", { headers: { "CF-Connecting-IP": "198.51.100.3" }, body: {} });
    expect(res.status).toBe(429);
    expect(Object.keys(res.body).sort()).toEqual(["error", "limit", "reset_at", "used"]);
    const retryAfter = Number(res.res.headers.get("Retry-After"));
    const untilReset = Math.ceil((new Date(res.body.reset_at).getTime() - Date.now()) / 1000);
    expect(Math.abs(retryAfter - untilReset)).toBeLessThanOrEqual(2);
    expect(await row("SELECT count FROM rate_limits WHERE action = 'auth_login'")).toEqual({ count: 501 });
  });
});
