// パスの値の percent-encoding が壊れているとき (%G0 や、途中で切れた UTF-8 の %E3%81) は、
// どのルートも 400 `invalid <名前>` を返す。以前は decodeURIComponent の例外が 500 になっていた。

import { describe, expect, it } from "vitest";
import { bearer, callJson, device } from "./support/worker";

const TRUNCATED = "%E3%81";
const NOT_HEX = "%G0";

type Case = [method: string, path: string, field: string];

const CASES: Case[] = [
  // タグ 3 プール
  ["GET", `/tags/${TRUNCATED}`, "tag_id"],
  ["PUT", `/tags/${NOT_HEX}`, "tag_id"],
  ["DELETE", `/idol-tags/${TRUNCATED}`, "tag_id"],
  ["GET", `/idol-tags/${TRUNCATED}/history`, "tag_id"],
  ["POST", `/unit-tags/${NOT_HEX}/report`, "tag_id"],
  ["GET", `/songs/${TRUNCATED}/tags`, "song_id"],
  ["POST", `/idols/${TRUNCATED}/tags`, "idol_id"],
  ["DELETE", `/units/u1/tags/${TRUNCATED}`, "tag_id"],
  ["DELETE", `/songs/${NOT_HEX}/tags/t1`, "song_id"],
  ["GET", `/songs/${TRUNCATED}/similar`, "song_id"],
  // 端末集計
  ["GET", `/penlight/votes/${TRUNCATED}`, "song_id"],
  // お題
  ["GET", `/polls/${TRUNCATED}`, "poll_id"],
  ["GET", `/polls/achievements/${TRUNCATED}`, "entity_id"],
  ["POST", `/polls/${NOT_HEX}/votes`, "poll_id"],
  ["DELETE", `/polls/p1/votes/${TRUNCATED}`, "entity_id"],
  ["DELETE", `/polls/${TRUNCATED}`, "poll_id"],
  // 予想・いいね
  ["GET", `/shows/${TRUNCATED}/predictions`, "show_id"],
  ["DELETE", `/shows/sh1/predictions/${NOT_HEX}`, "song_id"],
  ["GET", `/shows/sh1/songs/${TRUNCATED}/performers`, "song_id"],
  ["DELETE", `/shows/sh1/songs/s1/performers/${TRUNCATED}`, "idol_id"],
  ["GET", `/shows/${NOT_HEX}/likes`, "show_id"],
  ["POST", `/shows/sh1/songs/${TRUNCATED}/like`, "song_id"],
  // 歌詞 (前から 400 を返していた口も、同じ文言のまま)
  ["GET", `/songs/${TRUNCATED}/lyrics`, "song_id"],
  ["GET", `/songs/${TRUNCATED}/detail`, "song_id"],
  // index.ts のルート
  ["GET", `/users/${TRUNCATED}/badges`, "user_id"],
  ["GET", `/admin/users/${NOT_HEX}/edits`, "user_id"],
  ["GET", `/master/Song/${TRUNCATED}/history`, "record_name"],
  ["GET", `/transfer/${TRUNCATED}`, "code"],
];

describe("壊れた percent-encoding のパス", () => {
  it.each(CASES)("%s %s は 400 invalid %s", async (method, path, field) => {
    const headers = { ...(await bearer("001094.path-user")), ...device("dev-path") };
    const res = await callJson(method, path, { headers, body: method === "GET" ? undefined : {} });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: `invalid ${field}` });
  });

  it("正しく符号化した日本語の ID はそのまま通る", async () => {
    const res = await callJson("GET", `/songs/${encodeURIComponent("曲/1")}/tags`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ tags: [], my_tag_ids: [] });
  });
});
