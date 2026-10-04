// みんなのプレイリスト。公開・一覧・差し替え・取り下げと、作者名を返さないこと。
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { validatePlaylistBody } from "../src/routes/community_playlists";
import { bearer, callJson } from "./support/worker";
import { insertUser, row } from "./support/d1";

const OWNER = "001094.playlist_owner";
const OTHER = "001094.playlist_other";
const ADMIN = "001094.playlist_admin";

beforeEach(async () => {
  vi.spyOn(console, "log").mockImplementation(() => undefined);
  await insertUser(OWNER, { displayName: "作者" });
  await insertUser(OTHER);
  await insertUser(ADMIN, { isAdmin: true });
});
afterEach(() => vi.restoreAllMocks());

async function publish(body: Record<string, unknown>, uid = OWNER) {
  return callJson("POST", "/playlists", { headers: await bearer(uid), body });
}

describe("みんなのプレイリスト", () => {
  it("公開すると一覧と 1 つ取りに出る。作者名は返さない", async () => {
    const created = await publish({ title: " 遠征の行き ", description: "ひとこと", songIds: ["a", "b", "a", "c", "d", "e"] });
    expect(created.status).toBe(201);
    expect(created.body).toMatchObject({ title: "遠征の行き", songIds: ["a", "b", "c", "d", "e"], songCount: 5, isOwn: true });

    const list = await callJson("GET", "/playlists");
    expect(list.status).toBe(200);
    expect(list.body.playlists).toHaveLength(1);
    expect(list.body.playlists[0].songIds).toEqual(["a", "b", "c", "d"]);
    expect(JSON.stringify(list.body)).not.toContain("作者");
    expect(JSON.stringify(list.body)).not.toContain(OWNER);

    const one = await callJson("GET", `/playlists/${created.body.id}`);
    expect(one.body.songIds).toEqual(["a", "b", "c", "d", "e"]);
    expect(JSON.stringify(one.body)).not.toContain(OWNER);
  });

  it("差し替えは作者だけ。取り下げは作者かモデレーター", async () => {
    const created = await publish({ title: "t", songIds: ["a"] });
    const id = created.body.id;
    expect((await callJson("PUT", `/playlists/${id}`, { headers: await bearer(OTHER), body: { title: "x", songIds: ["b"] } })).status).toBe(404);
    const put = await callJson("PUT", `/playlists/${id}`, { headers: await bearer(OWNER), body: { title: "t2", songIds: ["b", "c"] } });
    expect(put.body).toMatchObject({ title: "t2", songIds: ["b", "c"], songCount: 2 });

    expect((await callJson("DELETE", `/playlists/${id}`, { headers: await bearer(OTHER) })).status).toBe(403);
    expect((await callJson("DELETE", `/playlists/${id}`, { headers: await bearer(ADMIN) })).status).toBe(200);
    expect((await callJson("GET", `/playlists/${id}`)).status).toBe(404);
    expect((await row<{ status: string }>("SELECT status FROM community_playlists WHERE id = ?", id))!.status).toBe("removed");
  });

  it("自分の公開分は /me/playlists で全曲つきで返る", async () => {
    await publish({ title: "mine", songIds: ["a", "b", "c", "d", "e"] });
    await publish({ title: "theirs", songIds: ["z"] }, OTHER);
    const mine = await callJson("GET", "/me/playlists", { headers: await bearer(OWNER) });
    expect(mine.body.playlists.map((p: { title: string }) => p.title)).toEqual(["mine"]);
    expect(mine.body.playlists[0].songIds).toHaveLength(5);
    expect((await callJson("GET", "/me/playlists")).status).toBe(401);
  });

  it("本文の確かめ: 空の題・曲なし・長すぎは 400、未ログインは 401", async () => {
    expect(validatePlaylistBody({ title: "", songIds: ["a"] }).ok).toBe(false);
    expect(validatePlaylistBody({ title: "t", songIds: [] }).ok).toBe(false);
    expect(validatePlaylistBody({ title: "あ".repeat(41), songIds: ["a"] }).ok).toBe(false);
    expect(validatePlaylistBody({ title: "t", songIds: [1] }).ok).toBe(false);
    expect((await callJson("POST", "/playlists", { body: { title: "t", songIds: ["a"] } })).status).toBe(401);
  });
});
