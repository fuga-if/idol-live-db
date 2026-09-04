import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { handleLyrics } from "../src/routes/lyrics";
import { handleSongDetail } from "../src/routes/song_detail";
import { signSessionToken } from "../src/auth";
import type { RouteContext } from "../src/routes/context";
import { responders, stubD1, type Responder } from "./support/stub_d1";

// JASRAC 年次利用曲目報告の 19 項目目「リクエスト回数」は、この 1 行のログだけを数える。
// D1 に列を足さないのは、閲覧のたびに書き込むと固定無料枠のホットパスが読み取りから
// 書き込みに変わるため (ランニングコスト 0 の制約)。
//
// ここで固定するのは 2 つ:
//   1. **歌詞を返したときだけ**出る (401/404/429 や歌詞未投入では出ない)。出しすぎると
//      報告が過大になり、出さなすぎると過少になる。どちらも許諾条件の報告として誤り。
//   2. **song_id 以外を載せない**。uid や IP を載せると、Workers Logs が
//      「誰が何を読んだか」の閲覧履歴になる。

const SECRET = "test-session-secret-that-is-long-enough";
const UID = "001094.fedcba9876543210";
let TOKEN = "";

beforeAll(async () => {
  TOKEN = await signSessionToken(UID, SECRET);
});

const SONG_ID = "cg_お願いシンデレラ";
const LINES = JSON.stringify([
  { id: "ll_1", ord: 0, kind: "lyric", text: "きみのこえ", section: null, start_ms: null },
]);

interface Scenario {
  /** song_lyrics の 1 行。null なら歌詞未投入。 */
  header?: unknown;
  /** IP バースト枠の現在値 (30 で上限)。 */
  ipCount?: number;
}

function responder(sc: Scenario = {}): Responder {
  return (sql) => {
    if (sql.includes("FROM song_lyrics")) {
      return "header" in sc
        ? sc.header
        : { source: null, updated_at: "2026-09-01 12:00:00", lines_json: LINES, status: "published" };
    }
    if (sql.includes("FROM api_rate_limits")) return { count: sc.ipCount ?? 0 };
    if (sql.includes("FROM users")) return { is_admin: 0 };
    return undefined;
  };
}

function ctxFor(path: string, db: D1Database, headers: Record<string, string> = {}): RouteContext {
  const url = new URL(`https://api.example.com${path}`);
  return {
    request: new Request(url.toString(), { method: "GET", headers }),
    env: { DB: db, SESSION_JWT_SECRET: SECRET, ADMIN_USER_IDS: "" } as unknown as RouteContext["env"],
    url,
    path,
    ...responders,
  };
}

/** console.log に出た lyrics_read だけを拾う。 */
function spyLogs(): { lines: string[] } {
  const lines: string[] = [];
  vi.spyOn(console, "log").mockImplementation((...args: unknown[]) => {
    const first = args[0];
    if (typeof first === "string" && first.includes("lyrics_read")) lines.push(first);
  });
  return { lines };
}

afterEach(() => vi.restoreAllMocks());

/** TOKEN は beforeAll で作られるので、参照は呼び出し時まで遅らせる。 */
const bearer = () => ({ Authorization: `Bearer ${TOKEN}` });
const lyricsPath = `/songs/${encodeURIComponent(SONG_ID)}/lyrics`;
const detailPath = `/songs/${encodeURIComponent(SONG_ID)}/detail`;

describe("GET /songs/:id/lyrics の利用ログ", () => {
  it("歌詞を返したときだけ 1 行出す", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder());
    const res = (await handleLyrics(ctxFor(lyricsPath, stub.db, bearer())))!;
    expect(res.status).toBe(200);
    expect(logs.lines).toHaveLength(1);
    expect(JSON.parse(logs.lines[0])).toEqual({ event: "lyrics_read", song_id: SONG_ID });
  });

  it("uid も IP も歌詞本文も載せない", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder());
    await handleLyrics(
      ctxFor(lyricsPath, stub.db, { ...bearer(), "CF-Connecting-IP": "203.0.113.9" })
    );
    // ログのキーは 2 つだけ。増やすと閲覧履歴になる。
    expect(Object.keys(JSON.parse(logs.lines[0])).sort()).toEqual(["event", "song_id"]);
    expect(logs.lines[0]).not.toContain(UID);
    expect(logs.lines[0]).not.toContain("203.0.113.9");
    expect(logs.lines[0]).not.toContain("きみのこえ");
  });

  it("未認証 (401) では出さない", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder());
    const res = (await handleLyrics(ctxFor(lyricsPath, stub.db)))!;
    expect(res.status).toBe(401);
    expect(logs.lines).toHaveLength(0);
  });

  it("歌詞未投入 (404) では出さない", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder({ header: null }));
    const res = (await handleLyrics(ctxFor(lyricsPath, stub.db, bearer())))!;
    expect(res.status).toBe(404);
    expect(logs.lines).toHaveLength(0);
  });

  it("未公開 (draft) を一般ユーザーが叩いた 404 でも出さない", async () => {
    const logs = spyLogs();
    const stub = stubD1(
      responder({ header: { source: null, updated_at: "2026-09-01 12:00:00", lines_json: LINES, status: "draft" } })
    );
    const res = (await handleLyrics(ctxFor(lyricsPath, stub.db, bearer())))!;
    expect(res.status).toBe(404);
    expect(logs.lines).toHaveLength(0);
  });

  it("IP バースト上限 (429) では出さない", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder({ ipCount: 30 }));
    const res = (await handleLyrics(ctxFor(lyricsPath, stub.db, bearer())))!;
    expect(res.status).toBe(429);
    expect(logs.lines).toHaveLength(0);
  });
});

describe("GET /songs/:id/detail の利用ログ", () => {
  it("Bearer 付きで歌詞を同梱したときは出す (経路で数え方を変えない)", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder());
    const res = (await handleSongDetail(ctxFor(detailPath, stub.db, bearer())))!;
    expect(res.status).toBe(200);
    expect((await res.json() as any).lyrics).not.toBeNull();
    expect(logs.lines).toHaveLength(1);
    expect(JSON.parse(logs.lines[0])).toEqual({ event: "lyrics_read", song_id: SONG_ID });
  });

  it("未認証 (歌詞を同梱しない) では出さない", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder());
    const res = (await handleSongDetail(ctxFor(detailPath, stub.db)))!;
    expect((await res.json() as any).lyrics).toBeNull();
    expect(logs.lines).toHaveLength(0);
  });

  it("歌詞未投入の曲を開いても出さない", async () => {
    const logs = spyLogs();
    const stub = stubD1(responder({ header: null }));
    const res = (await handleSongDetail(ctxFor(detailPath, stub.db, bearer())))!;
    expect((await res.json() as any).lyrics).toBeNull();
    expect(logs.lines).toHaveLength(0);
  });
});
