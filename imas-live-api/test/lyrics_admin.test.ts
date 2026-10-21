// 歌詞の管理用エンドポイント (routes/lyrics.ts)。どれもモデレーター (X-Push-Token か admin) だけが叩ける。
//   POST /admin/lyrics/status       公開状態をまとめて切り替える (本文は触らない)
//   GET  /admin/lyrics/quota        掲載曲数の集計
//   POST /admin/lyrics/ruby-list    《》振り仮名の一覧 (見直し用。行の本文は返さない)
//   POST /admin/lyrics/ruby-revert  振り仮名を括弧に戻す / 親字の頭を決め直す / 括弧を振り仮名にする
// 本文には実在の歌詞を使わない (意味の無い文字列だけ)。

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";

const PUSH_TOKEN = "push-token-for-admin-test";
const PUSH = { "X-Push-Token": PUSH_TOKEN };
const env = () => makeEnv({ LYRICS_PUSH_TOKEN: PUSH_TOKEN });

beforeEach(() => void vi.spyOn(console, "log").mockImplementation(() => {}));
afterEach(() => vi.restoreAllMocks());

async function seed(songId: string, status: "draft" | "published", texts: string[] = ["てすと"]) {
  const lines = texts.map((text, ord) => ({ id: `${songId}_l${ord}`, ord, kind: "lyric", text, section: null, calls: [] }));
  await exec("INSERT INTO song_lyrics (song_id, status, lines_json) VALUES (?, ?, ?)", songId, status, JSON.stringify(lines));
}

async function post(path: string, body: unknown, headers: Record<string, string> = PUSH) {
  return callJson("POST", path, { headers, body, env: env() });
}

async function linesOf(songId: string): Promise<string[]> {
  const r = await row<{ lines_json: string }>("SELECT lines_json FROM song_lyrics WHERE song_id = ?", songId);
  return JSON.parse(r!.lines_json).map((l: { text: string }) => l.text);
}

describe("モデレーターの判定", () => {
  it("push token が違う・一般ユーザーは 401。admin のセッションは通る", async () => {
    await insertUser("001094.user");
    await insertUser("001094.admin", { isAdmin: true });
    for (const [method, path] of [
      ["POST", "/admin/lyrics/status"],
      ["GET", "/admin/lyrics/quota"],
      ["POST", "/admin/lyrics/ruby-list"],
      ["POST", "/admin/lyrics/ruby-revert"],
    ] as const) {
      expect((await callJson(method, path, { headers: { "X-Push-Token": "wrong" }, body: method === "POST" ? {} : undefined, env: env() })).status).toBe(401);
      expect((await callJson(method, path, { headers: await bearer("001094.user"), body: method === "POST" ? {} : undefined, env: env() })).status).toBe(401);
    }
    expect((await callJson("GET", "/admin/lyrics/quota", { headers: await bearer("001094.admin"), env: env() })).status).toBe(200);
  });
});

describe("POST /admin/lyrics/status", () => {
  it("状態の違う曲だけを数えて切り替える。初回公開の時刻は最初の 1 回だけ残す", async () => {
    await seed("s1", "draft");
    await seed("s2", "draft");
    await seed("s3", "published");
    await exec("UPDATE song_lyrics SET first_published_at = '2025-01-01 00:00:00' WHERE song_id = 's3'");

    const pub = await post("/admin/lyrics/status", { song_ids: ["s1", "s2", "s3", "missing"], status: "published" });
    expect(pub.status).toBe(200);
    expect(pub.body).toEqual({ status: "published", requested: 4, updated: 2 });
    const first = await rows<{ song_id: string; status: string; first_published_at: string | null }>(
      "SELECT song_id, status, first_published_at FROM song_lyrics ORDER BY song_id"
    );
    expect(first.map((r) => r.status)).toEqual(["published", "published", "published"]);
    expect(first[0].first_published_at).not.toBeNull();
    expect(first[2].first_published_at).toBe("2025-01-01 00:00:00");

    // draft に戻して再公開しても first_published_at は動かない
    const s1First = first[0].first_published_at;
    await exec("UPDATE song_lyrics SET first_published_at = '2025-06-01 00:00:00' WHERE song_id = 's1'");
    expect((await post("/admin/lyrics/status", { song_ids: ["s1"], status: "draft" })).body.updated).toBe(1);
    expect((await post("/admin/lyrics/status", { song_ids: ["s1"], status: "published" })).body.updated).toBe(1);
    expect(await row("SELECT first_published_at FROM song_lyrics WHERE song_id = 's1'")).toEqual({ first_published_at: "2025-06-01 00:00:00" });
    expect(s1First).toBeTruthy();
  });

  it.each<[string, unknown, string]>([
    ["status が不正", { song_ids: ["s1"], status: "hidden" }, "status must be 'draft' or 'published'"],
    ["song_ids が空", { song_ids: [], status: "draft" }, "song_ids required"],
    ["song_ids が配列でない", { song_ids: "s1", status: "draft" }, "song_ids required"],
    ["空文字の id", { song_ids: ["s1", ""], status: "draft" }, "song_ids must be non-empty strings"],
    ["数値の id", { song_ids: [1], status: "draft" }, "song_ids must be non-empty strings"],
    ["本文が JSON でない", "{", "status must be 'draft' or 'published'"],
  ])("%s は 400", async (_label, body, message) => {
    const res = await post("/admin/lyrics/status", body);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: message });
  });

  it("件数の上限を超えると 400", async () => {
    const res = await post("/admin/lyrics/status", { song_ids: Array.from({ length: 1000 }, (_, i) => `s${i}`), status: "draft" });
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/^song_ids must be at most \d+$/);
  });
});

describe("GET /admin/lyrics/quota", () => {
  it("公開と下書きの曲数を返す (本文は返さない)", async () => {
    await seed("s1", "published");
    await seed("s2", "published");
    await seed("s3", "draft");
    const res = await callJson("GET", "/admin/lyrics/quota", { headers: PUSH, env: env() });
    expect(res.body).toEqual({ license: "J260943703", published: 2, draft: 1 });
    expect(res.res.headers.get("Cache-Control")).toContain("no-store");
  });
});

describe("POST /admin/lyrics/ruby-list", () => {
  it("曲 id・行の番号・位置・親字・読みだけを返し、limit ごとに続きを辿れる", async () => {
    await seed("a1", "published", ["見本字《みほんじ》の行", "ふつうの行", "あの｜STAR《ほし》と記憶抱《イダ》く"]);
    await seed("a2", "draft", ["二《ふた》つ目"]);
    await seed("a3", "published", ["振り仮名なし"]);

    const page1 = await post("/admin/lyrics/ruby-list", { limit: 2 });
    expect(page1.body).toEqual({
      items: [
        { songId: "a1", ord: 0, at: 3, base: "見本字", ruby: "みほんじ" },
        { songId: "a1", ord: 2, at: 7, base: "STAR", ruby: "ほし" },
        { songId: "a1", ord: 2, at: 15, base: "記憶抱", ruby: "イダ" },
        { songId: "a2", ord: 0, at: 1, base: "二", ruby: "ふた" },
      ],
      next: "a2",
    });
    expect(JSON.stringify(page1.body)).not.toContain("の行");

    const page2 = await post("/admin/lyrics/ruby-list", { after: page1.body.next, limit: 2 });
    expect(page2.body).toEqual({ items: [], next: null });
  });

  it("親字は末尾 12 文字、読みは先頭 20 文字に切る。閉じの無い《や親字の無い《》は数えない", async () => {
    await seed("b1", "published", [
      `${"漢".repeat(15)}《${"よ".repeat(25)}》`,
      "かな《よみ》",
      "閉じない《よみ",
      "空《》",
    ]);
    const res = await post("/admin/lyrics/ruby-list", {});
    expect(res.body.items).toEqual([{ songId: "b1", ord: 0, at: 15, base: "漢".repeat(12), ruby: "よ".repeat(20) }]);
  });
});

describe("POST /admin/lyrics/ruby-revert", () => {
  async function put(songId: string, texts: string[]) {
    const res = await callJson("PUT", `/admin/lyrics/${songId}`, {
      headers: PUSH, env: env(),
      body: { status: "published", lines: texts.map((text) => ({ kind: "lyric", text })) },
    });
    expect(res.status).toBe(200);
  }

  async function indexed(gram: string): Promise<boolean> {
    const list = await rows<{ song_ids: string }>("SELECT song_ids FROM lyrics_gram_index WHERE gram = ?", gram);
    return list.some((r) => r.song_ids.split("\n").includes("r1"));
  }

  it("振り仮名を括弧に戻し、検索用の本文と索引も書き直す", async () => {
    await put("r1", ["見本《みほん》だ", "もう一行"]);
    expect(await row("SELECT body FROM song_lyrics WHERE song_id = 'r1'")).toEqual({ body: "見本だ\nもう一行" });
    expect(await indexed("ミホ")).toBe(false);

    const res = await post("/admin/lyrics/ruby-revert", { items: [{ songId: "r1", ord: 0, at: 2 }] });
    expect(res.body).toEqual({ requested: 1, reverted: 1 });
    expect(await linesOf("r1")).toEqual(["見本（みほん）だ", "もう一行"]);
    expect(await row("SELECT body FROM song_lyrics WHERE song_id = 'r1'")).toEqual({ body: "見本（みほん）だ\nもう一行" });
    // 括弧の中の読みが本文に戻ったので、索引にも載る
    expect(await indexed("ミホ")).toBe(true);
  });

  it("base を付けると親字の頭を決め直す。toRuby は括弧を振り仮名にする。同じ行は後ろから当てる", async () => {
    // 漢字の直後でない括弧は取り込みで振り仮名にならない (当て字は親字の頭を選んで振り仮名にする)
    await put("r1", ["記憶抱《イダ》くSTAR（ほし）"]);
    const res = await post("/admin/lyrics/ruby-revert", {
      items: [
        { songId: "r1", ord: 0, at: 3, base: 2 },
        { songId: "r1", ord: 0, at: 12, base: 8, toRuby: true },
      ],
    });
    expect(res.body).toEqual({ requested: 2, reverted: 2 });
    expect(await linesOf("r1")).toEqual(["記憶｜抱《イダ》く｜STAR《ほし》"]);
  });

  it("当てられない位置・知らない曲は数えず、本文も変えない", async () => {
    await put("r1", ["ふつうの行"]);
    const before = await row("SELECT lines_json, updated_at FROM song_lyrics WHERE song_id = 'r1'");
    const res = await post("/admin/lyrics/ruby-revert", {
      items: [{ songId: "r1", ord: 0, at: 1 }, { songId: "r1", ord: 9, at: 0 }, { songId: "nope", ord: 0, at: 0 }],
    });
    expect(res.body).toEqual({ requested: 3, reverted: 0 });
    expect(await row("SELECT lines_json, updated_at FROM song_lyrics WHERE song_id = 'r1'")).toEqual(before);
  });

  it("items は 1〜500 件で、各件に songId・ord・at が要る", async () => {
    expect((await post("/admin/lyrics/ruby-revert", {})).body).toEqual({ error: "items must be 1..500" });
    expect((await post("/admin/lyrics/ruby-revert", { items: Array(501).fill({ songId: "a", ord: 0, at: 0 }) })).status).toBe(400);
    expect((await post("/admin/lyrics/ruby-revert", { items: [{ songId: "a", ord: "0", at: 0 }] })).body)
      .toEqual({ error: "each item needs songId, ord, at" });
  });

  it("索引の書き直しに失敗しても本文の変更は残し、ログに出す", async () => {
    await put("r1", ["見本《みほん》だ"]);
    const errors: unknown[][] = [];
    vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => void errors.push(args));
    const base = env();
    const db = base.DB;
    const failingIndex = {
      prepare: (sql: string) => {
        if (/lyrics_gram_index/.test(sql)) throw new Error("index unavailable");
        return db.prepare(sql);
      },
      batch: db.batch.bind(db),
    } as unknown as D1Database;
    const res = await callJson("POST", "/admin/lyrics/ruby-revert", {
      headers: PUSH, env: { ...base, DB: failingIndex }, body: { items: [{ songId: "r1", ord: 0, at: 2 }] },
    });
    expect(res.body).toEqual({ requested: 1, reverted: 1 });
    expect(await linesOf("r1")).toEqual(["見本（みほん）だ"]);
    expect(errors.map((e) => e[0])).toEqual(["lyrics_gram_index_update_failed"]);
  });
});
