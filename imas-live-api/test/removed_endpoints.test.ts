// 呼び出し元の無かった 3 本 (Q-10 で削除) は、ほかの無いパスと同じ 404 を返す。

import { describe, expect, it } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { rows } from "./support/d1";

const ADMIN = "001094.admin";

describe("削除したエンドポイント", () => {
  it.each([
    ["POST", "/app/integrity"],
    ["POST", "/admin/cloudkit/save"],
  ])("%s %s は 404", async (method, path) => {
    const res = await callJson(method, path, {
      headers: await bearer(ADMIN),
      env: makeEnv({ ADMIN_USER_IDS: ADMIN }),
      body: {},
    });
    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: "Not found" });
  });

  it("アプリ証明の IP 枠を使わない", async () => {
    await callJson("POST", "/app/integrity", { body: {} });
    expect(await rows("SELECT * FROM rate_limits WHERE action = 'app_attest'")).toEqual([]);
  });
});
