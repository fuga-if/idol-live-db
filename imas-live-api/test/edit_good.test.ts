// POST / DELETE /edits/:batchId/good — 編集への Good (edit_good.ts)。
// Good は edit_good の行だけで閉じる (CloudKit も contribution_count も触らない)。

import { describe, expect, it } from "vitest";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";

const EDITOR = "001094.editor";
const FAN = "001094.fan";
const FAN2 = "001094.fan2";

async function seedBatch(id: number, opts: { cloudkitOk?: number; editor?: string } = {}) {
  await exec(
    "INSERT INTO edit_batch (id, editor_id, source, op, cloudkit_ok, created_at) VALUES (?, ?, 'app', 'update', ?, 1)",
    id, opts.editor ?? EDITOR, opts.cloudkitOk ?? 1
  );
}

async function good(method: "POST" | "DELETE", batch: number | string, uid = FAN) {
  return callJson(method, `/edits/${batch}/good`, { headers: await bearer(uid) });
}

describe("POST /edits/:batchId/good", () => {
  it("付けると goodCount を返す。同じ人が何度押しても 1。編集件数は動かない", async () => {
    await insertUser(EDITOR);
    await insertUser(FAN);
    await insertUser(FAN2);
    await seedBatch(1);

    expect((await good("POST", 1)).body).toEqual({ batchId: 1, goodCount: 1, gooded: true });
    expect((await good("POST", 1)).body).toEqual({ batchId: 1, goodCount: 1, gooded: true });
    expect((await good("POST", 1, FAN2)).body).toEqual({ batchId: 1, goodCount: 2, gooded: true });
    expect(await row("SELECT contribution_count FROM users WHERE id = ?", EDITOR)).toEqual({ contribution_count: 0 });
  });

  it("無い batch は 404、未反映は 409、自分の編集は 400、batchId が 0 は 400", async () => {
    await insertUser(EDITOR);
    await insertUser(FAN);
    await seedBatch(1, { cloudkitOk: 0 });
    await seedBatch(2);
    expect((await good("POST", 99)).status).toBe(404);
    expect((await good("POST", 1)).body).toEqual({ error: "edit not applied yet" });
    expect((await good("POST", 2, EDITOR)).body).toEqual({ error: "cannot good your own edit" });
    expect((await good("POST", 0)).body).toEqual({ error: "invalid batchId" });
    expect(await rows("SELECT * FROM edit_good")).toEqual([]);
  });

  it("未ログインは 401、BAN は 403", async () => {
    await insertUser(EDITOR);
    await insertUser(FAN, { isBanned: true });
    await seedBatch(1);
    expect((await callJson("POST", "/edits/1/good")).status).toBe(401);
    expect((await good("POST", 1)).status).toBe(403);
    expect((await good("DELETE", 1)).status).toBe(403);
  });
});

describe("DELETE /edits/:batchId/good", () => {
  it("外すと goodCount が減る。付けていなくても no-op で 200", async () => {
    await insertUser(EDITOR);
    await insertUser(FAN);
    await insertUser(FAN2);
    await seedBatch(1);
    await good("POST", 1);
    await good("POST", 1, FAN2);

    expect((await good("DELETE", 1)).body).toEqual({ batchId: 1, goodCount: 1, gooded: false });
    expect((await good("DELETE", 1)).body).toEqual({ batchId: 1, goodCount: 1, gooded: false });
    expect(await rows("SELECT user_id FROM edit_good")).toEqual([{ user_id: FAN2 }]);
  });

  it("取り消しはレート制限に数えない (付け外しの往復で枠を使い切らない)", async () => {
    await insertUser(EDITOR);
    await insertUser(FAN);
    await seedBatch(1);
    // 今日の good の枠 (300) を使い切った状態
    await exec(
      "INSERT INTO rate_limits (user_id, action, date, count) VALUES (?, 'good', ?, 300)",
      FAN, new Date().toISOString().slice(0, 10)
    );
    expect((await good("POST", 1)).status).toBe(429);
    expect((await good("DELETE", 1)).status).toBe(200);
  });
});
