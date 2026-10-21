// 編集の巻き戻し (revert.ts)。
//   POST /edits/:batchId/revert   本人 (自分の batch) か admin が 1 batch を戻す
//   POST /admin/revert-user       admin が 1 ユーザーの編集をまとめて戻す (dryRun / alsoBan)
//   GET  /admin/users/:id/edits   admin が対象ユーザーの編集一覧を見る
//
// revertBatch の結果は reverted / already_reverted / skipped_conflict / not_found / not_applied / failed の 6 通り。
// CloudKit を呼ばずに決まる前の 3 つは D1 の行だけで確かめ、残りは test/support/cloudkit.ts の模造で確かめる。

import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";
import { FakeCloudKit, testCloudKitKey } from "./support/cloudkit";

const ADMIN = "001094.admin";
const EDITOR = "001094.editor";
const OTHER = "001094.other";
const ck = new FakeCloudKit();
let ckEnv: ReturnType<typeof makeEnv>;

beforeAll(async () => {
  ckEnv = makeEnv({ CLOUDKIT_KEY_ID: "test-key", CLOUDKIT_PRIVATE_KEY: await testCloudKitKey() });
  ck.install();
});

beforeEach(async () => {
  ck.reset();
  await insertUser(ADMIN, { isAdmin: true });
  await insertUser(EDITOR, { displayName: "編集者" });
  await insertUser(OTHER);
});

afterEach(() => vi.restoreAllMocks());

interface Entry {
  type: string;
  name: string;
  op: string;
  before?: unknown;
  after?: unknown;
}

/** edit_batch と edit_history を直接入れる。返り値は batchId。 */
async function seedBatch(
  editor: string,
  entries: Entry[],
  opts: { cloudkitOk?: boolean; revertedAt?: number | null; source?: string; createdAt?: number } = {}
): Promise<number> {
  const created = opts.createdAt ?? Date.now();
  const batch = await row<{ id: number }>(
    `INSERT INTO edit_batch (editor_id, source, op, summary, cloudkit_ok, created_at, reverted_at)
     VALUES (?, ?, 'update', 'seed', ?, ?, ?) RETURNING id`,
    editor,
    opts.source ?? "app",
    opts.cloudkitOk === false ? 0 : 1,
    created,
    opts.revertedAt ?? null
  );
  for (const e of entries) {
    await exec(
      `INSERT INTO edit_history (batch_id, record_type, record_name, op, before_json, after_json, modified_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
      batch!.id,
      e.type,
      e.name,
      e.op,
      e.before === undefined || e.before === null ? null : JSON.stringify(e.before),
      e.after === undefined || e.after === null ? null : JSON.stringify(e.after),
      created,
      created
    );
  }
  return batch!.id;
}

async function revert(batchId: number, as = EDITOR, body?: unknown) {
  return callJson("POST", `/edits/${batchId}/revert`, { headers: await bearer(as), env: ckEnv, body });
}

const SONG_UPDATE: Entry = {
  type: "Song",
  name: "s1",
  op: "update",
  before: { title: "旧題", lyricist: "作詞者", modifiedAt: 1 },
  after: { title: "新題", lyricist: "作詞者", note: "編集で足した補足" },
};

describe("POST /edits/:batchId/revert — CloudKit を呼ばずに決まる結果", () => {
  it("無い batch は 404 (所有者の確認で止まる)", async () => {
    const res = await revert(999_999);
    expect(res.status).toBe(404);
    expect(ck.requests).toEqual([]);
  });

  it("CloudKit に反映されなかった batch は not_applied (409)", async () => {
    const id = await seedBatch(EDITOR, [SONG_UPDATE], { cloudkitOk: false });
    const res = await revert(id);
    expect(res.status).toBe(409);
    expect(res.body).toMatchObject({ batchId: id, outcome: "not_applied" });
    expect(ck.requests).toEqual([]);
  });

  it("戻し済みの batch は already_reverted (200) で、二重には戻さない", async () => {
    const id = await seedBatch(EDITOR, [SONG_UPDATE], { revertedAt: 123 });
    const res = await revert(id);
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ batchId: id, outcome: "already_reverted" });
    expect(ck.requests).toEqual([]);
  });

  it("他人の batch は 403。admin なら戻せる", async () => {
    const id = await seedBatch(EDITOR, [SONG_UPDATE]);
    expect((await revert(id, OTHER)).status).toBe(403);
    expect((await revert(id, ADMIN)).body.outcome).toBe("reverted");
  });

  it("batchId と本文の検証", async () => {
    expect((await callJson("POST", "/edits/1/revert", { env: ckEnv })).status).toBe(401);
    const id = await seedBatch(EDITOR, [SONG_UPDATE]);
    const bad = await revert(id, EDITOR, "{");
    expect(bad.status).toBe(400);
    expect(bad.body).toEqual({ error: "invalid json body" });
  });

  it("逆適用できない履歴 (before の無い update、廃止した SongCall、履歴なし) は failed (502)", async () => {
    const noBefore = await seedBatch(EDITOR, [{ type: "Song", name: "s1", op: "update", after: { title: "x" } }]);
    expect((await revert(noBefore)).body).toMatchObject({ outcome: "failed", reason: expect.stringContaining("cannot build revert op for Song/s1") });

    const songCall = await seedBatch(EDITOR, [{ type: "SongCall", name: "c1", op: "create", after: { text: "x" } }]);
    expect((await revert(songCall)).status).toBe(502);

    const empty = await seedBatch(EDITOR, []);
    expect((await revert(empty)).body).toMatchObject({ outcome: "failed", reason: "no edit_history rows" });

    expect(ck.count("modify")).toBe(0);
    expect(await rows("SELECT id FROM edit_batch WHERE reverted_at IS NOT NULL")).toEqual([]);
  });
});

describe("POST /edits/:batchId/revert — 逆適用", () => {
  it("update は before の全フィールドへ戻し、編集で足されたフィールドは null でクリアする", async () => {
    const id = await seedBatch(EDITOR, [SONG_UPDATE]);
    const res = await revert(id);
    expect(res.status).toBe(200);
    expect(res.body.outcome).toBe("reverted");

    const [op] = ck.modifiedOps();
    expect(op.record.recordName).toBe("s1");
    expect(op.record.fields.title.value).toBe("旧題");
    expect(op.record.fields.lyricist.value).toBe("作詞者");
    expect(op.record.fields.note.value).toBeNull();
    // modifiedAt は before の値ではなく、いま注入した値
    expect(op.record.fields.modifiedAt.value).not.toBe(1);
    expect(op.record.fields).not.toHaveProperty("deletedAt");

    // D1: 対象 batch に reverted_at、履歴に reverted=1。revert 自体は新しい batch として前後を入れ替えて残す
    expect(await row("SELECT reverted_by, reverted_at IS NOT NULL AS done FROM edit_batch WHERE id = ?", id)).toEqual({ reverted_by: EDITOR, done: 1 });
    expect(await rows("SELECT reverted FROM edit_history WHERE batch_id = ?", id)).toEqual([{ reverted: 1 }]);
    expect(await row("SELECT editor_id, source, op, reverts_batch_id, cloudkit_ok FROM edit_batch WHERE id = ?", res.body.revertBatchId)).toEqual({
      editor_id: EDITOR, source: "revert", op: "revert", reverts_batch_id: id, cloudkit_ok: 1,
    });
    const back = await row<{ op: string; before_json: string; after_json: string }>(
      "SELECT op, before_json, after_json FROM edit_history WHERE batch_id = ?", res.body.revertBatchId
    );
    expect(back!.op).toBe("revert");
    expect(JSON.parse(back!.before_json)).toEqual(SONG_UPDATE.after);
    expect(JSON.parse(back!.after_json)).toEqual(SONG_UPDATE.before);

    // 2 回目は冪等
    expect((await revert(id)).body.outcome).toBe("already_reverted");
  });

  it("create はソフト削除、delete は before に戻して deletedAt をクリアする", async () => {
    const id = await seedBatch(EDITOR, [
      { type: "SongVideo", name: "ytref_1", op: "create", after: { songId: "s1", youtubeUrl: "https://youtu.be/x" } },
      { type: "Song", name: "s2", op: "delete", before: { title: "消された曲", modifiedAt: 5 } },
    ]);
    ck.put("Song", "s2", { title: "消された曲", deletedAt: 100 });
    expect((await revert(id)).body.outcome).toBe("reverted");

    const ops = Object.fromEntries(ck.modifiedOps().map((o) => [o.record.recordName, o.record.fields]));
    expect(Object.keys(ops.ytref_1).sort()).toEqual(["deletedAt", "modifiedAt"]);
    expect(ops.ytref_1.deletedAt.value).toEqual(expect.any(Number));
    expect(ops.s2.title.value).toBe("消された曲");
    expect(ops.s2.deletedAt.value).toBeNull();
    expect(ck.get("s2")).not.toHaveProperty("deletedAt");
  });

  it("後から別の人が同じレコードを編集していたら skipped_conflict。admin の force なら戻す", async () => {
    const id = await seedBatch(EDITOR, [SONG_UPDATE]);
    await seedBatch(OTHER, [{ type: "Song", name: "s1", op: "update", before: SONG_UPDATE.after, after: { title: "別の人の修正" } }]);

    const skipped = await revert(id);
    expect(skipped.status).toBe(200);
    expect(skipped.body).toMatchObject({ outcome: "skipped_conflict", reason: "newer edit by another user on Song/s1" });
    expect(ck.count("modify")).toBe(0);

    // 本人は force できない
    expect((await revert(id, EDITOR, { force: true })).body.outcome).toBe("skipped_conflict");
    expect((await revert(id, ADMIN, { force: true })).body.outcome).toBe("reverted");
  });

  it("同じ人の後続の編集や revert 操作は競合に数えない", async () => {
    const id = await seedBatch(EDITOR, [SONG_UPDATE]);
    await seedBatch(EDITOR, [{ type: "Song", name: "s1", op: "update", before: {}, after: {} }]);
    await seedBatch(OTHER, [{ type: "Song", name: "s1", op: "revert", before: {}, after: {} }], { source: "revert" });
    expect((await revert(id)).body.outcome).toBe("reverted");
  });

  it("CloudKit への書き込みに失敗したら failed (502) で、reverted_at を立てない", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const id = await seedBatch(EDITOR, [SONG_UPDATE]);
    ck.failNext("modify");
    const res = await revert(id);
    expect(res.status).toBe(502);
    expect(res.body.reason).toMatch(/^cloudkit_error: CloudKit HTTP 503/);
    expect(await row("SELECT reverted_at FROM edit_batch WHERE id = ?", id)).toEqual({ reverted_at: null });
    // 再実行すれば戻せる
    expect((await revert(id)).body.outcome).toBe("reverted");
  });
});

describe("POST /edits/:batchId/revert — セトリのスナップショット", () => {
  beforeEach(() => {
    ck.put("SetlistItem", "sli_a", { showId: "sh1", songId: "s1", position: 1 });
    ck.put("SetlistPerformer", "slp_a", { setlistItemId: "sli_a", idolId: "idol_a" });
    ck.put("Idol", "idol_a", {});
  });

  it("show のセトリ全体を before に戻す。いま在って before に無い曲と出演者はソフト削除する", async () => {
    const edit = await callJson("POST", "/edits", {
      headers: await bearer(ADMIN), env: ckEnv,
      body: {
        ops: [
          { op: "update", recordType: "SetlistItem", recordName: "sli_a", fields: { position: 5 } },
          { op: "create", recordType: "SetlistItem", fields: { showId: "sh1", songId: "s2", position: 2 } },
        ],
      },
    });
    expect(edit.status).toBe(200);
    const added = edit.body.results[1].recordName;
    // 編集の後で (同じ人が) 足した曲。保存済みの after には無いが、現状の再取得で拾って消す
    ck.put("SetlistItem", "sli_late", { showId: "sh1", songId: "s3", position: 3 });
    ck.requests.length = 0;

    const res = await revert(edit.body.batchId, ADMIN);
    expect(res.body.outcome).toBe("reverted");

    const ops = ck.modifiedOps().map((o) => ({
      name: o.record.recordName,
      deleted: o.record.fields.deletedAt?.value != null,
    }));
    expect(ops).toEqual(expect.arrayContaining([
      { name: "sli_a", deleted: false },
      { name: "slp_a", deleted: false },
      { name: added, deleted: true },
      { name: "sli_late", deleted: true },
    ]));
    expect(ops).toHaveLength(4);
    expect(ck.get("sli_a")).toMatchObject({ position: 1 });

    // 逆向きの履歴はスナップショット行だけ (個別の SetlistItem 行は二重に戻さない)
    expect(await rows("SELECT record_type, record_name FROM edit_history WHERE batch_id = ?", res.body.revertBatchId))
      .toEqual([{ record_type: "ShowSetlist", record_name: "sh1" }]);
  });

  it("現状のセトリを取り直せなければ failed", async () => {
    const id = await seedBatch(EDITOR, [
      { type: "ShowSetlist", name: "sh1", op: "snapshot", before: { items: [], performers: [] }, after: { items: [], performers: [] } },
    ]);
    ck.failNext("query");
    const res = await revert(id);
    expect(res.status).toBe(502);
    expect(res.body.reason).toBe("cannot re-query current setlist for show sh1");
  });

  it("before の無いスナップショットは failed", async () => {
    const id = await seedBatch(EDITOR, [{ type: "ShowSetlist", name: "sh1", op: "snapshot", after: { items: [] } }]);
    expect((await revert(id)).body).toMatchObject({ outcome: "failed", reason: "snapshot before missing for sh1" });
  });
});

describe("POST /admin/revert-user", () => {
  async function revertUser(body: unknown, as = ADMIN) {
    return callJson("POST", "/admin/revert-user", { headers: await bearer(as), env: ckEnv, body });
  }

  it("admin 以外は 403。userId は必須", async () => {
    expect((await revertUser({ userId: EDITOR }, EDITOR)).status).toBe(403);
    expect((await revertUser({})).body).toEqual({ error: "userId is required" });
    expect((await revertUser("{")).status).toBe(400);
  });

  it("dryRun は CloudKit に書かず、BAN もせず、batch ごとの予測を返す", async () => {
    const ok = await seedBatch(EDITOR, [SONG_UPDATE]);
    const conflict = await seedBatch(EDITOR, [{ type: "Song", name: "s2", op: "update", before: { title: "a" }, after: { title: "b" } }]);
    await seedBatch(OTHER, [{ type: "Song", name: "s2", op: "update", before: { title: "b" }, after: { title: "c" } }]);
    const broken = await seedBatch(EDITOR, [{ type: "Song", name: "s3", op: "update", after: { title: "x" } }]);
    // 対象外: 反映されていない batch / 戻し済み / revert 操作
    await seedBatch(EDITOR, [SONG_UPDATE], { cloudkitOk: false });
    await seedBatch(EDITOR, [SONG_UPDATE], { revertedAt: 1 });
    await seedBatch(EDITOR, [SONG_UPDATE], { source: "revert" });

    const res = await revertUser({ userId: EDITOR, dryRun: true, alsoBan: true });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ userId: EDITOR, banned: false, dryRun: true, reverted: 1, skipped: 1, failed: 1, alreadyReverted: 0 });
    // 新しい順
    expect(res.body.items.map((i: { batchId: number; outcome: string }) => [i.batchId, i.outcome])).toEqual([
      [broken, "failed"],
      [conflict, "skipped_conflict"],
      [ok, "reverted"],
    ]);
    expect(res.body.items[2].revertBatchId).toBeUndefined();
    expect(ck.requests).toEqual([]);
    expect(await row("SELECT is_banned FROM users WHERE id = ?", EDITOR)).toEqual({ is_banned: 0 });
    expect(await rows("SELECT id FROM edit_batch WHERE reverted_at IS NOT NULL AND id IN (?, ?, ?)", ok, conflict, broken)).toEqual([]);
  });

  it("本実行は新しい順に戻す。alsoBan は先に BAN し、その人が付けた Good を消す。force なら競合も戻す", async () => {
    const older = await seedBatch(EDITOR, [SONG_UPDATE], { createdAt: 1_000 });
    const newer = await seedBatch(EDITOR, [{ type: "Song", name: "s2", op: "update", before: { title: "a" }, after: { title: "b" } }], { createdAt: 2_000 });
    await seedBatch(OTHER, [{ type: "Song", name: "s2", op: "update", before: { title: "b" }, after: { title: "c" } }]);
    const othersBatch = await seedBatch(OTHER, []);
    await exec("INSERT INTO edit_good (batch_id, user_id, created_at) VALUES (?, ?, 1)", othersBatch, EDITOR);

    const res = await revertUser({ userId: EDITOR, alsoBan: true, force: true });
    expect(res.body).toMatchObject({ banned: true, dryRun: false, reverted: 2, skipped: 0, failed: 0 });
    expect(res.body.items.map((i: { batchId: number }) => i.batchId)).toEqual([newer, older]);
    expect(ck.modifiedOps().map((o) => o.record.recordName)).toEqual(["s2", "s1"]);
    expect(await row("SELECT is_banned FROM users WHERE id = ?", EDITOR)).toEqual({ is_banned: 1 });
    expect(await rows("SELECT * FROM edit_good WHERE user_id = ?", EDITOR)).toEqual([]);
  });

  it("since より前の編集は残す", async () => {
    const old = await seedBatch(EDITOR, [SONG_UPDATE], { createdAt: 1_000 });
    const recent = await seedBatch(EDITOR, [{ type: "Song", name: "s2", op: "update", before: { title: "a" }, after: { title: "b" } }], { createdAt: 5_000 });
    const res = await revertUser({ userId: EDITOR, since: 2_000 });
    expect(res.body.items.map((i: { batchId: number }) => i.batchId)).toEqual([recent]);
    expect(await row("SELECT reverted_at FROM edit_batch WHERE id = ?", old)).toEqual({ reverted_at: null });
  });
});

describe("GET /admin/users/:id/edits", () => {
  it("app の編集だけを新しい順に、件数と未戻しの数つきで返す", async () => {
    const first = await seedBatch(EDITOR, [SONG_UPDATE, { type: "Song", name: "s2", op: "delete", before: {} }]);
    const second = await seedBatch(EDITOR, [{ type: "SongVideo", name: "ytref_1", op: "create", after: {} }], { revertedAt: 42 });
    await seedBatch(EDITOR, [SONG_UPDATE], { cloudkitOk: false });
    await seedBatch(EDITOR, [SONG_UPDATE], { source: "revert" });

    const res = await callJson("GET", `/admin/users/${EDITOR}/edits`, { headers: await bearer(ADMIN), env: ckEnv });
    expect(res.status).toBe(200);
    expect(res.body.user).toEqual({ uid: EDITOR, displayName: "編集者", isBanned: false });
    expect(res.body).toMatchObject({ total: 2, unreverted: 1 });
    expect(res.body.edits).toEqual([
      expect.objectContaining({ batchId: second, recordType: "SongVideo", recordName: "ytref_1", opCount: 1, reverted: true, revertedAt: 42 }),
      expect.objectContaining({ batchId: first, recordType: "Song", recordName: "s1", opCount: 2, reverted: false, revertedAt: null }),
    ]);

    const unreverted = await callJson("GET", `/admin/users/${EDITOR}/edits?unreverted_only=true&limit=1&offset=0`, {
      headers: await bearer(ADMIN), env: ckEnv,
    });
    expect(unreverted.body.edits.map((e: { batchId: number }) => e.batchId)).toEqual([first]);
  });

  it("admin 以外は 403。知らないユーザーは空で返す", async () => {
    expect((await callJson("GET", `/admin/users/${EDITOR}/edits`, { headers: await bearer(OTHER), env: ckEnv })).status).toBe(403);
    const res = await callJson("GET", "/admin/users/nobody/edits?limit=abc", { headers: await bearer(ADMIN), env: ckEnv });
    expect(res.body).toEqual({ user: { uid: "nobody", displayName: null, isBanned: false }, total: 0, unreverted: 0, edits: [] });
  });
});
