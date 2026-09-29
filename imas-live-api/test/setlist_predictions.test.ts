// 予想セトリ / 出演者予想 / セトリのいいね の特性テスト。ローカル D1 で index.ts の入口から通す。

import { describe, expect, it } from "vitest";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";

const UID = "001094.predictor";
const OTHER = "001094.other";

describe("予想セトリ (/shows/:id/predictions と /me/predictions)", () => {
  async function predict(showId: string, songId: string, uid = UID) {
    return callJson("POST", `/shows/${showId}/predictions`, { headers: await bearer(uid), body: { song_id: songId } });
  }

  it("未ログインは 401、BAN は 403。song_id を検証する", async () => {
    expect((await callJson("POST", "/shows/sh1/predictions", { body: { song_id: "s1" } })).status).toBe(401);
    await insertUser(UID, { isBanned: true });
    expect((await predict("sh1", "s1")).status).toBe(403);
    await insertUser(OTHER);
    const bad = await callJson("POST", "/shows/sh1/predictions", { headers: await bearer(OTHER), body: {} });
    expect(bad.status).toBe(400);
    expect(bad.body).toEqual({ error: "song_id is required" });
  });

  it("投票は 201。同じ曲は 200 で already_voted。1 公演 3 票まで", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    expect((await predict("sh1", "s1")).body)
      .toEqual({ song_id: "s1", vote_count: 1, already_voted: false, my_vote_count: 1 });
    const again = await predict("sh1", "s1");
    expect(again.status).toBe(200);
    expect(again.body).toEqual({ song_id: "s1", vote_count: 1, already_voted: true, my_vote_count: 1 });
    expect((await predict("sh1", "s1", OTHER)).body.vote_count).toBe(2);
    await predict("sh1", "s2");
    await predict("sh1", "s3");
    const fourth = await predict("sh1", "s4");
    expect(fourth.status).toBe(409);
    expect(fourth.body).toEqual({ error: "vote limit" });
    // 別の公演は別枠。
    expect((await predict("sh2", "s4")).status).toBe(201);
  });

  it("一覧は票数順で、自分が入れた曲に印を付ける。/me/predictions は自分の票の一覧", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    await predict("sh1", "s1", OTHER);
    await predict("sh1", "s2", OTHER);
    await predict("sh1", "s2");

    const list = await callJson("GET", "/shows/sh1/predictions", { headers: await bearer(UID) });
    expect(list.status).toBe(200);
    expect(list.res.headers.get("Cache-Control")).toBeNull();
    expect(list.body.map((r: any) => [r.song_id, r.vote_count, r.has_user_voted])).toEqual([
      ["s2", 2, true], ["s1", 1, false],
    ]);
    expect(Object.keys(list.body[0]).sort()).toEqual(
      ["first_voted_at", "first_voted_by", "has_user_voted", "show_id", "song_id", "vote_count"]
    );

    const mine = await callJson("GET", "/me/predictions", { headers: await bearer(UID) });
    expect(mine.body).toEqual([
      { show_id: "sh1", song_id: "s2", vote_count: 2, voted_at: expect.any(String) },
    ]);
    expect((await callJson("GET", "/me/predictions")).status).toBe(401);
  });

  it("一覧の first_voted_by は先頭 8 文字だけ返す (キーは残す。値の無い行は null のまま)", async () => {
    await insertUser(UID);
    await predict("sh1", "s1");
    await exec("INSERT INTO setlist_predictions (show_id, song_id, vote_count, first_voted_by) VALUES ('sh1', 's2', 1, NULL)");
    const list = await callJson("GET", "/shows/sh1/predictions");
    expect(Object.fromEntries(list.body.map((r: any) => [r.song_id, r.first_voted_by])))
      .toEqual({ s1: UID.slice(0, 8), s2: null });
  });

  it("取り消しは票を 1 減らし、0 票の行は消える。入れていなければ not_voted", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    await predict("sh1", "s1");
    const auth = await bearer(UID);
    expect((await callJson("DELETE", "/shows/sh1/predictions/s9", { headers: auth })).body)
      .toEqual({ song_id: "s9", vote_count: 0, not_voted: true });
    expect((await callJson("DELETE", "/shows/sh1/predictions/s1", { headers: auth })).body)
      .toEqual({ song_id: "s1", vote_count: 0 });
    expect(await rows("SELECT * FROM setlist_predictions")).toEqual([]);
  });
});

describe("出演者予想 (/shows/:id/songs/:songId/performers)", () => {
  async function pick(idolId: string, uid = UID, songId = "s1") {
    return callJson("POST", `/shows/sh1/songs/${songId}/performers`, {
      headers: await bearer(uid), body: { idol_id: idolId },
    });
  }

  it("未ログインは 401、BAN は 403。idol_id を検証する", async () => {
    expect((await callJson("POST", "/shows/sh1/songs/s1/performers", { body: { idol_id: "i1" } })).status).toBe(401);
    await insertUser(UID, { isBanned: true });
    expect((await pick("i1")).status).toBe(403);
    await insertUser(OTHER);
    const bad = await callJson("POST", "/shows/sh1/songs/s1/performers", { headers: await bearer(OTHER), body: {} });
    expect(bad.status).toBe(400);
    expect(bad.body).toEqual({ error: "idol_id is required" });
  });

  it("投票は 201。同じアイドルは 200 で already_voted (枠を使わない)。1 曲 8 人まで", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    expect((await pick("i1")).body).toEqual({ idol_id: "i1", vote_count: 1, already_voted: false });
    const again = await pick("i1");
    expect(again.status).toBe(200);
    expect(again.body).toEqual({ idol_id: "i1", vote_count: 1, already_voted: true });
    expect(await row("SELECT count FROM rate_limits WHERE action = 'performer_prediction'")).toEqual({ count: 1 });

    expect((await pick("i1", OTHER)).body.vote_count).toBe(2);
    for (let i = 2; i <= 8; i++) expect((await pick(`i${i}`)).status).toBe(201);
    const ninth = await pick("i9");
    expect(ninth.status).toBe(422);
    expect(ninth.body).toEqual({ error: "Too many votes: max 8 performers per song" });
    expect(await row("SELECT first_voted_by FROM setlist_performer_predictions WHERE idol_id = 'i1'"))
      .toEqual({ first_voted_by: UID });
  });

  it("一覧は票数順で、自分が入れたアイドルに印を付ける", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    await pick("i1", OTHER);
    await pick("i2", OTHER);
    await pick("i2");
    const res = await callJson("GET", "/shows/sh1/songs/s1/performers", { headers: await bearer(UID) });
    expect(res.status).toBe(200);
    expect(res.body.map((r: any) => [r.idol_id, r.vote_count, r.has_user_voted])).toEqual([
      ["i2", 2, true], ["i1", 1, false],
    ]);
    expect(Object.keys(res.body[0]).sort()).toEqual(
      ["first_voted_at", "first_voted_by", "has_user_voted", "idol_id", "show_id", "song_id", "vote_count"]
    );
  });

  it("一覧の first_voted_by は先頭 8 文字だけ返す (キーは残す)", async () => {
    await insertUser(UID);
    await pick("i1");
    const res = await callJson("GET", "/shows/sh1/songs/s1/performers");
    expect(res.body.map((r: any) => r.first_voted_by)).toEqual([UID.slice(0, 8)]);
  });

  it("取り消しは票を 1 減らし、0 票の行は消える。入れていなければ not_voted", async () => {
    await insertUser(UID);
    await insertUser(OTHER);
    await pick("i1");
    await pick("i1", OTHER);
    const auth = await bearer(UID);
    expect((await callJson("DELETE", "/shows/sh1/songs/s1/performers/i9", { headers: auth })).body)
      .toEqual({ idol_id: "i9", vote_count: 0, not_voted: true });
    expect((await callJson("DELETE", "/shows/sh1/songs/s1/performers/i1", { headers: auth })).body)
      .toEqual({ idol_id: "i1", vote_count: 1 });
    expect((await callJson("DELETE", "/shows/sh1/songs/s1/performers/i1", { headers: await bearer(OTHER) })).body)
      .toEqual({ idol_id: "i1", vote_count: 0 });
    expect(await rows("SELECT * FROM setlist_performer_predictions")).toEqual([]);
  });
});

describe("セトリのいいね (/shows/:id/likes と /shows/:id/songs/:songId/like)", () => {
  it("未ログインは 401。いいねは冪等で、曲ごとの数と自分の状態を返す", async () => {
    expect((await callJson("POST", "/shows/sh1/songs/s1/like")).status).toBe(401);
    await insertUser(UID);
    await insertUser(OTHER);
    const auth = await bearer(UID);
    expect((await callJson("POST", "/shows/sh1/songs/s1/like", { headers: auth })).body)
      .toEqual({ song_id: "s1", like_count: 1, liked: true });
    expect((await callJson("POST", "/shows/sh1/songs/s1/like", { headers: auth })).body.like_count).toBe(1);
    await callJson("POST", "/shows/sh1/songs/s1/like", { headers: await bearer(OTHER) });
    await callJson("POST", "/shows/sh1/songs/s2/like", { headers: await bearer(OTHER) });

    const list = await callJson("GET", "/shows/sh1/likes", { headers: auth });
    expect(list.res.headers.get("Cache-Control")).toBeNull();
    expect([...list.body].sort((a: any, b: any) => a.song_id.localeCompare(b.song_id))).toEqual([
      { song_id: "s1", like_count: 2, has_user_liked: true },
      { song_id: "s2", like_count: 1, has_user_liked: false },
    ]);

    expect((await callJson("DELETE", "/shows/sh1/songs/s1/like", { headers: auth })).body)
      .toEqual({ song_id: "s1", like_count: 1, liked: false });
  });

  it("BAN は 403。曲 id の長さを検証する", async () => {
    await insertUser(UID, { isBanned: true });
    expect((await callJson("POST", "/shows/sh1/songs/s1/like", { headers: await bearer(UID) })).status).toBe(403);
    await insertUser(OTHER);
    const long = await callJson("POST", `/shows/sh1/songs/${"x".repeat(201)}/like`, { headers: await bearer(OTHER) });
    expect(long.status).toBe(400);
    expect(long.body).toEqual({ error: "song_id must be 200 characters or less" });
  });
});

describe("表の前提", () => {
  it("予想・出演者予想・いいねの表は show_id を持つ (本番と同じ。0038 で揃えた)", async () => {
    await exec("INSERT INTO setlist_predictions (show_id, song_id) VALUES ('sh', 's')");
    await exec("INSERT INTO setlist_prediction_votes (show_id, song_id, user_id) VALUES ('sh', 's', 'u')");
    await exec("INSERT INTO setlist_song_likes (show_id, song_id, user_id) VALUES ('sh', 's', 'u')");
    await exec("INSERT INTO setlist_performer_predictions (show_id, song_id, idol_id) VALUES ('sh', 's', 'i')");
    expect(await rows("SELECT show_id FROM setlist_song_likes")).toEqual([{ show_id: "sh" }]);
    // 本番の first_voted_at は NOT NULL で既定値あり。
    expect(await row("SELECT first_voted_at IS NOT NULL AS has_time FROM setlist_predictions")).toEqual({ has_time: 1 });
  });
});
