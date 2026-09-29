import { describe, expect, it } from "vitest";
import { handleLyrics } from "../src/routes/lyrics";
import type { RouteContext } from "../src/routes/context";
import { responders, stubD1 } from "./support/stub_d1";

// GET /lyrics/published は歌詞クイズの出題母集団。契約は 2 つ:
//   1. 返すのは公開済み (published) の song_id だけ。本文の列を SELECT しない
//      (まとめ取りの口にしない = JASRAC 許諾の「一括ダウンロード不可」)。
//   2. 本文を含まないのでエッジにキャッシュしてよい。

function ctxFor(db: D1Database): RouteContext {
  const path = "/lyrics/published";
  const url = new URL(`https://api.example.com${path}`);
  return {
    request: new Request(url.toString(), { method: "GET" }),
    env: { DB: db, ADMIN_USER_IDS: "" } as unknown as RouteContext["env"],
    url,
    path,
    ...responders,
  } as RouteContext;
}

describe("GET /lyrics/published", () => {
  it("公開済みの song_id だけを返し、本文の列には触れない", async () => {
    const stub = stubD1((sql) =>
      sql.includes("FROM song_lyrics") ? [{ song_id: "cg_a" }, { song_id: "ml_b" }] : undefined
    );
    const res = await handleLyrics(ctxFor(stub.db));
    expect(res?.status).toBe(200);
    expect(await res!.json()).toEqual({ songIds: ["cg_a", "ml_b"] });
    const sql = stub.sql();
    expect(sql).toContain("status = 'published'");
    for (const col of ["lines_json", "body", "source"]) expect(sql).not.toContain(col);
  });
});
