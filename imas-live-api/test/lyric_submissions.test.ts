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
      body: { source_kind: "booklet", source_note: " 初回限定盤 ", attested_no_copy: true, text: "\r\nきらめく \r\n\n\n\nステージ\n\n" },
    });
    expect(r.status).toBe(201);
    expect(r.body.status).toBe("pending");
    expect(JSON.stringify(r.body)).not.toContain("きらめく");
    expect(await row("SELECT song_id, user_id, source_kind, source_note, body, line_count, status FROM lyric_submissions WHERE id = ?", r.body.id))
      .toEqual({ song_id: "s1", user_id: UID, source_kind: "booklet", source_note: "初回限定盤", body: "きらめく\n\nステージ", line_count: 3, status: "pending" });
    // 歌詞の公開テーブルには書かない
    expect(await row("SELECT count(*) AS n FROM song_lyrics")).toEqual({ n: 0 });
  });

  it("入力元・転載していない確認・本文が無いと 400、未ログインは 401", async () => {
    expect(validateSubmission({ source_kind: "site", attested_no_copy: true, text: "a" }).ok).toBe(false);
    expect(validateSubmission({ source_kind: "listening", attested_no_copy: true, text: "a" }).ok).toBe(false);
    expect(validateSubmission({ source_kind: "official", attested_no_copy: false, text: "a" }).ok).toBe(false);
    expect(validateSubmission({ source_kind: "official", attested_no_copy: true, text: " \n " }).ok).toBe(false);
    expect(validateSubmission({ source_kind: "official", attested_no_copy: true, text: "あ".repeat(8001) }).ok).toBe(false);
    expect(validateSubmission({ source_kind: "official", attested_no_copy: true, text: Array(401).fill("a").join("\n") }).ok).toBe(false);
    expect(validateSubmission({ source_kind: "official", attested_no_copy: true, text: "ｱｲﾄﾞﾙ" }).ok).toBe(false);
    expect(validateSubmission({ source_kind: "official", attested_no_copy: true, text: "a" }).ok).toBe(true);
    expect((await callJson("POST", "/songs/s1/lyric-submissions", { body: { source_kind: "booklet", attested_no_copy: true, text: "a" } })).status).toBe(401);
  });

  it("整え方はコアと同じ (字は変えない)", () => {
    expect(normalizeLyricText("\r\n\n  あいう　 \r\nかきく\n\n\n\nさしす\n\n")).toBe("  あいう\nかきく\n\nさしす");
  });
});
