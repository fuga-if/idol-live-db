// 歌詞検索の転置インデックス (lyrics_gram_index) と、検索のバインド変数の上限。ローカル D1 で通す。
// 歌詞の本文には実在の歌詞を使わない (意味の無い文字列だけ)。

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { callJson, makeEnv } from "./support/worker";
import { exec, rows } from "./support/d1";

const PUSH_TOKEN = "push-token-for-test";

async function putLyrics(songId: string, texts: string[]) {
  return callJson("PUT", `/admin/lyrics/${encodeURIComponent(songId)}`, {
    headers: { "X-Push-Token": PUSH_TOKEN },
    body: { status: "published", lines: texts.map((text) => ({ kind: "lyric", text })) },
    env: makeEnv({ LYRICS_PUSH_TOKEN: PUSH_TOKEN }),
  });
}

async function gramsOf(songId: string): Promise<string[]> {
  const all = await rows<{ gram: string; song_ids: string }>("SELECT gram, song_ids FROM lyrics_gram_index");
  return all.filter((r) => r.song_ids.split("\n").includes(songId)).map((r) => r.gram).sort();
}

beforeEach(() => void vi.spyOn(console, "log").mockImplementation(() => {}));
afterEach(() => vi.restoreAllMocks());

describe("PUT /admin/lyrics/:id の索引の増分更新", () => {
  it("索引は正規化した本文から作る (検索語も全再構築も正規化後の形で引く)", async () => {
    expect((await putLyrics("s1", ["あいう"])).status).toBe(200);
    expect(await gramsOf("s1")).toEqual(["イ", "イウ", "ウ", "ア", "アイ"].sort());

    // 差し替えでは、消えた gram から曲を外し、増えた gram に足す。
    expect((await putLyrics("s1", ["あいえ"])).status).toBe(200);
    expect(await gramsOf("s1")).toEqual(["イ", "イエ", "エ", "ア", "アイ"].sort());
  });

  it("ひらがなで入れた曲が、カタカナの検索語の候補に索引から挙がる", async () => {
    // 全再構築で入った別の曲 (索引は正規化後の gram)。これがあると索引の候補で絞る経路を通る。
    await exec(
      "INSERT INTO song_lyrics (song_id, status, lines_json, body, body_norm) VALUES ('s2', 'published', '[]', 'テスト', 'テスト')"
    );
    for (const gram of ["テ", "テス", "ス", "スト", "ト"]) {
      await exec("INSERT INTO lyrics_gram_index (gram, part, song_ids) VALUES (?, 0, 's2')", gram);
    }
    await putLyrics("s1", ["てすとの ぎょう"]);

    const res = await callJson("GET", `/lyrics/search?q=${encodeURIComponent("テスト")}`);
    expect(res.status).toBe(200);
    expect(res.body.hits.map((h: any) => h.songId)).toEqual(["s1", "s2"]);
  });
});

describe("GET /lyrics/search のバインド変数", () => {
  it("同じ語を上限まで繰り返しても、索引の候補が多くても 500 にならない", async () => {
    // 索引で絞れる (候補 300 件以下) かつ、1 回の IN に入りきらない件数の曲を用意する。
    const ids = Array.from({ length: 100 }, (_, i) => `s${String(i).padStart(3, "0")}`);
    for (const id of ids) {
      await exec(
        "INSERT INTO song_lyrics (song_id, status, lines_json, body, body_norm) VALUES (?, 'published', '[]', 'アイ', 'アイ')",
        id
      );
    }
    for (const gram of ["ア", "イ", "アイ"]) {
      await exec("INSERT INTO lyrics_gram_index (gram, part, song_ids) VALUES (?, 0, ?)", gram, ids.join("\n"));
    }
    // 1 文字の語を空白で 25 個 (検索文字列の上限 50 文字)。
    const q = Array.from({ length: 25 }, (_, i) => (i % 2 === 0 ? "あ" : "い")).join(" ");
    expect(q.length).toBeLessThanOrEqual(50);

    const res = await callJson("GET", `/lyrics/search?q=${encodeURIComponent(q)}`);
    expect(res.status).toBe(200);
    expect(res.body.hits).toHaveLength(100);
    expect(res.body.hits[0].songId).toBe("s000");
  });
});
