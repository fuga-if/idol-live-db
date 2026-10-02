import { beforeAll, describe, expect, it } from "vitest";
import { handleLyricsTimings } from "../src/routes/timings";
import { validateTimingsBody, MAX_START_MS } from "../src/lyrics_timings";
import { signSessionToken } from "../src/auth";
import type { RouteContext } from "../src/routes/context";
import { responders, stubD1, type Responder, type StubD1 } from "./support/stub_d1";

// PUT /songs/:song_id/timings — 歌詞行の再生位置の保存。
// 本文を書き換えられないこと・応答に本文が載らないこと・コールを消さないことを固定する。

const SECRET = "test-session-secret-that-is-long-enough";
const UID = "001094.fedcba9876543210";
let TOKEN = "";
beforeAll(async () => {
  TOKEN = await signSessionToken(UID, SECRET);
});

const CALL = { id: "cl_1", start: 0, end: 0, anchorText: "", text: "ハイ！", emphasis: "normal", timing: "after" };
const LINES = [
  { id: "ll_1", ord: 0, kind: "lyric", text: "きみのこえ", section: null, start_ms: null, clap: "ppph", calls: [CALL] },
  // migration 0027 が書いた形 (キーが startMs)。
  { id: "ll_2", ord: 1, kind: "lyric", text: "とどいて", section: null, startMs: 9000 },
];

function responder(status = "published"): { r: Responder; written: () => string | null } {
  let written: string | null = null;
  const r: Responder = (sql, params) => {
    if (sql.includes("is_banned")) return { is_banned: 0 };
    if (sql.includes("INSERT INTO rate_limits")) return { count: 1 };
    if (sql.includes("UPDATE song_lyrics SET lines_json")) {
      written = params[0] as string;
      return { success: true, meta: { changes: 1 } };
    }
    if (sql.includes("FROM song_lyrics WHERE song_id")) return { status, lines_json: JSON.stringify(LINES) };
    return undefined;
  };
  return { r, written: () => written };
}

function put(stub: StubD1, body: unknown, auth = true): RouteContext {
  const path = "/songs/cg_song/timings";
  const url = new URL(`https://api.example.com${path}`);
  const headers: Record<string, string> = auth ? { Authorization: `Bearer ${TOKEN}` } : {};
  return {
    request: new Request(url.toString(), { method: "PUT", headers, body: JSON.stringify(body) }),
    env: { DB: stub.db, SESSION_JWT_SECRET: SECRET } as unknown as RouteContext["env"],
    url,
    path,
    ...responders,
  };
}

describe("validateTimingsBody", () => {
  const ids = new Set(["a", "b"]);
  it("正規化する", () => {
    const r = validateTimingsBody({ lines: [{ id: "a", startMs: 1200 }, { id: "b", startMs: null }] }, ids);
    expect(r.ok && [...r.timings]).toEqual([["a", 1200], ["b", null]]);
  });
  it("snake_case (iOS の送信形) も受ける", () => {
    const r = validateTimingsBody({ lines: [{ id: "a", start_ms: 5 }] }, ids);
    expect(r.ok && r.timings.get("a")).toBe(5);
  });
  it("知らない行・重複・範囲外・小数を弾く", () => {
    expect(validateTimingsBody({ lines: [{ id: "x", startMs: 1 }] }, ids).ok).toBe(false);
    expect(validateTimingsBody({ lines: [{ id: "a", startMs: 1 }, { id: "a", startMs: 2 }] }, ids).ok).toBe(false);
    expect(validateTimingsBody({ lines: [{ id: "a", startMs: -1 }] }, ids).ok).toBe(false);
    expect(validateTimingsBody({ lines: [{ id: "a", startMs: MAX_START_MS + 1 }] }, ids).ok).toBe(false);
    expect(validateTimingsBody({ lines: [{ id: "a", startMs: 1.5 }] }, ids).ok).toBe(false);
    expect(validateTimingsBody({ lines: "a" }, ids).ok).toBe(false);
  });
});

describe("PUT /songs/:id/timings", () => {
  it("未ログインは 401", async () => {
    const { r } = responder();
    const res = await handleLyricsTimings(put(stubD1(r), { lines: [] }, false));
    expect(res?.status).toBe(401);
  });

  it("下書きは 404", async () => {
    const { r } = responder("draft");
    const res = await handleLyricsTimings(put(stubD1(r), { lines: [] }));
    expect(res?.status).toBe(404);
  });

  it("start_ms を書き、本文とコールはそのまま、応答に本文を含めない", async () => {
    const { r, written } = responder();
    const res = await handleLyricsTimings(put(stubD1(r), { lines: [{ id: "ll_1", startMs: 4321 }] }));
    expect(res?.status).toBe(200);
    expect(res?.headers.get("Cache-Control")).toBe("no-store");
    const body = await res!.text();
    expect(body).not.toContain("きみのこえ");
    expect(JSON.parse(body)).toEqual({
      songId: "cg_song",
      lines: [{ id: "ll_1", startMs: 4321 }, { id: "ll_2", startMs: null }],
    });
    const saved = JSON.parse(written()!);
    expect(saved[0]).toMatchObject({ text: "きみのこえ", clap: "ppph", calls: [CALL], start_ms: 4321 });
    // 古いキー startMs は落ちる (残すと null に戻した値が読み出しで蘇る)。
    expect(saved[1]).not.toHaveProperty("startMs");
    expect(saved[1].start_ms).toBeNull();
  });

  it("知らない行 id は 400", async () => {
    const { r } = responder();
    const res = await handleLyricsTimings(put(stubD1(r), { lines: [{ id: "ll_x", startMs: 1 }] }));
    expect(res?.status).toBe(400);
  });
});
