// 歌詞を消したときに退避した注釈 (lyric_annotation_archive) を、歌詞が入り直したときに付け直す。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { applyAnnotationArchive } from "../src/lyrics_annotation_archive";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";

const UID = "001094.archive";
const ARCHIVE = [
  { id: "ll_old0", ord: 0, kind: "lyric", start_ms: 6592, singers: ["ml_a", "ml_b"] },
  { id: "ll_old2", ord: 2, kind: "lyric", start_ms: 19223, singers: ["ml_a"], partBreaks: [{ at: 2, singers: ["ml_b"] }],
    calls: [{ id: "c_1", start: 4, end: 4, text: "(Fu!)", emphasis: "normal", timing: "after" }] },
];

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(UID);
  await exec(
    "INSERT INTO lyric_annotation_archive (song_id, lines_json, likes_json, archived_at) VALUES ('s1', ?, ?, '2026-10-06')",
    JSON.stringify(ARCHIVE), JSON.stringify({ ll_old2: 3, ll_gone: 1 })
  );
});
afterEach(() => vi.restoreAllMocks());

const lyricLines = (texts: string[]) =>
  texts.map((text, ord) => ({ id: `ll_n${ord}`, ord, kind: text ? "lyric" : "blank", text, section: null, start_ms: null }));

describe("lyric_annotation_archive", () => {
  it("投稿で歌詞が入り直したら、歌割・タイミング・コール・ここ好きを元の行 id で付け直す", async () => {
    const r = await callJson("POST", "/songs/s1/lyric-submissions", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "いちばん\n\nにばんめ" },
    });
    expect(r.body.published).toBe(true);
    const lyrics = await callJson("GET", "/songs/s1/lyrics", { headers: await bearer(UID) });
    const [first, , third] = lyrics.body.lines;
    expect(first).toMatchObject({ id: "ll_old0", singers: ["ml_a", "ml_b"] });
    expect(third).toMatchObject({ id: "ll_old2", singers: ["ml_a"], partBreaks: [{ at: 2, singers: ["ml_b"] }] });
    expect(third.calls).toEqual([expect.objectContaining({ id: "c_1", text: "(Fu!)", start: 4, end: 4 })]);
    expect(third.calls[0].stale).toBeFalsy();
    const saved = await row<{ lines_json: string; likes_json: string }>("SELECT lines_json, likes_json FROM song_lyrics WHERE song_id = 's1'");
    expect(JSON.parse(saved!.lines_json).map((l: { start_ms: number | null }) => l.start_ms)).toEqual([6592, null, 19223]);
    expect(JSON.parse(saved!.likes_json)).toEqual({ ll_old2: 3 });
    expect(await row("SELECT part_lines FROM song_part_stats WHERE song_id = 's1'")).toEqual({ part_lines: 2 });
    expect(await row("SELECT timed_lines FROM song_timing_stats WHERE song_id = 's1'")).toEqual({ timed_lines: 2 });
    expect(await row("SELECT call_lines, call_count FROM song_call_stats WHERE song_id = 's1'")).toEqual({ call_lines: 1, call_count: 1 });
    expect((await row<{ restored_at: string | null }>("SELECT restored_at FROM lyric_annotation_archive WHERE song_id = 's1'"))!.restored_at).not.toBeNull();
  });

  it("行の並びが合わなければ何も付けない", async () => {
    await callJson("POST", "/songs/s1/lyric-submissions", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "いちばん\nにばんめ" },
    });
    const saved = JSON.parse((await row<{ lines_json: string }>("SELECT lines_json FROM song_lyrics WHERE song_id = 's1'"))!.lines_json);
    expect(saved.some((l: { singers?: string[] }) => l.singers)).toBe(false);
    expect(await row("SELECT restored_at FROM lyric_annotation_archive WHERE song_id = 's1'")).toEqual({ restored_at: null });
  });

  it("先に入っていた歌詞にも、管理の口から付け直せる", async () => {
    await exec("INSERT INTO song_lyrics (song_id, source, status, lines_json) VALUES ('s1', 'みんなの投稿', 'published', ?)",
      JSON.stringify(lyricLines(["いちばん", "", "にばんめ"])));
    await insertUser("001094.archive.admin", { isAdmin: true });
    expect((await callJson("POST", "/admin/lyrics/s1/restore-annotations", { headers: await bearer(UID) })).status).toBe(401);
    const r = await callJson("POST", "/admin/lyrics/s1/restore-annotations", { headers: await bearer("001094.archive.admin") });
    expect(r.body).toEqual({ songId: "s1", restored: true });
    const saved = JSON.parse((await row<{ lines_json: string }>("SELECT lines_json FROM song_lyrics WHERE song_id = 's1'"))!.lines_json);
    expect(saved.map((l: { id: string }) => l.id)).toEqual(["ll_old0", "ll_n1", "ll_old2"]);
  });

  it("区切りやコールが行に収まらない・種類が違うなら合わないとみなす", () => {
    const lines = lyricLines(["あ", "", "いう"]);
    expect(applyAnnotationArchive(lines, ARCHIVE as never)).toBeNull();
    expect(applyAnnotationArchive(lyricLines(["あ", "い", "ううううう"]), ARCHIVE as never)).not.toBeNull();
    expect(applyAnnotationArchive(lyricLines(["あ", "い", ""]), ARCHIVE as never)).toBeNull();
  });
});
