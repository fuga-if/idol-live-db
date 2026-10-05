// GET /lyrics/annotations: コール・タイミングがある曲の id を song_id 順にページで全件返す。
import { beforeEach, describe, expect, it } from "vitest";
import { callJson } from "./support/worker";
import { exec } from "./support/d1";

beforeEach(async () => {
  await exec("INSERT INTO song_call_stats (song_id, call_lines, call_count) VALUES ('a', 3, 4), ('b', 0, 0), ('c', 1, 1)");
  await exec("INSERT INTO song_timing_stats (song_id, timed_lines, timed_calls) VALUES ('c', 10, 0), ('d', 5, 1), ('e', 0, 0)");
  await exec("INSERT INTO song_part_stats (song_id, part_lines) VALUES ('d', 4), ('f', 0)");
});

describe("GET /lyrics/annotations", () => {
  it("両方を合わせて id 順に、ページを辿って全件取れる", async () => {
    const first = await callJson("GET", "/lyrics/annotations?limit=2");
    expect(first.status).toBe(200);
    expect(first.body).toEqual({
      songs: [{ songId: "a", calls: true, timings: false, parts: false }, { songId: "c", calls: true, timings: true, parts: false }],
      next: "c",
    });
    const second = await callJson("GET", "/lyrics/annotations?limit=2&after=c");
    expect(second.body).toEqual({ songs: [{ songId: "d", calls: false, timings: true, parts: true }], next: null });
  });

  it("不正な limit は 400", async () => {
    expect((await callJson("GET", "/lyrics/annotations?limit=0")).status).toBe(400);
  });
});
