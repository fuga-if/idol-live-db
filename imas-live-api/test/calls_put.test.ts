import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { handleLyricsCalls } from "../src/routes/calls";
import { signSessionToken } from "../src/auth";
import type { RouteContext } from "../src/routes/context";
import { responders, stubD1, type Responder, type StubD1 } from "./support/stub_d1";

// PUT /songs/:song_id/calls の回帰網。
// この経路には既にクライアント (iOS のコール編集画面) が付いているので、
// **応答の形・ステータス・Cache-Control は 1 バイトも変えてはいけない**。
// 統計 (0032) と履歴はその上に足した副次データで、失敗しても保存を落とさない。

const SECRET = "test-session-secret-that-is-long-enough";
const UID = "001094.fedcba9876543210";
let TOKEN = "";

beforeAll(async () => {
  TOKEN = await signSessionToken(UID, SECRET);
});

const LINE_ID = "ll_1";
const EXISTING_LINES = [
  { id: LINE_ID, ord: 0, kind: "lyric", text: "きみのこえ", section: null, start_ms: null,
    clap: null, calls: [] },
];
const HEADER = {
  source: "CD ブックレット",
  status: "published",
  updated_at: "2026-09-01 12:00:00",
  lines_json: JSON.stringify(EXISTING_LINES),
};

/** BODY を保存した後の姿 (無変更の再保存・stale 貼り直しのテストで使う)。 */
const SAVED_LINES = [
  {
    ...EXISTING_LINES[0],
    clap: "back_beat",
    calls: [
      {
        id: "cl_existing",
        start: 0,
        end: 5,
        anchorText: "きみのこえ",
        text: "ハイ！ハイ！",
        emphasis: "normal",
        timing: "after",
      },
    ],
  },
];

/** 運用者トークン (歌詞投入 CLI 用)。 */
const PUSH_TOKEN = "push-token-for-test";

/** 1 件コールを付ける保存ボディ。 */
const BODY = {
  lines: [
    {
      id: LINE_ID,
      clap: "back_beat",
      calls: [{ start: 0, end: 5, anchorText: "きみのこえ", text: "ハイ！ハイ！", timing: "after" }],
    },
  ],
};

interface Scenario {
  banned?: number;
  header?: unknown;
  /** 履歴の 30 分まとめ UPDATE が何行に当たったか。 */
  historyMerged?: number;
  /** 履歴の書き込みで D1 が落ちる状況を作る。 */
  historyThrows?: boolean;
}

function responder(sc: Scenario = {}): Responder {
  // 保存した lines_json を覚えて後続の SELECT に返す (ハンドラは保存後にもう一度
  // 読み直して応答を作るので、覚えないと「保存前の姿」を返してしまう)。
  let header: unknown = "header" in sc ? sc.header : { ...HEADER };
  return (sql, params) => {
    if (sql.includes("is_banned")) return { is_banned: sc.banned ?? 0 };
    if (sql.includes("INSERT INTO rate_limits")) return { count: 1 };
    if (sql.includes("UPDATE song_lyrics SET lines_json")) {
      if (header) header = { ...(header as object), lines_json: params[0] };
      return undefined;
    }
    if (sql.includes("FROM song_lyrics WHERE song_id")) return header;
    if (sql.includes("UPDATE call_edit_history")) {
      if (sc.historyThrows) throw new Error("D1_ERROR: no such table");
      return { success: true, meta: { changes: sc.historyMerged ?? 0 } };
    }
    if (sql.includes("INSERT INTO call_edit_history")) {
      if (sc.historyThrows) throw new Error("D1_ERROR: no such table");
      return { success: true, meta: { changes: 1 } };
    }
    return undefined;
  };
}

/** waitUntil に積まれた副作用 (ダッシュボードのキャッシュ破棄) は、テストを抜ける前に
 *  必ず待つ。待たないと Workers ランタイムがテスト外のストレージアクセスとして落とす。 */
const pending: Promise<unknown>[] = [];

function put(
  stub: StubD1,
  body: unknown = BODY,
  headers: Record<string, string> = { Authorization: `Bearer ${TOKEN}` }
): RouteContext {
  const path = "/songs/cg_%E3%81%8A%E9%A1%98%E3%81%84/calls";
  const url = new URL(`https://api.example.com${path}`);
  return {
    request: new Request(url.toString(), { method: "PUT", headers, body: JSON.stringify(body) }),
    env: { DB: stub.db, SESSION_JWT_SECRET: SECRET } as unknown as RouteContext["env"],
    url,
    path,
    waitUntil: (p) => void pending.push(p.catch(() => undefined)),
    ...responders,
  };
}

/** ハンドラを呼び、waitUntil ぶんを待ってから応答を返す。 */
async function save(ctx: RouteContext): Promise<Response | null> {
  const res = await handleLyricsCalls(ctx);
  await Promise.all(pending.splice(0));
  return res;
}

/** ダッシュボードのキャッシュ破棄を記録する (テスト環境の Cache には触らせない)。 */
function spyCachePurge() {
  const purged: Request[] = [];
  vi.spyOn(caches.default, "delete").mockImplementation(async (req: RequestInfo | URL) => {
    purged.push(req as Request);
    return true;
  });
  return purged;
}

afterEach(() => vi.restoreAllMocks());

const sqlOf = (stub: StubD1) => stub.calls.map((c) => c.sql).join("\n");

describe("PUT /songs/:id/calls — 既存クライアント契約 (変えてはいけない)", () => {
  it("保存に成功すると 200 で歌詞ペイロード + status を返し、no-store を付ける", async () => {
    const stub = stubD1(responder());
    const res = (await save(put(stub)))!;
    expect(res.status).toBe(200);
    expect(res.headers.get("Cache-Control")).toBe("no-store");
    const body = (await res.json()) as any;
    // GET /songs/:id/lyrics と同じ形 + status。編集画面が再取得せずに済む契約。
    expect(Object.keys(body).sort()).toEqual(["lines", "songId", "source", "status", "updatedAt"]);
    expect(body.status).toBe("published");
    expect(body.lines[0]).toMatchObject({ id: LINE_ID, clap: "back_beat" });
    expect(body.lines[0].calls[0]).toMatchObject({ text: "ハイ！ハイ！", anchorText: "きみのこえ" });
  });

  it("未ログインは 401、BAN は 403 (統計にも履歴にも触らない)", async () => {
    const anon = stubD1(responder());
    expect((await save(put(anon, BODY, {})))!.status).toBe(401);

    const banned = stubD1(responder({ banned: 1 }));
    expect((await save(put(banned)))!.status).toBe(403);

    for (const stub of [anon, banned]) {
      expect(sqlOf(stub)).not.toMatch(/song_call_stats|call_edit_history/);
    }
  });

  it("PUT 以外・別パスでは null を返す", async () => {
    const stub = stubD1(responder());
    const ctx = put(stub);
    expect(await save({ ...ctx, path: "/songs/x/lyrics" })).toBeNull();
    expect(
      await save({
        ...ctx,
        request: new Request(ctx.url.toString(), { method: "GET" }),
      })
    ).toBeNull();
  });

  it("歌詞の無い曲は 404 で、統計も履歴も 1 文も発行しない", async () => {
    const stub = stubD1(responder({ header: null }));
    const res = (await save(put(stub)))!;
    expect(res.status).toBe(404);
    expect(sqlOf(stub)).not.toMatch(/song_call_stats|call_edit_history/);
  });
});

describe("PUT /songs/:id/calls — 統計と履歴", () => {
  it("歌詞行と統計を同じ batch で書く (歌詞だけ書けて統計が古い状態を作らない)", async () => {
    const stub = stubD1(responder());
    await save(put(stub));
    const batched = stub.calls.filter((c) => c.kind === "batch");
    expect(batched).toHaveLength(2);
    expect(batched[0].sql).toMatch(/UPDATE song_lyrics SET lines_json/);
    expect(batched[1].sql).toMatch(/INSERT INTO song_call_stats/);
    // 数えた結果 (1 行 / 1 コール) と編集者がそのまま入る。
    expect(batched[1].params).toEqual([expect.any(String), 1, 1, UID]);
  });

  it("履歴を 1 行積む (直近にまとめる相手がいなければ INSERT)", async () => {
    const stub = stubD1(responder({ historyMerged: 0 }));
    await save(put(stub));
    const inserted = stub.calls.find((c) => c.sql.includes("INSERT INTO call_edit_history"));
    expect(inserted).toBeDefined();
    // before(0,0) → after(lines 1, calls 1)。
    expect(inserted!.params.slice(2)).toEqual([0, 1, 0, 1]);
  });

  it("30 分以内の同じ人の再保存は既存行の更新で済ませ、INSERT を発行しない", async () => {
    const stub = stubD1(responder({ historyMerged: 1 }));
    await save(put(stub));
    expect(sqlOf(stub)).toMatch(/UPDATE call_edit_history/);
    expect(sqlOf(stub)).not.toMatch(/INSERT INTO call_edit_history/);
  });

  it("まとめ対象は「その曲の直近行が自分のものである」ときだけ (他人の編集は飲み込まない)", async () => {
    const stub = stubD1(responder());
    await save(put(stub));
    const merge = stub.calls.find((c) => c.sql.includes("UPDATE call_edit_history"))!;
    // 副問い合わせは song_id だけで直近行を引き、user_id の一致は外側で見る。
    expect(merge.sql).toMatch(/WHERE song_id = \? ORDER BY id DESC LIMIT 1/);
    expect(merge.sql).toMatch(/AND user_id = \?/);
    // 時間幅も SQL に埋め込まずバインドする (動的 SQL 断片を作らない規律)。
    expect(merge.sql).toMatch(/at >= datetime\('now', \?\)/);
    expect(merge.params).toContain("-30 minutes");
  });

  it("履歴の書き込みが落ちても保存は 200 (副次データで保存を失敗にしない)", async () => {
    const stub = stubD1(responder({ historyThrows: true }));
    const res = (await save(put(stub)))!;
    expect(res.status).toBe(200);
    expect(sqlOf(stub)).toMatch(/INSERT INTO song_call_stats/);
  });

  it("運用者トークンでの投入は履歴を書かず、統計の編集者を NULL にする", async () => {
    // 歌詞投入 CLI からの一括投入は「みんなの編集」ではない。最近の編集に運用者の
    // 作業が並ぶと、ユーザーが書いたコールが見えなくなる。
    const stub = stubD1(responder());
    const ctx = put(stub, BODY, { "X-Push-Token": PUSH_TOKEN });
    const res = (await save({
      ...ctx,
      env: { ...ctx.env, LYRICS_PUSH_TOKEN: PUSH_TOKEN } as RouteContext["env"],
    }))!;
    expect(res.status).toBe(200);
    const upsert = stub.calls.find((c) => c.sql.includes("INSERT INTO song_call_stats"))!;
    expect(upsert.params).toEqual([expect.any(String), 1, 1, null]);
    expect(sqlOf(stub)).not.toMatch(/call_edit_history/);
    // レート枠も運用者専用のものを使う (一般ユーザーの "edit" 枠を食わない)。
    const rl = stub.calls.find((c) => c.sql.includes("INSERT INTO rate_limits"))!;
    expect(rl.params).toContain("lyrics_calls");
  });

  it("保存後にダッシュボードのエッジキャッシュを捨てる", async () => {
    const purged = spyCachePurge();
    const stub = stubD1(responder());
    await save(put(stub));
    expect(purged).toHaveLength(1);
    // index.ts のキャッシュキーと同じ形 (URL のみ・GET) でないと 1 件も消えない。
    expect(purged[0].url).toBe("https://api.example.com/calls/dashboard");
    expect(purged[0].method).toBe("GET");
  });

  it("無変更の保存ではキャッシュを捨てない (無駄なミスを増やさない)", async () => {
    const purged = spyCachePurge();
    const stub = stubD1(responder({ header: { ...HEADER, lines_json: JSON.stringify(SAVED_LINES) } }));
    await save(put(stub));
    expect(purged).toHaveLength(0);
  });

  it("アンカーの貼り直し (stale を落とすだけ) も編集として記録する", async () => {
    // 歌詞差し替えでズレた印が付いたコールを人が直す作業。件数も文言も変わらないが、
    // 見逃すとこの作業だけが履歴から消える。
    const staleLines = [
      {
        ...SAVED_LINES[0],
        calls: [{ ...SAVED_LINES[0].calls[0], stale: true }],
      },
    ];
    const stub = stubD1(responder({ header: { ...HEADER, lines_json: JSON.stringify(staleLines) } }));
    await save(put(stub));
    expect(sqlOf(stub)).toMatch(/INSERT INTO song_call_stats/);
    expect(sqlOf(stub)).toMatch(/call_edit_history/);
  });

  it("中身の変わらない保存では統計も履歴も書かない", async () => {
    // 既に同じコールが入っている状態で、同じ内容を保存し直す。
    const stub = stubD1(
      responder({ header: { ...HEADER, lines_json: JSON.stringify(SAVED_LINES) } })
    );
    const res = (await save(put(stub)))!;
    expect(res.status).toBe(200);
    expect(sqlOf(stub)).not.toMatch(/song_call_stats|call_edit_history/);
    // 歌詞行の保存自体は従来どおり走る (挙動を変えない)。
    expect(sqlOf(stub)).toMatch(/UPDATE song_lyrics SET lines_json/);
  });
});
