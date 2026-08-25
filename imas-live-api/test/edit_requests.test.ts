import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { handlePostEditRequests, type EditRequestDeps, type EditRequestEnv } from "../src/edit_requests";

// --- テスト用の最小スタブ ----------------------------------------------------
// D1 は is_banned を引くだけなので、prepare/bind/first の 3 段だけ用意する。
function stubDb(isBanned = 0) {
  return {
    prepare: () => ({ bind: () => ({ first: async () => ({ is_banned: isBanned }) }) }),
  } as unknown as D1Database;
}

function makeDeps(over: Partial<EditRequestDeps<EditRequestEnv>> = {}): EditRequestDeps<EditRequestEnv> {
  return {
    getAuthUser: async () => ({ uid: "001094.fedcba9876543210" }),
    checkRateLimit: async () => ({ allowed: true, used: 1, limit: 10, reset_at: "2026-08-20T00:00:00Z" }),
    json: (data, status = 200) => Response.json(data as object, { status }),
    error: (message, status = 400) => Response.json({ error: message }, { status }),
    rateLimitResponse: (used, limit, resetAt) =>
      Response.json({ error: "rate limited", used, limit, resetAt }, { status: 429 }),
    ...over,
  };
}

const ENV: EditRequestEnv = { DB: stubDb(), GITHUB_TOKEN: "t", GITHUB_REPO: "owner/repo" };

const post = (body: unknown) =>
  new Request("https://api.example.com/edit-requests", { method: "POST", body: JSON.stringify(body) });

/** GitHub API 呼び出しを記録しつつ 201 を返す。 */
function mockGitHub() {
  const calls: { path: string; payload: Record<string, string> }[] = [];
  vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
    calls.push({
      path: new URL(url).pathname,
      payload: JSON.parse(String(init.body)) as Record<string, string>,
    });
    return Response.json({ number: 123, html_url: "https://github.com/owner/repo/issues/123" }, { status: 201 });
  });
  return calls;
}

const idolOp = (color: string) => ({
  op: "update",
  recordType: "Idol",
  recordName: "sc_櫻木真乃",
  fields: { name: "櫻木真乃", brandId: "sc", sortOrder: 4001, color },
});

beforeEach(() => mockGitHub());
afterEach(() => vi.unstubAllGlobals());

describe("POST /edit-requests — 入口", () => {
  it("未ログインは 401", async () => {
    const res = await handlePostEditRequests(post({ ops: [idolOp("#FFBAD6")] }), ENV,
      makeDeps({ getAuthUser: async () => null }));
    expect(res.status).toBe(401);
  });

  it("ops が空なら 400", async () => {
    const res = await handlePostEditRequests(post({ ops: [] }), ENV, makeDeps());
    expect(res.status).toBe(400);
    await expect(res.json()).resolves.toMatchObject({ error: expect.stringContaining("ops is required") });
  });

  it("BAN 済みユーザーは 403", async () => {
    const res = await handlePostEditRequests(post({ ops: [idolOp("#FFBAD6")] }),
      { ...ENV, DB: stubDb(1) }, makeDeps());
    expect(res.status).toBe(403);
  });

  it("レート制限は 429", async () => {
    const res = await handlePostEditRequests(post({ ops: [idolOp("#FFBAD6")] }), ENV,
      makeDeps({
        checkRateLimit: async () => ({ allowed: false, used: 11, limit: 10, reset_at: "2026-08-20T00:00:00Z" }),
      }));
    expect(res.status).toBe(429);
  });

  it("GITHUB_TOKEN 未設定は 503", async () => {
    const res = await handlePostEditRequests(post({ ops: [idolOp("#FFBAD6")] }),
      { ...ENV, GITHUB_TOKEN: undefined }, makeDeps());
    expect(res.status).toBe(503);
  });
});

describe("POST /edit-requests — マスタ検証", () => {
  // 実際に発生した事故: color を "#" 抜きで送った 29 件がそのまま issue になり、
  // 取り込み側が「マスタ規約は #RRGGBB」と気付くまで放置された。
  it("不正な値は issue を作らずに 400 で返す", async () => {
    const calls = mockGitHub();
    const res = await handlePostEditRequests(post({ ops: [idolOp("FFBAD6")] }), ENV, makeDeps());
    expect(res.status).toBe(400);
    await expect(res.json()).resolves.toMatchObject({
      error: expect.stringContaining("ops[0]: color must be #RRGGBB"),
    });
    expect(calls).toHaveLength(0);
  });

  it("何番目の op が悪いかを返す", async () => {
    const res = await handlePostEditRequests(
      post({ ops: [idolOp("#FFBAD6"), idolOp("#144384"), idolOp("nope")] }), ENV, makeDeps());
    await expect(res.json()).resolves.toMatchObject({ error: expect.stringContaining("ops[2]") });
  });

  it("admin 専用 recordType は通さない", async () => {
    const res = await handlePostEditRequests(
      post({ ops: [{ op: "update", recordType: "Brand", recordName: "cg", fields: { name: "x" } }] }),
      ENV, makeDeps());
    expect(res.status).toBe(400);
  });

  it("正しい修正リクエストは 201 で issue になる", async () => {
    const calls = mockGitHub();
    const res = await handlePostEditRequests(
      post({ ops: [idolOp("#FFBAD6")], summary: "アイドル編集" }), ENV, makeDeps());
    expect(res.status).toBe(201);
    await expect(res.json()).resolves.toMatchObject({ ok: true, issueNumber: 123 });
    expect(calls).toHaveLength(1);
    expect(calls[0].path).toBe("/repos/owner/repo/issues");
    expect(calls[0].payload.title).toBe("[修正リクエスト] アイドル編集");
  });
});

describe("POST /edit-requests — issue の組み立て", () => {
  const setlistOp = (position: number) => ({
    op: "create",
    recordType: "SetlistItem",
    fields: { showId: "sh_x", songId: `sg_${position}`, position },
  });

  it("投稿者 ID は先頭 8 文字までしか出さない", async () => {
    const calls = mockGitHub();
    await handlePostEditRequests(post({ ops: [idolOp("#FFBAD6")] }), ENV, makeDeps());
    expect(calls[0].payload.body).toContain("`001094.f…`");
    expect(calls[0].payload.body).not.toContain("fedcba9876543210");
  });

  it("少数の op は field 単位の表を出し、raw を本文に同梱する", async () => {
    const calls = mockGitHub();
    await handlePostEditRequests(post({ ops: [setlistOp(1)] }), ENV, makeDeps());
    const body = calls[0].payload.body;
    expect(body).toContain("| field | 希望値 |");
    expect(body).toContain("<details><summary>raw (取り込み用)</summary>");
    expect(calls).toHaveLength(1); // コメント分割なし
  });

  it("op が多いと表を省略し、raw をコメントに分割して投稿する", async () => {
    const calls = mockGitHub();
    const ops = Array.from({ length: 600 }, (_, i) => setlistOp(i + 1));
    const res = await handlePostEditRequests(post({ ops }), ENV, makeDeps());
    expect(res.status).toBe(201);

    const [issue, ...comments] = calls;
    expect(issue.payload.body).toContain("op が 600 件あるため個別の表は省略");
    expect(issue.payload.body.length).toBeLessThanOrEqual(65536);
    expect(comments.length).toBeGreaterThan(0);
    for (const c of comments) {
      expect(c.path).toBe("/repos/owner/repo/issues/123/comments");
      expect(c.payload.body.length).toBeLessThanOrEqual(65536);
    }
    // 分割しても各チャンクは単体で JSON として読める。
    const parsed = comments.map((c) => JSON.parse(c.payload.body.split("```json\n")[1].split("\n```")[0]));
    expect(parsed.reduce((n, p) => n + p.ops.length, 0)).toBe(600);
  });

  it("raw の投稿に失敗したら 502 で「どこまで入ったか」を返す", async () => {
    let n = 0;
    vi.stubGlobal("fetch", async () => {
      n += 1;
      return n === 1
        ? Response.json({ number: 123, html_url: "https://github.com/owner/repo/issues/123" }, { status: 201 })
        : new Response("boom", { status: 500 });
    });
    const ops = Array.from({ length: 600 }, (_, i) => setlistOp(i + 1));
    const res = await handlePostEditRequests(post({ ops }), ENV, makeDeps());
    expect(res.status).toBe(502);
    await expect(res.json()).resolves.toMatchObject({
      error: expect.stringContaining("raw data is incomplete"),
    });
  });

  it("issue 作成自体が失敗したら 502", async () => {
    vi.stubGlobal("fetch", async () => new Response("nope", { status: 403 }));
    const res = await handlePostEditRequests(post({ ops: [idolOp("#FFBAD6")] }), ENV, makeDeps());
    expect(res.status).toBe(502);
  });
});
