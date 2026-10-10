// 手応え (GET /me/feedback・POST /shows/views) と公演の奥付 (GET /shows/:id/credits・POST /users/me/credit)。

import { describe, expect, it } from "vitest";
import { jstWeekStart } from "../src/contribution_feedback";
import { bearer, callJson, device } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";

const NOW = Date.now();

/** 適用済みの app の編集 batch を 1 つ入れ、edit_history の行 (record_type, record_name) を付ける。 */
async function insertBatch(
  editor: string,
  rowsOf: Array<[string, string]>,
  opts: { source?: string; reverted?: boolean; createdAt?: number } = {}
): Promise<number> {
  await exec(
    `INSERT INTO edit_batch (editor_id, source, op, summary, cloudkit_ok, created_at, reverted_at)
     VALUES (?, ?, 'replace', 'セトリを編集', 1, ?, ?)`,
    editor, opts.source ?? "app", opts.createdAt ?? NOW, opts.reverted ? NOW : null
  );
  const id = (await row<{ id: number }>("SELECT MAX(id) AS id FROM edit_batch"))!.id;
  for (const [rt, rn] of rowsOf) {
    await exec(
      `INSERT INTO edit_history (batch_id, record_type, record_name, op, modified_at, created_at)
       VALUES (?, ?, ?, 'update', ?, ?)`,
      id, rt, rn, NOW, NOW
    );
  }
  return id;
}

async function good(batchId: number, uid: string, at: number) {
  await exec("INSERT INTO edit_good (batch_id, user_id, created_at) VALUES (?, ?, ?)", batchId, uid, at);
}

describe("jstWeekStart", () => {
  it("JST の月曜始まり", () => {
    // 2026-10-04 (日) 23:59 JST → その週の月曜は 09-28
    expect(jstWeekStart(Date.parse("2026-10-04T14:59:00Z"))).toBe("2026-09-28");
    // 2026-10-05 (月) 00:00 JST → 10-05
    expect(jstWeekStart(Date.parse("2026-10-04T15:00:00Z"))).toBe("2026-10-05");
  });
});

describe("GET /me/feedback", () => {
  it("未ログインは 401", async () => {
    expect((await callJson("GET", "/me/feedback")).status).toBe(401);
  });

  it("自分の app の編集に付いた Good を、since より後を新着として返す", async () => {
    await insertUser("fb.me");
    await insertUser("fb.a");
    await insertUser("fb.b");
    const mine = await insertBatch("fb.me", [["SetlistItem", "si_1"], ["ShowSetlist", "sh_fb1"]]);
    const seed = await insertBatch("fb.me", [["Song", "s1"]], { source: "seed" });
    const other = await insertBatch("fb.a", [["Song", "s2"]]);
    await good(mine, "fb.a", 1000);
    await good(mine, "fb.b", 3000);
    await good(seed, "fb.a", 3000);
    await good(other, "fb.b", 3000);

    const { status, body } = await callJson("GET", "/me/feedback?since=2000", { headers: await bearer("fb.me") });
    expect(status).toBe(200);
    expect(body.goods).toEqual([
      {
        batchId: mine,
        summary: "セトリを編集",
        recordType: "SetlistItem",
        recordName: "si_1",
        goodCount: 2,
        newGoodCount: 1,
        latestGoodAt: 3000,
      },
    ]);
    expect(body.newGoodTotal).toBe(1);
  });

  it("自分が入れたセトリの公演の、先週の閲覧数を合計する (取り消した編集は除く)", async () => {
    await insertUser("fb.reach");
    await insertBatch("fb.reach", [["ShowSetlist", "sh_r1"]]);
    await insertBatch("fb.reach", [["ShowSetlist", "sh_r2"]]);
    await insertBatch("fb.reach", [["ShowSetlist", "sh_r3"]], { reverted: true });
    const lastWeek = jstWeekStart(Date.now() - 7 * 86_400_000);
    const thisWeek = jstWeekStart(Date.now());
    await exec("INSERT INTO show_views_weekly VALUES (?, 'sh_r1', 5)", lastWeek);
    await exec("INSERT INTO show_views_weekly VALUES (?, 'sh_r2', 2)", lastWeek);
    await exec("INSERT INTO show_views_weekly VALUES (?, 'sh_r3', 100)", lastWeek);
    await exec("INSERT INTO show_views_weekly VALUES (?, 'sh_r1', 9)", thisWeek);

    const { body } = await callJson("GET", "/me/feedback", { headers: await bearer("fb.reach") });
    expect(body.setlistReach).toEqual({ week: lastWeek, viewers: 7, shows: 2 });
  });
});

describe("D1 の読み方", () => {
  it("先週の閲覧数は自分の編集 (editor 索引) から引く。全員の ShowSetlist 行を読まない", async () => {
    const plan = await rows<{ detail: string }>(
      `EXPLAIN QUERY PLAN
       SELECT h.record_name FROM edit_batch eb CROSS JOIN edit_history h ON h.batch_id = eb.id
        WHERE eb.editor_id = 'x' AND eb.source = 'app' AND eb.cloudkit_ok = 1
          AND eb.reverted_at IS NULL AND h.record_type = 'ShowSetlist'`
    );
    const details = plan.map((p) => p.detail).join(" | ");
    expect(details).toContain("idx_edit_batch_editor");
    expect(details).toContain("idx_edit_history_batch_type");
    expect(details).not.toContain("idx_edit_history_record");
  });
});

describe("POST /shows/views", () => {
  it("端末 ID が要る。今週の公演ごとの人数を 1 ずつ足す", async () => {
    expect((await callJson("POST", "/shows/views", { body: { show_ids: ["sh_v1"] } })).status).toBe(400);
    const week = jstWeekStart(Date.now());
    for (const d of ["dev-1", "dev-2"]) {
      const res = await callJson("POST", "/shows/views", {
        headers: device(d),
        body: { show_ids: ["sh_v1", "sh_v1", "sh_v2"] },
      });
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ ok: true, week, counted: 2 });
    }
    expect(await row("SELECT viewers FROM show_views_weekly WHERE show_id = 'sh_v1' AND week = ?", week))
      .toEqual({ viewers: 2 });
  });

  it("公演 ID の形と数を確かめる", async () => {
    const h = device("dev-3");
    expect((await callJson("POST", "/shows/views", { headers: h, body: { show_ids: ["ev_1"] } })).status).toBe(400);
    expect((await callJson("POST", "/shows/views", { headers: h, body: { show_ids: [] } })).status).toBe(400);
    const many = Array.from({ length: 4 }, (_, i) => `sh_${i}`);
    expect((await callJson("POST", "/shows/views", { headers: h, body: { show_ids: many } })).status).toBe(400);
  });
});

describe("GET /shows/:id/credits と POST /users/me/credit", () => {
  it("名前を載せると選んだ人だけを、最初に入れた順に役割別で返す", async () => {
    await insertUser("cr.a", { displayName: "Aさん" });
    await insertUser("cr.b", { displayName: "Bさん" });
    await insertUser("cr.c", { displayName: "Cさん" });
    await insertUser("cr.banned", { displayName: "荒らし", isBanned: true });
    await insertUser("cr.mail", { displayName: "mail@example.com" });
    await insertBatch("cr.b", [["SetlistItem", "x"], ["ShowSetlist", "sh_c1"]], { createdAt: 2 });
    await insertBatch("cr.a", [["SetlistItem", "x"], ["SetlistPerformer", "y"], ["ShowSetlist", "sh_c1"]], { createdAt: 1 });
    await insertBatch("cr.c", [["SetlistPerformer", "y"], ["ShowSetlist", "sh_c1"]], { createdAt: 3 });
    await insertBatch("cr.banned", [["SetlistItem", "x"], ["ShowSetlist", "sh_c1"]], { createdAt: 4 });
    await insertBatch("cr.mail", [["SetlistItem", "x"], ["ShowSetlist", "sh_c1"]], { createdAt: 5 });
    // 取り消した編集・別の公演はクレジットに入らない。
    await insertBatch("cr.c", [["SetlistItem", "x"], ["ShowSetlist", "sh_c1"]], { reverted: true });
    await insertBatch("cr.c", [["SetlistItem", "x"], ["ShowSetlist", "sh_c2"]]);

    // 既定は載せない。
    const before = await callJson("GET", "/shows/sh_c1/credits?v=0");
    expect(before.body.setlist).toEqual({ names: [], total: 3 });
    expect(before.res.headers.get("Cache-Control")).toBe("public, max-age=600");

    for (const uid of ["cr.a", "cr.b", "cr.c", "cr.banned", "cr.mail"]) {
      const res = await callJson("POST", "/users/me/credit", { headers: await bearer(uid), body: { credit_opt_in: true } });
      expect(uid === "cr.banned" ? res.status : res.body).toEqual(uid === "cr.banned" ? 403 : { creditOptIn: true });
    }
    await exec("UPDATE users SET credit_opt_in = 1 WHERE id = 'cr.banned'");

    const { body } = await callJson("GET", "/shows/sh_c1/credits?v=1");
    expect(body).toEqual({
      showId: "sh_c1",
      setlist: { names: ["Aさん", "Bさん", "m***"], total: 3 },
      performers: { names: ["Aさん", "Cさん"], total: 2 },
    });

    const me = await callJson("GET", "/auth/me", { headers: await bearer("cr.a") });
    expect(me.body.creditOptIn).toBe(true);
  });

  it("切り替えは真偽値だけ。未ログインは 401", async () => {
    expect((await callJson("POST", "/users/me/credit", { body: { credit_opt_in: true } })).status).toBe(401);
    await insertUser("cr.x");
    const res = await callJson("POST", "/users/me/credit", { headers: await bearer("cr.x"), body: { credit_opt_in: "yes" } });
    expect(res.status).toBe(400);
    expect((await callJson("GET", "/shows/ev_1/credits")).status).toBe(400);
  });
});
