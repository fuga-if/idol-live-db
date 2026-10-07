// POST /songs/:id/lyric-submissions — 歌詞の投稿。確認待ちで預かり、本文は返さない。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { normalizeLyricText, validateSubmission } from "../src/routes/lyric_submissions";
import { bearer, callJson, makeEnv } from "./support/worker";
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
    // 歌詞の無い曲なので、その場で公開する (運営はあとから確認する)
    expect(r.body.published).toBe(true);
    const lyrics = await callJson("GET", "/songs/s1/lyrics", { headers: await bearer(UID) });
    expect(lyrics.body.lines.map((l: { kind: string; text: string }) => [l.kind, l.text]))
      .toEqual([["lyric", "きらめく"], ["blank", ""], ["lyric", "ステージ"]]);
    expect(lyrics.body.source).toBe("みんなの投稿");

    // 既に歌詞のある曲への直しもすぐ公開し、前の版を残す (2026-10-07)
    const again = await callJson("POST", "/songs/s1/lyric-submissions", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "ちがう歌詞" },
    });
    expect(again.status).toBe(201);
    expect(again.body.published).toBe(true);
    const now = await callJson("GET", "/songs/s1/lyrics?v=2", { headers: await bearer(UID) });
    expect(now.body.lines.map((l: { text: string }) => l.text)).toEqual(["ちがう歌詞"]);
    expect(await row("SELECT COUNT(*) AS n FROM song_lyrics_versions WHERE song_id = 's1'")).toEqual({ n: 1 });

    // モデレーターは 1 つ前の版に戻せる (本文は応答に出さない)
    await insertUser("001094.lsub.admin", { isAdmin: true });
    const restored = await callJson("POST", "/admin/lyrics/s1/restore", { headers: await bearer("001094.lsub.admin") });
    expect(restored.body).toEqual({ restored: "s1" });
    const back = await callJson("GET", "/songs/s1/lyrics?v=3", { headers: await bearer(UID) });
    expect(back.body.lines.map((l: { text: string }) => l.text)).toEqual(["きらめく", "", "ステージ"]);
    expect((await callJson("POST", "/admin/lyrics/s1/restore", { headers: await bearer(UID) })).status).toBe(401);
  });

  it("歌詞を出せない曲は預かるだけで公開しない", async () => {
    const r = await callJson("POST", "/songs/765as_binarystar/lyric-submissions", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "ほし" },
    });
    expect(r.status).toBe(201);
    expect(r.body.published).toBe(false);
    expect(await row("SELECT COUNT(*) AS n FROM song_lyrics WHERE song_id = '765as_binarystar'")).toEqual({ n: 0 });
  });

  it("歌詞の奥付は名前を載せると選んだ人だけ。BAN すると、その人の版が出ている曲は非公開になる", async () => {
    await insertUser("001094.lsub.b", { displayName: "Bさん" });
    await callJson("POST", "/songs/s9/lyric-submissions", {
      headers: await bearer(UID), body: { agreed_to_guideline: true, text: "いち" },
    });
    await new Promise((res) => setTimeout(res, 1100)); // published_at は秒単位
    await callJson("POST", "/songs/s9/lyric-submissions", {
      headers: await bearer("001094.lsub.b"), body: { agreed_to_guideline: true, text: "に" },
    });
    await callJson("POST", "/users/me/credit", { headers: await bearer("001094.lsub.b"), body: { credit_opt_in: true } });
    const lyrics = await callJson("GET", "/songs/s9/lyrics", { headers: await bearer(UID) });
    expect(lyrics.body.submittedBy).toEqual({ names: ["Bさん"], total: 2 });

    // 投稿した人への手応え
    const fb = await callJson("GET", "/me/feedback?since=0", { headers: await bearer("001094.lsub.b") });
    expect(fb.body.lyrics.newPublishedCount).toBe(1);
    expect(fb.body.lyrics.published[0]).toMatchObject({ songId: "s9", isNew: true, likeCount: 0 });

    await insertUser("001094.lsub.admin2", { isAdmin: true });
    await callJson("POST", "/admin/ban", { headers: await bearer("001094.lsub.admin2"), body: { user_id: "001094.lsub.b" } });
    expect(await row("SELECT status FROM song_lyrics WHERE song_id = 's9'")).toEqual({ status: "draft" });
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

describe("POST /songs/:id/lyrics-report", () => {
  it("理由と短い補足だけを GitHub の issue にする (本文は載せない)", async () => {
    const sent: Array<{ url: string; body: { title: string; body: string; labels: string[] } }> = [];
    vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
      sent.push({ url, body: JSON.parse(String(init.body)) });
      return Response.json({ number: 1 }, { status: 201 });
    });
    const env = makeEnv({ GITHUB_TOKEN: "t", GITHUB_REPO: "owner/repo" });
    expect((await callJson("POST", "/songs/s1/lyrics-report", { body: { reason: "copied" }, env })).status).toBe(401);
    expect((await callJson("POST", "/songs/s1/lyrics-report", {
      headers: await bearer(UID), body: { reason: "nope" }, env,
    })).status).toBe(400);
    const r = await callJson("POST", "/songs/s1/lyrics-report", {
      headers: await bearer(UID), body: { reason: "copied", note: "あ".repeat(400) }, env,
    });
    expect(r.status).toBe(201);
    expect(sent[0].url).toBe("https://api.github.com/repos/owner/repo/issues");
    expect(sent[0].body.title).toBe("[歌詞の報告] s1 — 歌詞サイト・他サービスからの転載");
    expect(sent[0].body.labels).toEqual(["lyrics-report"]);
    expect(sent[0].body.body).toContain("あ".repeat(300));
    expect(sent[0].body.body).not.toContain("あ".repeat(301));
  });
});
