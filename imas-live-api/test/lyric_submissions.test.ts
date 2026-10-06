// POST /songs/:id/lyric-submissions — 歌詞の投稿。確認待ちで預かり、本文は返さない。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { normalizeLyricText, validateSubmission } from "../src/routes/lyric_submissions";
import { bearer, callJson } from "./support/worker";
import { insertUser, row } from "./support/d1";

const UID = "001094.lsub";

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(UID);
});
afterEach(() => vi.restoreAllMocks());

describe("POST /songs/:id/lyric-submissions", () => {
  it("整えた本文を確認待ちで預かり、応答に本文を返さない", async () => {
    const r = await callJson("POST", "/songs/s1/lyric-submissions", {
      headers: await bearer(UID),
      body: { agreed_to_guideline: true, text: "\r\nきらめく \r\n\n\n\nステージ\n\n" },
    });
    expect(r.status).toBe(201);
    expect(r.body.status).toBe("pending");
    expect(JSON.stringify(r.body)).not.toContain("きらめく");
    expect(await row("SELECT song_id, user_id, body, line_count, status FROM lyric_submissions WHERE id = ?", r.body.id))
      .toEqual({ song_id: "s1", user_id: UID, body: "きらめく\n\nステージ", line_count: 3, status: "pending" });
    // 歌詞の公開テーブルには書かない
    expect(await row("SELECT count(*) AS n FROM song_lyrics")).toEqual({ n: 0 });
  });

  it("ガイドラインへの同意・本文が無いと 400、未ログインは 401", async () => {
    const ok = (text: string, agreed: unknown = true) => validateSubmission({ agreed_to_guideline: agreed, text }).ok;
    expect(ok("a", false)).toBe(false);
    expect(ok("a", "yes")).toBe(false);
    expect(ok(" \n ")).toBe(false);
    expect(ok("あ".repeat(8001))).toBe(false);
    expect(ok(Array(401).fill("a").join("\n"))).toBe(false);
    expect(ok("ｱｲﾄﾞﾙ")).toBe(false);
    expect(ok("a")).toBe(true);
    expect((await callJson("POST", "/songs/s1/lyric-submissions", { body: { agreed_to_guideline: true, text: "a" } })).status).toBe(401);
  });

  it("整え方はコアと同じ (字は変えない)", () => {
    expect(normalizeLyricText("\r\n\n  あいう　 \r\nかきく\n\n\n\nさしす\n\n")).toBe("  あいう\nかきく\n\nさしす");
  });
});
