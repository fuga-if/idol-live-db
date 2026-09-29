// ルートの中で投げられた例外は、どのルートでも request id 付きの 500 (JSON) になり、
// D1 のエラー文は応答に出ずログにだけ残る。
// (以前は依存注入の方式のルートを await せずに返していて、失敗が入口の catch を素通りしていた)

import { env } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";

const UID = "001094.route-errors";

/** どの文を用意しても投げる D1。 */
const brokenDb = {
  ...env.DB,
  prepare: () => {
    throw new Error("D1_ERROR: no such table: secret_detail");
  },
  batch: () => Promise.reject(new Error("D1_ERROR: no such table: secret_detail")),
} as unknown as D1Database;

afterEach(() => vi.restoreAllMocks());

const IDOL_OP = {
  op: "update", recordType: "Idol", recordName: "sc_x",
  fields: { name: "x", brandId: "sc", sortOrder: 1, color: "#FFBAD6" },
};

describe("ルートの中の例外", () => {
  it.each([
    ["GET", "/edits", undefined],
    ["GET", "/me/edits", undefined],
    ["POST", "/edits/1/good", undefined],
    ["DELETE", "/edits/1/good", undefined],
    ["POST", "/edits/1/revert", undefined],
    ["POST", "/edit-requests", { ops: [IDOL_OP] }],
    ["POST", "/transfer", { payload: "x" }],
    ["GET", "/transfer/ABCDEFGHJK", undefined],
    ["POST", "/admin/revert-user", { userId: "001094.other" }],
    ["GET", "/admin/users/001094.other/edits", undefined],
  ] as const)("%s %s は request id 付きの 500", async (method, path, body) => {
    const logged: unknown[][] = [];
    vi.spyOn(console, "error").mockImplementation((...args: unknown[]) => void logged.push(args));
    const res = await callJson(method, path, {
      headers: await bearer(UID),
      body,
      env: makeEnv({ DB: brokenDb, ADMIN_USER_IDS: UID, GITHUB_TOKEN: "t" }),
    });
    expect(res.status).toBe(500);
    const requestId = res.res.headers.get("X-Request-Id");
    expect(requestId).toBeTruthy();
    expect(res.body).toEqual({ error: `Internal error (request id: ${requestId})` });
    expect(JSON.stringify(logged)).toContain("route_failed");
    expect(JSON.stringify(logged)).toContain("secret_detail");
  });
});
