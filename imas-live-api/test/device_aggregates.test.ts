// お気に入り / ペンライト色 (端末単位の集計) の特性テスト。ローカル D1 で index.ts の入口から通す。
//
// ⚠️ 同じ端末の再送・付けていない端末の取り消しで数が動く件は P2-16 で直すので、ここでは固定しない
//    (test/device_counters.test.ts が直した後の挙動を固定する)。

import { describe, expect, it } from "vitest";
import { callJson, device } from "./support/worker";
import { exec, row, rows } from "./support/d1";

async function toggleFavorite(songId: string, value: boolean, deviceId: string) {
  return callJson("POST", "/favorites/toggle", { headers: device(deviceId), body: { song_id: songId, value } });
}

async function votePenlight(songId: string, colors: string[], deviceId: string) {
  return callJson("POST", "/penlight/vote", { headers: device(deviceId), body: { song_id: songId, colors } });
}

describe("POST /favorites/toggle", () => {
  it("端末 ID 必須。本文を検証する", async () => {
    expect((await callJson("POST", "/favorites/toggle", { body: { song_id: "s1", value: true } })).body)
      .toEqual({ error: "X-Device-Id header is required" });
    const cases: Array<[unknown, string]> = [
      ["{", "invalid JSON body"],
      [{ value: true }, "song_id is required"],
      [{ song_id: "", value: true }, "song_id is required"],
      [{ song_id: "x".repeat(201), value: true }, "song_id must be 200 characters or less"],
      [{ song_id: "s1", value: "yes" }, "value must be boolean"],
    ];
    for (const [body, message] of cases) {
      const res = await callJson("POST", "/favorites/toggle", { headers: device("dev-a"), body });
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body).toEqual({ error: message });
    }
  });

  it("登録で数が増え、登録した端末の解除で減る。応答は曲 id と現在の数", async () => {
    expect((await toggleFavorite("s1", true, "dev-a")).body).toEqual({ song_id: "s1", count: 1 });
    expect((await toggleFavorite("s1", true, "dev-b")).body).toEqual({ song_id: "s1", count: 2 });
    expect((await toggleFavorite("s1", false, "dev-a")).body).toEqual({ song_id: "s1", count: 1 });
    expect(await rows("SELECT device_id FROM device_song_favorite")).toEqual([{ device_id: "dev-b" }]);
  });

  it("数は 0 未満にならない", async () => {
    await exec("INSERT INTO song_favorites (song_id, count) VALUES ('s1', 0)");
    await exec("INSERT INTO device_song_favorite (device_id, song_id, created_at) VALUES ('dev-a', 's1', 1)");
    expect((await toggleFavorite("s1", false, "dev-a")).body).toEqual({ song_id: "s1", count: 0 });
  });
});

describe("GET /favorites/ranking", () => {
  it("数の多い順に song_id と数だけを返す。公開キャッシュ", async () => {
    await exec("INSERT INTO song_favorites (song_id, count) VALUES ('a', 1), ('b', 5), ('c', 3)");
    const res = await callJson("GET", "/favorites/ranking");
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe("public, max-age=60, stale-while-revalidate=300");
    expect(res.body).toEqual([
      { song_id: "b", count: 5 },
      { song_id: "c", count: 3 },
      { song_id: "a", count: 1 },
    ]);
    const limited = await callJson("GET", "/favorites/ranking?limit=2");
    expect(limited.body.map((r: any) => r.song_id)).toEqual(["b", "c"]);
  });
});

describe("ペンライト", () => {
  it("GET /penlight/palette は並び順どおりの全色 (キャッシュ指定なし)", async () => {
    const res = await callJson("GET", "/penlight/palette");
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBeNull();
    expect(res.body).toHaveLength(15);
    expect(res.body[0]).toEqual({
      color_hex: "#FFFFFF", name: "白", sort_order: 1, note: "黒ペンライトの代用として使われることが多い",
    });
  });

  it("POST /penlight/vote は端末 ID 必須。本文を検証する", async () => {
    expect((await callJson("POST", "/penlight/vote", { body: { song_id: "s1", colors: ["#FF0000"] } })).body)
      .toEqual({ error: "X-Device-Id header is required" });
    const cases: Array<[unknown, string]> = [
      ["{", "invalid JSON body"],
      [{ colors: ["#FF0000"] }, "song_id is required"],
      [{ song_id: "s1" }, "colors must be a non-empty array"],
      [{ song_id: "s1", colors: [] }, "colors must be a non-empty array"],
    ];
    for (const [body, message] of cases) {
      const res = await callJson("POST", "/penlight/vote", { headers: device("dev-a"), body });
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body).toEqual({ error: message });
    }
  });

  it("色は並べ替えて - で連結した組で数える。同じ端末の投票は差し替え", async () => {
    const first = await votePenlight("s1", ["#FF0000", "#0000FF"], "dev-a");
    expect(first.status).toBe(200);
    expect(first.body).toEqual({ song_id: "s1", color_set_key: "#0000FF-#FF0000", count: 1 });
    expect((await votePenlight("s1", ["#0000FF", "#FF0000"], "dev-b")).body.count).toBe(2);

    // 同じ組を入れ直しても数は変わらない。
    expect((await votePenlight("s1", ["#FF0000", "#0000FF"], "dev-a")).body.count).toBe(2);

    // 別の組に替えると、前の組が 1 減り新しい組が 1 増える。
    expect((await votePenlight("s1", ["#FFFFFF"], "dev-a")).body)
      .toEqual({ song_id: "s1", color_set_key: "#FFFFFF", count: 1 });
    expect(await rows("SELECT color_set_key, count FROM penlight_color_set_votes ORDER BY color_set_key"))
      .toEqual([
        { color_set_key: "#0000FF-#FF0000", count: 1 },
        { color_set_key: "#FFFFFF", count: 1 },
      ]);
  });

  it("GET /penlight/votes/:song_id は上位 5 組・総数・自分の投票", async () => {
    const sets = [["#000001"], ["#000002"], ["#000003"], ["#000004"], ["#000005"], ["#000006"]];
    for (let i = 0; i < sets.length; i++) {
      for (let n = 0; n <= i; n++) await votePenlight("s1", sets[i], `dev-${i}-${n}`);
    }
    const res = await callJson("GET", "/penlight/votes/s1", { headers: device("dev-5-0") });
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBeNull();
    expect(res.body.total_votes).toBe(21);
    expect(res.body.top_sets.map((s: any) => [s.key, s.count])).toEqual([
      ["#000006", 6], ["#000005", 5], ["#000004", 4], ["#000003", 3], ["#000002", 2],
    ]);
    expect(res.body.top_sets[0]).toEqual({ key: "#000006", colors: ["#000006"], count: 6 });
    expect(res.body.my_vote).toEqual({ color_set_key: "#000006", colors: ["#000006"] });

    const anon = await callJson("GET", "/penlight/votes/s1?anon=1");
    expect(anon.body.my_vote).toBeNull();
    const empty = await callJson("GET", "/penlight/votes/none");
    expect(empty.body).toEqual({ top_sets: [], total_votes: 0, my_vote: null });
  });

  it("DELETE /penlight/vote は投票していれば取り消し、していなければ cancelled: false", async () => {
    await votePenlight("s1", ["#FF0000"], "dev-a");
    await votePenlight("s1", ["#FF0000"], "dev-b");

    const none = await callJson("DELETE", "/penlight/vote?song_id=s1", { headers: device("dev-x") });
    expect(none.body).toEqual({ song_id: "s1", cancelled: false });

    const res = await callJson("DELETE", "/penlight/vote?song_id=s1", { headers: device("dev-a") });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ song_id: "s1", cancelled: true });
    expect(await row("SELECT count FROM penlight_color_set_votes WHERE song_id = 's1'")).toEqual({ count: 1 });
    expect(await rows("SELECT device_id FROM device_song_penlight")).toEqual([{ device_id: "dev-b" }]);

    const missing = await callJson("DELETE", "/penlight/vote", { headers: device("dev-a") });
    expect(missing.status).toBe(400);
    expect(missing.body).toEqual({ error: "song_id is required" });
  });
});
