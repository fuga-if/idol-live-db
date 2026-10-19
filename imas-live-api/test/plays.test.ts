// 再生回数 (POST /plays/batch) と全曲の数 (GET /community/song-stats)。ローカル D1 で入口から通す。

import { afterEach, describe, expect, it, vi } from "vitest";
import { callJson, device } from "./support/worker";
import { exec, row, rows } from "./support/d1";
import { jstWeekOf } from "../src/routes/plays";

afterEach(() => vi.useRealTimers());

async function send(plays: unknown, deviceId = "dev-a") {
  return callJson("POST", "/plays/batch", { headers: device(deviceId), body: { plays } });
}

describe("jstWeekOf", () => {
  it("JST の月曜始まり", () => {
    // 2026-10-19 (月) 00:00 JST = 10-18 15:00 UTC
    expect(jstWeekOf(Date.UTC(2026, 9, 18, 15, 0, 0))).toBe("2026-10-19");
    expect(jstWeekOf(Date.UTC(2026, 9, 18, 14, 59, 59))).toBe("2026-10-12");
    expect(jstWeekOf(Date.UTC(2026, 9, 25, 14, 59, 59))).toBe("2026-10-19");
  });
});

describe("POST /plays/batch", () => {
  it("端末 ID 必須。本文を検証する", async () => {
    expect((await callJson("POST", "/plays/batch", { body: { plays: [] } })).status).toBe(400);
    const cases: Array<[unknown, string]> = [
      [[], "plays must be a non-empty array"],
      ["x", "plays must be a non-empty array"],
      [[{ preview: 1 }], "song_id is required"],
      [[{ song_id: "s1", preview: -1 }], "preview and full must be non-negative integers"],
      [[{ song_id: "s1", full: 1.5 }], "preview and full must be non-negative integers"],
      [Array.from({ length: 501 }, (_, i) => ({ song_id: `s${i}`, preview: 1 })), "plays must be 500 items or less"],
    ];
    for (const [plays, message] of cases) {
      const res = await send(plays);
      expect(res.status, JSON.stringify(plays).slice(0, 80)).toBe(400);
      expect(res.body).toEqual({ error: message });
    }
  });

  it("曲ごとに足す。同じ曲が重なっていたら足し合わせ、0 だけの曲は書かない", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.UTC(2026, 9, 20, 3));
    const res = await send([
      { song_id: "s1", preview: 2 },
      { song_id: "s1", full: 1 },
      { song_id: "s2", preview: 0, full: 0 },
    ]);
    expect(res.body).toEqual({ accepted: 1 });
    await send([{ song_id: "s1", preview: 1, full: 1 }], "dev-b");
    expect(await rows("SELECT * FROM song_play_counts")).toEqual([
      {
        song_id: "s1",
        preview_count: 3,
        full_count: 2,
        week: "2026-10-19",
        week_preview: 3,
        week_full: 2,
        prev_week_preview: 0,
        prev_week_full: 0,
      },
    ]);
  });

  it("週が変わったら今週の数を前の週へ送り、2 週あいたら前の週は 0", async () => {
    vi.useFakeTimers({ toFake: ["Date"] });
    vi.setSystemTime(Date.UTC(2026, 9, 13, 3)); // 10-12 の週
    await send([{ song_id: "s1", preview: 4, full: 1 }]);
    vi.setSystemTime(Date.UTC(2026, 9, 20, 3)); // 10-19 の週
    await send([{ song_id: "s1", preview: 1 }]);
    expect(await row("SELECT week, week_preview, week_full, prev_week_preview, prev_week_full, preview_count FROM song_play_counts"))
      .toEqual({ week: "2026-10-19", week_preview: 1, week_full: 0, prev_week_preview: 4, prev_week_full: 1, preview_count: 5 });
    vi.setSystemTime(Date.UTC(2026, 10, 3, 3)); // 11-02 の週 (2 週あき)
    await send([{ song_id: "s1", full: 2 }]);
    expect(await row("SELECT week, week_preview, week_full, prev_week_preview, prev_week_full FROM song_play_counts"))
      .toEqual({ week: "2026-11-02", week_preview: 0, week_full: 2, prev_week_preview: 0, prev_week_full: 0 });
  });

  it("端末ごとに 1 日 30 回まで", async () => {
    // IP の分の枠 (30 回/分) に先に当たらないよう、その日の 30 回は表に入れておく
    const today = new Date().toISOString().slice(0, 10);
    await exec("INSERT INTO rate_limits (user_id, date, action, count) VALUES ('device:dev-c', ?, 'play_batch', 29)", today);
    expect((await send([{ song_id: "s1", preview: 1 }], "dev-c")).status).toBe(200);
    expect((await send([{ song_id: "s1", preview: 1 }], "dev-c")).status).toBe(429);
    expect((await send([{ song_id: "s1", preview: 1 }], "dev-d")).status).toBe(200);
  });
});

describe("GET /community/song-stats", () => {
  it("再生とお気に入りを曲ごとにまとめて返す。公開キャッシュ 30 分", async () => {
    await exec(
      `INSERT INTO song_play_counts VALUES ('s1', 5, 2, '2026-10-19', 1, 1, 3, 0)`
    );
    await exec("INSERT INTO song_favorites (song_id, count) VALUES ('s1', 4), ('s2', 1), ('s3', 0)");
    const res = await callJson("GET", "/community/song-stats");
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe("public, max-age=1800, stale-while-revalidate=3600");
    expect(res.body.plays_since).toBe("2026-10-20");
    expect(typeof res.body.generated_at).toBe("number");
    expect(res.body.songs).toEqual([
      {
        song_id: "s1",
        favorites: 4,
        preview: 5,
        full: 2,
        week: "2026-10-19",
        week_preview: 1,
        week_full: 1,
        prev_week_preview: 3,
        prev_week_full: 0,
      },
      { song_id: "s2", favorites: 1, preview: 0, full: 0 },
    ]);
  });
});

describe("GET /songs/:id/detail の counts", () => {
  it("その曲のお気に入りと再生回数", async () => {
    await exec(`INSERT INTO song_play_counts VALUES ('s1', 5, 2, '2026-10-19', 1, 1, 3, 0)`);
    await exec("INSERT INTO song_favorites (song_id, count) VALUES ('s1', 4)");
    expect((await callJson("GET", "/songs/s1/detail")).body.counts).toEqual({
      favorites: 4, preview: 5, full: 2, plays_since: "2026-10-20",
    });
    expect((await callJson("GET", "/songs/none/detail")).body.counts).toEqual({
      favorites: 0, preview: 0, full: 0, plays_since: "2026-10-20",
    });
  });
});
