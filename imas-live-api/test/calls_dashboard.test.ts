import { describe, expect, it } from "vitest";
import { handleCallsDashboard } from "../src/routes/calls";
import type { RouteContext } from "../src/routes/context";
import { responders, stubD1, type Responder } from "./support/stub_d1";

// GET /calls/dashboard は認証不要 = エッジキャッシュ (public, max-age) に載る。
// **そこに歌詞本文やコール本文が 1 文字でも混ざったら JASRAC 許諾の前提が崩れる**ので、
// 応答の中身だけでなく「発行した SQL が歌詞の列に触れていないこと」まで見る。

const TAG = { id: "tag_44Kz44O844Or5puy", name: "コール曲" };

const statsRow = (over: Record<string, unknown> = {}) => ({
  song_id: "cg_お願いシンデレラ",
  call_lines: 18,
  call_count: 42,
  updated_at: "2026-09-01 12:00:00",
  updated_by_name: "ぷろでゅーさー",
  ...over,
});

const historyRow = (over: Record<string, unknown> = {}) => ({
  id: 12,
  song_id: "cg_お願いシンデレラ",
  at: "2026-09-01 12:00:00",
  call_lines_before: 0,
  call_lines_after: 18,
  call_count_before: 0,
  call_count_after: 42,
  by_name: "ぷろでゅーさー",
  ...over,
});

const taggedRow = (over: Record<string, unknown> = {}) => ({
  song_id: "ml_Thank_You",
  has_lyrics: 1,
  has_calls: 0,
  ...over,
});

/** 既定の応答 (1 曲 / 1 履歴 / タグ 3 曲)。個別のテストは over で差し替える。 */
function defaultResponder(over: Partial<{
  tag: unknown;
  stats: unknown[];
  history: unknown[];
  tagged: unknown[];
}> = {}): Responder {
  return (sql) => {
    if (sql.includes("FROM tags WHERE name")) return "tag" in over ? over.tag : TAG;
    if (sql.includes("FROM song_call_stats s")) return over.stats ?? [statsRow()];
    if (sql.includes("FROM call_edit_history h")) return over.history ?? [historyRow()];
    if (sql.includes("FROM song_tags st")) {
      return (
        over.tagged ?? [
          taggedRow(),
          taggedRow({ song_id: "cg_お願いシンデレラ", has_calls: 1 }),
          taggedRow({ song_id: "sc_夢咲きAFTER_SCHOOL", has_lyrics: 0 }),
        ]
      );
    }
    return undefined;
  };
}

function makeCtx(db: D1Database, path = "/calls/dashboard", method = "GET"): RouteContext {
  const url = new URL(`https://api.example.com${path}`);
  return {
    request: new Request(url.toString(), { method }),
    env: { DB: db } as unknown as RouteContext["env"],
    url,
    path,
    ...responders,
  };
}

async function get(responder: Responder = defaultResponder()) {
  const stub = stubD1(responder);
  const res = await handleCallsDashboard(makeCtx(stub.db));
  return { stub, res: res!, body: res ? ((await res.json()) as any) : null };
}

describe("GET /calls/dashboard — ルーティング", () => {
  it("別のパスでは null を返してルータの if チェーンに戻す", async () => {
    const stub = stubD1(defaultResponder());
    expect(await handleCallsDashboard(makeCtx(stub.db, "/calls"))).toBeNull();
    expect(await handleCallsDashboard(makeCtx(stub.db, "/songs/x/calls"))).toBeNull();
    // 1 文も D1 を叩いていない (マッチ判定より先に SQL を投げていない)。
    expect(stub.calls).toHaveLength(0);
  });

  it("GET 以外では null を返す", async () => {
    const stub = stubD1(defaultResponder());
    expect(await handleCallsDashboard(makeCtx(stub.db, "/calls/dashboard", "POST"))).toBeNull();
    expect(stub.calls).toHaveLength(0);
  });
});

describe("GET /calls/dashboard — 歌詞を漏らさない (最重要)", () => {
  it("応答 JSON に text / anchorText / lines が現れない", async () => {
    const { res, body } = await get();
    expect(res.status).toBe(200);
    const raw = JSON.stringify(body);
    // 「コール本文を足したくなったら、まずこのテストを消すことになる」構造にしてある。
    expect(raw).not.toContain("anchorText");
    expect(raw).not.toContain('"text"');
    expect(raw).not.toContain('"lines"');
    expect(raw).not.toContain("clap");
  });

  it("発行 SQL が歌詞本文の列 (lines_json / body / body_norm) を読まない", async () => {
    const { stub } = await get();
    const sql = stub.sql();
    expect(sql).not.toMatch(/lines_json/);
    expect(sql).not.toMatch(/\bbody\b/);
    expect(sql).not.toMatch(/body_norm/);
    // song_lyrics には触れるが、見るのは status と存在有無だけ。
    expect(sql).toMatch(/song_lyrics/);
  });

  it("生の uid を返さない (編集者匿名性)", async () => {
    const uid = "001094.fedcba9876543210";
    const { body } = await get((sql) => {
      if (sql.includes("FROM tags WHERE name")) return TAG;
      if (sql.includes("FROM song_call_stats s")) return [statsRow({ updated_by_name: null })];
      if (sql.includes("FROM call_edit_history h")) return [historyRow({ by_name: null })];
      if (sql.includes("FROM song_tags st")) return [taggedRow()];
      return undefined;
    });
    expect(JSON.stringify(body)).not.toContain(uid);
    // uid の代わりに出るのはマスク済み表示名だけ。
    expect(body.songsWithCalls[0].updatedBy).toBe("匿名");
    expect(body.recentEdits[0].by).toBe("匿名");
  });
});

describe("GET /calls/dashboard — 応答契約", () => {
  it("3 セクションと callTag のキーが契約どおり", async () => {
    const { body } = await get();
    expect(body).toMatchObject({
      generatedAt: expect.any(Number),
      songsWithCalls: [
        {
          songId: "cg_お願いシンデレラ",
          callLines: 18,
          callCount: 42,
          updatedAt: expect.any(Number),
          updatedBy: "ぷろでゅーさー",
        },
      ],
      recentEdits: [
        {
          id: 12,
          songId: "cg_お願いシンデレラ",
          at: expect.any(Number),
          by: "ぷろでゅーさー",
          callLinesBefore: 0,
          callLinesAfter: 18,
          callCountBefore: 0,
          callCountAfter: 42,
          summary: "calls 0->42, lines 0->18",
        },
      ],
      // 歌詞が published でタグが付いていてコールが無い曲だけが並ぶ。
      taggedWithoutCalls: ["ml_Thank_You"],
      callTag: { tagId: TAG.id, tagName: TAG.name, tagged: 3, withCalls: 1, withoutLyrics: 1 },
    });
  });

  it("時刻は epoch 秒 (iOS の .secondsSince1970)", async () => {
    const { body } = await get();
    const expected = Math.floor(Date.parse("2026-09-01T12:00:00Z") / 1000);
    expect(body.songsWithCalls[0].updatedAt).toBe(expected);
    expect(body.recentEdits[0].at).toBe(expected);
    // ミリ秒で返していないこと (iOS のデコードが落ちる)。
    expect(String(body.recentEdits[0].at)).toHaveLength(10);
  });

  it("メール混入の display_name はマスクされる", async () => {
    const { body } = await get((sql) => {
      if (sql.includes("FROM tags WHERE name")) return TAG;
      if (sql.includes("FROM song_call_stats s"))
        return [statsRow({ updated_by_name: "fuga.else@gmail.com" })];
      if (sql.includes("FROM call_edit_history h"))
        return [historyRow({ by_name: "fuga.else@gmail.com" })];
      return undefined;
    });
    expect(body.songsWithCalls[0].updatedBy).toBe("f***");
    expect(body.recentEdits[0].by).toBe("f***");
    expect(JSON.stringify(body)).not.toContain("@");
  });

  it("エッジキャッシュに載る Cache-Control を返す", async () => {
    const { res } = await get();
    expect(res.headers.get("Cache-Control")).toBe("public, max-age=1800");
  });

  it("「コール曲」タグが無ければ ③ を空にして 200 (500 にしない)", async () => {
    const { res, body, stub } = await get(defaultResponder({ tag: null }));
    expect(res.status).toBe(200);
    expect(body.taggedWithoutCalls).toEqual([]);
    expect(body.callTag).toBeNull();
    // タグが引けないときは song_tags を舐めない。
    expect(stub.sql()).not.toMatch(/FROM song_tags/);
    // ①② は独立して出る。
    expect(body.songsWithCalls).toHaveLength(1);
    expect(body.recentEdits).toHaveLength(1);
  });
});

describe("GET /calls/dashboard — 上限", () => {
  it("SQL の LIMIT を素通りしても応答はサーバ定数の件数で頭打ちになる", async () => {
    const many = (n: number, make: (i: number) => unknown) =>
      Array.from({ length: n }, (_, i) => make(i));
    const { body } = await get((sql) => {
      if (sql.includes("FROM tags WHERE name")) return TAG;
      if (sql.includes("FROM song_call_stats s"))
        return many(300, (i) => statsRow({ song_id: `s${i}` }));
      if (sql.includes("FROM call_edit_history h"))
        return many(100, (i) => historyRow({ id: i }));
      if (sql.includes("FROM song_tags st"))
        return many(500, (i) => taggedRow({ song_id: `t${i}` }));
      return undefined;
    });
    expect(body.songsWithCalls).toHaveLength(200);
    expect(body.recentEdits).toHaveLength(30);
    expect(body.taggedWithoutCalls).toHaveLength(100);
    // 上限で切っても内訳は母集合ぜんぶを数えている (「あと何曲あるか」が分かる)。
    expect(body.callTag.tagged).toBe(500);
  });

  it("クエリパラメータでは上限を動かせない (キャッシュキーを 1 つに保つ)", async () => {
    const stub = stubD1(defaultResponder());
    const url = new URL("https://api.example.com/calls/dashboard?limit=9999");
    const res = await handleCallsDashboard({
      request: new Request(url.toString()),
      env: { DB: stub.db } as unknown as RouteContext["env"],
      url,
      // ルータが渡す path にクエリは含まれない = パラメータは一切見ていない。
      path: "/calls/dashboard",
      ...responders,
    });
    const bound = stub.calls.flatMap((c) => c.params);
    expect(bound).not.toContain("9999");
    expect(bound).not.toContain(9999);
    expect(res!.status).toBe(200);
  });
});
