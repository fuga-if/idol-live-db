// 貢献バッジ (badges.ts)。
// GET /users/:user_id/badges — tier は編集件数 (cloudkit_ok=1 かつ source='app' の batch 数) だけで決まる。境界は 10 / 50 / 200 / 500。
// GET /users/me/badges — マイ投稿の件数と内訳の出どころ。

import { describe, expect, it } from "vitest";
import { bearer, callJson } from "./support/worker";
import { exec, insertUser, row } from "./support/d1";

const UID = "001094.badge";
const FAN = "001094.fan";

/** editor の app 編集 batch を n 件入れる (1 batch に Song の履歴を 1 行)。 */
async function seedEdits(editor: string, n: number, opts: { source?: string; cloudkitOk?: number; recordType?: string } = {}) {
  if (n === 0) return;
  await exec(
    `WITH RECURSIVE seq(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM seq WHERE i < ?)
     INSERT INTO edit_batch (editor_id, source, op, cloudkit_ok, created_at)
     SELECT ?, ?, 'update', ?, i FROM seq`,
    n, editor, opts.source ?? "app", opts.cloudkitOk ?? 1
  );
  await exec(
    `INSERT INTO edit_history (batch_id, record_type, record_name, op, modified_at, created_at)
     SELECT id, ?, 'r' || id, 'update', 0, 0 FROM edit_batch
      WHERE editor_id = ? AND id NOT IN (SELECT batch_id FROM edit_history)`,
    opts.recordType ?? "Song", editor
  );
}

async function badges(uid: string) {
  // 公開キャッシュに載るので、毎回 URL を変える
  return callJson("GET", `/users/${encodeURIComponent(uid)}/badges?t=${crypto.randomUUID()}`);
}

describe("GET /users/:user_id/badges", () => {
  it.each([
    [0, "none"],
    [9, "none"],
    [10, "bronze"],
    [49, "bronze"],
    [50, "silver"],
    [199, "silver"],
    [200, "gold"],
    [499, "gold"],
    [500, "platinum"],
  ])("編集 %i 件は %s", async (n, tier) => {
    await insertUser(UID);
    await seedEdits(UID, n);
    const res = await badges(UID);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ tier, editCount: n });
  });

  it("CloudKit 未反映・revert・seed の batch は数えない。内訳は履歴の record_type ごと、Good は app 編集に付いた分", async () => {
    await insertUser(UID);
    await insertUser(FAN);
    await seedEdits(UID, 3);
    await seedEdits(UID, 2, { recordType: "SetlistItem" });
    await seedEdits(UID, 4, { cloudkitOk: 0 });
    await seedEdits(UID, 5, { source: "revert" });
    await seedEdits(UID, 6, { source: "seed" });
    await exec(
      `INSERT INTO edit_good (batch_id, user_id, created_at)
       SELECT id, ?, 0 FROM edit_batch WHERE editor_id = ? AND source = 'app' ORDER BY id LIMIT 2`,
      FAN, UID
    );
    await exec(
      `INSERT INTO edit_good (batch_id, user_id, created_at)
       SELECT id, ?, 0 FROM edit_batch WHERE editor_id = ? AND source = 'revert' LIMIT 1`,
      FAN, UID
    );

    expect((await badges(UID)).body).toEqual({
      tier: "none",
      editCount: 5,
      goodsReceived: 2,
      categories: { Song: 3, ShowSetlist: 2 },
    });
  });

  it("知らないユーザーは 0 件で返す", async () => {
    expect((await badges("nobody")).body).toEqual({ tier: "none", editCount: 0, goodsReceived: 0, categories: {} });
  });
});

const NOW = Date.now();

/** app の編集 batch を 1 つ入れ、edit_history の行 (record_type) を付ける。 */
async function insertBatch(
  editor: string,
  types: string[],
  opts: { source?: string; cloudkitOk?: number } = {}
): Promise<void> {
  await exec(
    `INSERT INTO edit_batch (editor_id, source, op, summary, cloudkit_ok, created_at)
     VALUES (?, ?, 'replace', '編集', ?, ?)`,
    editor, opts.source ?? "app", opts.cloudkitOk ?? 1, NOW
  );
  const id = (await row<{ id: number }>("SELECT MAX(id) AS id FROM edit_batch"))!.id;
  for (const [i, rt] of types.entries()) {
    await exec(
      `INSERT INTO edit_history (batch_id, record_type, record_name, op, modified_at, created_at)
       VALUES (?, ?, ?, 'update', ?, ?)`,
      id, rt, `${rt}_${id}_${i}`, NOW, NOW
    );
  }
}

describe("GET /users/me/badges", () => {
  it("未ログインは 401", async () => {
    expect((await callJson("GET", "/users/me/badges")).status).toBe(401);
  });

  it("内訳は op 行ではなく編集 batch を数え、セトリの行は ShowSetlist にまとめる", async () => {
    await insertUser("bd.me");
    await insertBatch("bd.me", ["ShowSetlist", "SetlistItem", "SetlistItem", "SetlistItem", "SetlistPerformer"]);
    await insertBatch("bd.me", ["ShowSetlist", "SetlistItem"]);
    await insertBatch("bd.me", ["Song", "SongArtist"]);
    await insertBatch("bd.me", ["Song"], { source: "seed" });
    await insertBatch("bd.me", ["Song"], { cloudkitOk: 0 });

    const res = await callJson("GET", "/users/me/badges", { headers: await bearer("bd.me") });
    expect(res.status).toBe(200);
    expect(res.body.editCount).toBe(3);
    expect(res.body.categories).toEqual({ ShowSetlist: 2, Song: 1, SongArtist: 1 });
  });
});
