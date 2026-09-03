import { describe, expect, it } from "vitest";
import { handleLyrics } from "../src/routes/lyrics";
import type { Env } from "../src/env";
import type { RouteContext } from "../src/routes/context";

// JASRAC 許諾 J260943703 は「ご利用曲数 100曲まで」。101 曲目を published にできて
// しまうと、フラグの付け間違い (`--all --status published`) がそのまま許諾違反になる。
// ここで守っているのはコードの整合性ではなく許諾の範囲そのものなので、
// 上限の判定だけは実ハンドラを通して確かめておく。

const PUSH_TOKEN = "test-push-token";

/**
 * SQL の中身で応答を出し分ける D1 スタブ。歌詞 PUT が投げるクエリは
 * 「レート枠」「公開数」「既存行」「保存後の読み直し」の 4 種類しかない。
 */
function stubDb(publishedCount: number, log: string[]) {
  const answer = (sql: string) => {
    if (sql.includes("rate_limits")) return { count: 1 };
    if (sql.includes("FROM song_lyrics WHERE status = 'published'")) return { n: publishedCount };
    if (sql.includes("SELECT lines_json")) return { lines_json: null };
    if (sql.includes("SELECT source, status")) {
      return { source: null, status: "published", updated_at: "2026-09-03 00:00:00", lines_json: null };
    }
    return null;
  };
  const stmt = (sql: string) => ({
    bind: () => stmt(sql),
    first: async () => answer(sql),
    run: async () => ({ success: true }),
    all: async () => ({ results: [] }),
  });
  return {
    prepare: (sql: string) => {
      log.push(sql);
      return stmt(sql);
    },
    batch: async (statements: unknown[]) => {
      log.push("BATCH:" + statements.length);
      return [];
    },
  } as unknown as D1Database;
}

function put(songId: string, status: string, db: D1Database): RouteContext {
  return {
    request: new Request(`https://api.example.com/admin/lyrics/${songId}`, {
      method: "PUT",
      headers: { "X-Push-Token": PUSH_TOKEN, "Content-Type": "application/json" },
      body: JSON.stringify({ source: "test", status, lines: [{ kind: "lyric", text: "あ" }] }),
    }),
    env: { DB: db, LYRICS_PUSH_TOKEN: PUSH_TOKEN } as unknown as Env,
    url: new URL(`https://api.example.com/admin/lyrics/${songId}`),
    path: `/admin/lyrics/${songId}`,
    json: (data, status = 200) => Response.json(data as object, { status }),
    error: (message, status = 400) => Response.json({ error: message }, { status }),
    rateLimitResponse: () => Response.json({ error: "rate limited" }, { status: 429 }),
    rateLimitSimple: () => Response.json({ error: "rate limited" }, { status: 429 }),
  };
}

describe("掲載曲数の上限 (JASRAC 許諾 J260943703 / 100曲)", () => {
  it("100 曲公開済みなら 101 曲目の published を 409 で拒む", async () => {
    const log: string[] = [];
    const res = await handleLyrics(put("cg_foo", "published", stubDb(100, log)));
    expect(res?.status).toBe(409);
    // 拒むだけでなく、書き込みに進んでいないこと。
    expect(log.some((sql) => sql.startsWith("BATCH:"))).toBe(false);
  });

  it("99 曲なら 100 曲目は通す", async () => {
    const log: string[] = [];
    const res = await handleLyrics(put("cg_foo", "published", stubDb(99, log)));
    expect(res?.status).toBe(200);
    expect(log.some((sql) => sql.startsWith("BATCH:"))).toBe(true);
  });

  it("draft は上限に達していても常に通す (入れ替えができなくなるため)", async () => {
    const log: string[] = [];
    const res = await handleLyrics(put("cg_foo", "draft", stubDb(100, log)));
    expect(res?.status).toBe(200);
    // 公開数を数えるクエリ自体を投げていない (draft は枠を使わない)。
    expect(log.some((sql) => sql.includes("status = 'published' AND song_id"))).toBe(false);
  });
});
