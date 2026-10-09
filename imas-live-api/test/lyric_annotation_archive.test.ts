// 歌詞を消したときに退避した注釈 (lyric_annotation_archive) を、歌詞が入り直したときに付け直す。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { alignArchive, applyAnnotationArchive } from "../src/lyrics_annotation_archive";
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

  it("どう並べても行に収まらなければ何も付けない", async () => {
    await callJson("POST", "/songs/s1/lyric-submissions", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "いち\nに" },
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

  it("空行の置き方が違っても、行末の追っかけと行の長さで突き合わせる。決めきれない行は付けない", () => {
    // 元の 50・52・53 行目の行末に追っかけ。投稿では空行が 1 つ少なく、1 行ずつ前にある。
    const archived = [50, 52, 53].map((ord, i) => ({
      id: `ll_o${ord}`, ord, kind: "lyric",
      calls: [{ id: `c${ord}`, start: [9, 13, 15][i], end: [9, 13, 15][i], text: "（ウォー）", timing: "after" }],
    }));
    const texts = Array.from({ length: 60 }, () => "あああああああああああああああああああ");
    texts[49] = "あ".repeat(9); texts[50] = ""; texts[51] = "あ".repeat(13); texts[52] = "あ".repeat(15);
    const aligned = alignArchive(lyricLines(texts), archived as never)!;
    expect(archived.map((a) => aligned.get(a as never))).toEqual([49, 51, 52]);

    // ずれの変わり目が 2 行のどちらの間か決まらないとき、その間の行は付けない。
    const amb = [{ id: "a", ord: 0, kind: "lyric" }, { id: "b", ord: 2, kind: "lyric" }, { id: "c", ord: 4, kind: "lyric" }];
    const got = alignArchive(lyricLines(["x", "x", "x", "x", ""]), amb as never)!;
    expect(got.get(amb[0] as never)).toBe(0);
    expect(got.has(amb[1] as never)).toBe(false);
    expect(got.get(amb[2] as never)).toBe(3);
  });

  it("本文と同じ文言で除いた被せのコールは、近い括弧の中身から文言を戻す", () => {
    const archived = [{ id: "a", ord: 0, kind: "lyric", calls: [
      { id: "c1", start: 4, end: 11, timing: "over" },            // 括弧の中身と 1 字ずれ
      { id: "c2", start: 0, end: 0, timing: "after" },            // 追っかけは文言が分からない
    ] }];
    const [line] = applyAnnotationArchive(lyricLines(["ほら (Let's go!) 行こう"]), archived as never)!;
    expect(line!.calls).toEqual([expect.objectContaining({ id: "c1", start: 4, end: 13, text: "Let's go!", timing: "over" })]);
    expect(applyAnnotationArchive(lyricLines(["括弧の無い行の長いところ"]), [{ ...archived[0], calls: [archived[0]!.calls[0]] }] as never)![0]!.calls).toEqual([]);
  });
});
