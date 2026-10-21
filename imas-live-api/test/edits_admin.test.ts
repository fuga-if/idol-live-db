// POST /edits の管理者の経路 (マスタの update / delete / セトリ) と、GET /master/:type/:name/history。
// CloudKit は test/support/cloudkit.ts のメモリ上の模造で受ける。
//
// update のマージ (mergeUpdateFields) は、送っていないフィールドが edit_history.after・results・
// CloudKit から消えたバグ (batch 16/55/56) の再発防止である。ここを最初に固定する。

import { env } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { bearer, callJson, makeEnv } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";
import { FakeCloudKit, testCloudKitKey } from "./support/cloudkit";

const ADMIN = "001094.admin";
const ck = new FakeCloudKit();
let ckEnv: ReturnType<typeof makeEnv>;

beforeAll(async () => {
  ckEnv = makeEnv({ CLOUDKIT_KEY_ID: "test-key", CLOUDKIT_PRIVATE_KEY: await testCloudKitKey() });
  ck.install();
});

beforeEach(async () => {
  ck.reset();
  await insertUser(ADMIN, { isAdmin: true, displayName: "管理者" });
});

afterEach(() => vi.restoreAllMocks());

async function postEdits(ops: unknown[], extra: Record<string, unknown> = {}) {
  return callJson("POST", "/edits", { headers: await bearer(ADMIN), env: ckEnv, body: { ops, ...extra } });
}

async function history(batchId: number) {
  const list = await rows<{ record_type: string; record_name: string; op: string; before_json: string | null; after_json: string | null }>(
    "SELECT record_type, record_name, op, before_json, after_json FROM edit_history WHERE batch_id = ? ORDER BY id",
    batchId
  );
  return list.map((r) => ({
    recordType: r.record_type,
    recordName: r.record_name,
    op: r.op,
    before: r.before_json === null ? null : JSON.parse(r.before_json),
    after: r.after_json === null ? null : JSON.parse(r.after_json),
  }));
}

describe("POST /edits — update のマージ", () => {
  it("送ったフィールドだけを上書きし、送っていないフィールドは残す。null は明示クリア", async () => {
    ck.put("Song", "s1", { title: "旧題", lyricist: "作詞者", composer: "作曲者", releaseDate: "2020-01-01", modifiedAt: 1 });

    const res = await postEdits([{ op: "update", recordType: "Song", recordName: "s1", fields: { title: "新題", composer: null } }]);
    expect(res.status).toBe(200);

    // CloudKit へは before に重ねた全フィールドを送る (modifiedAt は新しい値)
    const [sent] = ck.modifiedOps();
    expect(sent.operationType).toBe("forceUpdate");
    expect(Object.keys(sent.record.fields).sort()).toEqual(["composer", "lyricist", "modifiedAt", "releaseDate", "title"]);
    expect(sent.record.fields.title.value).toBe("新題");
    expect(sent.record.fields.lyricist.value).toBe("作詞者");
    expect(sent.record.fields.composer.value).toBeNull();
    expect(sent.record.fields.modifiedAt.value).not.toBe(1);

    // results[].fields も同じマージ後の値 (iOS はこれで楽観更新する)
    const [result] = res.body.results;
    expect(result).toMatchObject({ recordType: "Song", recordName: "s1", op: "update", ok: true });
    expect(result.fields).toMatchObject({ title: "新題", lyricist: "作詞者", composer: null, releaseDate: "2020-01-01" });

    // edit_history は before = CloudKit の現状、after = マージ後の全フィールド
    expect(await history(res.body.batchId)).toEqual([
      {
        recordType: "Song",
        recordName: "s1",
        op: "update",
        before: { title: "旧題", lyricist: "作詞者", composer: "作曲者", releaseDate: "2020-01-01", modifiedAt: 1 },
        after: { title: "新題", lyricist: "作詞者", composer: null, releaseDate: "2020-01-01" },
      },
    ]);
    expect(ck.get("s1")).toMatchObject({ title: "新題", lyricist: "作詞者", releaseDate: "2020-01-01" });
    expect(ck.get("s1")).not.toHaveProperty("composer");
  });

  it("CloudKit に無いレコードの update は before=null で、送った値だけを書く", async () => {
    const res = await postEdits([{ op: "update", recordType: "Song", recordName: "s404", fields: { title: "新規" } }]);
    expect(res.status).toBe(200);
    expect(await history(res.body.batchId)).toEqual([
      { recordType: "Song", recordName: "s404", op: "update", before: null, after: { title: "新規" } },
    ]);
  });

  it("before の取得に失敗したら 502 で、edit_batch も CloudKit への書き込みも作らない", async () => {
    ck.failNext("lookup");
    const res = await postEdits([{ op: "update", recordType: "Song", recordName: "s1", fields: { title: "x" } }]);
    expect(res.status).toBe(502);
    expect(res.body.error).toMatch(/^cloudkit_lookup_error: CloudKit HTTP 503/);
    expect(await rows("SELECT id FROM edit_batch")).toEqual([]);
    expect(ck.count("modify")).toBe(0);
  });
});

describe("POST /edits — delete と batch の op", () => {
  it("delete はソフト削除。履歴は before = 現状、after = null。results の fields は null", async () => {
    ck.put("Song", "s1", { title: "消す曲" });
    const res = await postEdits([{ op: "delete", recordType: "Song", recordName: "s1" }]);
    expect(res.status).toBe(200);
    expect(res.body.results).toEqual([{ recordType: "Song", recordName: "s1", op: "delete", ok: true, fields: null }]);
    expect(await history(res.body.batchId)).toEqual([
      { recordType: "Song", recordName: "s1", op: "delete", before: { title: "消す曲" }, after: null },
    ]);
    expect(ck.get("s1")).toMatchObject({ title: "消す曲", deletedAt: expect.any(Number) });
    expect(await row("SELECT op FROM edit_batch WHERE id = ?", res.body.batchId)).toEqual({ op: "delete" });
  });

  it("種類の混ざった batch は replace、同じ種類が複数なら その種類。summary はサーバが作る", async () => {
    ck.put("Song", "s1", { title: "a" });
    ck.put("Song", "s2", { title: "b" });
    const mixed = await postEdits(
      [
        { op: "update", recordType: "Song", recordName: "s1", fields: { title: "a2" } },
        { op: "delete", recordType: "Song", recordName: "s2" },
      ],
      { summary: "まとめて直した" }
    );
    expect(await row("SELECT op, summary FROM edit_batch WHERE id = ?", mixed.body.batchId)).toEqual({
      op: "replace",
      summary: "Song.update x1, Song.delete x1 — まとめて直した",
    });

    const updates = await postEdits([
      { op: "update", recordType: "Song", recordName: "s1", fields: { title: "a3" } },
      { op: "update", recordType: "Song", recordName: "s2", fields: { title: "b3" } },
    ]);
    expect(await row("SELECT op, summary FROM edit_batch WHERE id = ?", updates.body.batchId)).toEqual({
      op: "update",
      summary: "Song.update x2",
    });
  });

  it("履歴の確定に失敗しても CloudKit には反映済みなので 200 と warning を返す", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    const failingBatch = {
      prepare: env.DB.prepare.bind(env.DB),
      batch: () => Promise.reject(new Error("D1 down")),
    } as unknown as D1Database;
    const res = await callJson("POST", "/edits", {
      headers: await bearer(ADMIN),
      env: { ...ckEnv, DB: failingBatch },
      body: { ops: [{ op: "update", recordType: "Song", recordName: "s1", fields: { title: "x" } }] },
    });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ ok: true, warning: "history_not_recorded" });
    expect(ck.count("modify")).toBe(1);
    expect(await row("SELECT cloudkit_ok FROM edit_batch WHERE id = ?", res.body.batchId)).toEqual({ cloudkit_ok: 0 });
  });
});

describe("POST /edits — イベントの同名確認", () => {
  it("空白を畳んだ名前が一致するイベントがあれば 409 で、書き込まない", async () => {
    ck.put("Event", "ev_slug", { name: "SideM 11th STAGE" });
    const res = await postEdits([{ op: "create", recordType: "Event", fields: { name: "  SideM   11th STAGE " } }]);
    expect(res.status).toBe(409);
    expect(res.body.error).toContain("ev_slug");
    const [query] = ck.requests.filter((r) => r.endpoint === "query");
    expect(query.body.query.filterBy[0].fieldValue.value).toBe("SideM 11th STAGE");
    expect(ck.count("modify")).toBe(0);
  });

  it("同名が無ければ ev_<uuid> で作る。照会に失敗したときも通す", async () => {
    const created = await postEdits([{ op: "create", recordType: "Event", fields: { name: "新しいライブ" } }]);
    expect(created.status).toBe(200);
    expect(created.body.results[0].recordName).toMatch(/^ev_[0-9a-f-]{36}$/);

    ck.failNext("query");
    const passed = await postEdits([{ op: "create", recordType: "Event", fields: { name: "照会に失敗したライブ" } }]);
    expect(passed.status).toBe(200);
  });
});

describe("POST /edits — セトリ", () => {
  beforeEach(() => {
    ck.put("Show", "sh1", { eventId: "ev1" });
    ck.put("SetlistItem", "sli_a", { showId: "sh1", songId: "s1", position: 1 });
    ck.put("SetlistPerformer", "slp_a", { setlistItemId: "sli_a", idolId: "idol_a" });
    ck.put("Idol", "idol_a", { name: "A" });
    ck.put("Idol", "idol_b", { name: "B" });
  });

  it("セトリの編集は show 単位のスナップショット (ShowSetlist) を before / after つきで残す", async () => {
    const res = await postEdits([
      { op: "create", recordType: "SetlistItem", fields: { showId: "sh1", songId: "s2", position: 2 } },
      // batch に無い既存の曲 (sli_a) への出演者追加。showId は sli_a を引いて解決する
      { op: "create", recordType: "SetlistPerformer", fields: { setlistItemId: "sli_a", idolId: "idol_b" } },
    ]);
    expect(res.status).toBe(200);
    const [item, performer] = res.body.results;
    expect(item.recordName).toMatch(/^sli_/);
    expect(performer.recordName).toMatch(/^slp_/);

    const hist = await history(res.body.batchId);
    expect(hist.map((h) => [h.recordType, h.op])).toEqual([
      ["SetlistItem", "create"],
      ["SetlistPerformer", "create"],
      ["ShowSetlist", "snapshot"],
    ]);
    const snap = hist[2];
    expect(snap.recordName).toBe("sh1");
    expect(snap.before).toEqual({
      items: [{ recordName: "sli_a", fields: { showId: "sh1", songId: "s1", position: 1 } }],
      performers: [{ recordName: "slp_a", fields: { setlistItemId: "sli_a", idolId: "idol_a" } }],
    });
    expect(snap.after.items.map((i: { recordName: string }) => i.recordName).sort()).toEqual(["sli_a", item.recordName].sort());
    expect(snap.after.performers.map((p: { recordName: string }) => p.recordName).sort()).toEqual(["slp_a", performer.recordName].sort());
  });

  it("存在しない idolId を指す出演者は 400 で、CloudKit に書かない", async () => {
    const res = await postEdits([
      { op: "create", recordType: "SetlistPerformer", fields: { setlistItemId: "sli_a", idolId: "idol_404" } },
    ]);
    expect(res.status).toBe(400);
    expect(res.body.error).toBe("SetlistPerformer references unknown idolId: idol_404");
    expect(ck.count("modify")).toBe(0);
  });

  it("show を辿れないセトリの op は 400 (スナップショットの無いセトリ編集を作らない)", async () => {
    const res = await postEdits([{ op: "delete", recordType: "SetlistPerformer", recordName: "slp_orphan" }]);
    expect(res.status).toBe(400);
    expect(res.body.error).toMatch(/^cannot resolve showId for SetlistPerformer\/slp_orphan/);
    expect(await rows("SELECT id FROM edit_batch")).toEqual([]);
  });

  it("before のスナップショットを取れなければ 502", async () => {
    ck.failNext("query");
    const res = await postEdits([{ op: "update", recordType: "SetlistItem", recordName: "sli_a", fields: { position: 3 } }]);
    expect(res.status).toBe(502);
    expect(res.body.error).toMatch(/^setlist_snapshot_error: setlist items query/);
    expect(ck.count("modify")).toBe(0);
  });
});

describe("GET /master/:recordType/:recordName/history", () => {
  it("新しい順に、変更したフィールド名と前後の値を返す。編集者の表示名はメールを伏せる", async () => {
    await exec("UPDATE users SET display_name = ? WHERE id = ?", "admin@example.com", ADMIN);
    ck.put("Song", "s1", { title: "旧題", lyricist: "作詞者" });
    const first = await postEdits([{ op: "update", recordType: "Song", recordName: "s1", fields: { title: "新題" } }]);
    // 作成時刻で並べるので、2 件目を確実に後にする
    await exec("UPDATE edit_history SET created_at = created_at - 1000 WHERE batch_id = ?", first.body.batchId);
    const second = await postEdits([{ op: "delete", recordType: "Song", recordName: "s1" }]);

    const res = await callJson("GET", "/master/Song/s1/history?v=1", { env: ckEnv });
    expect(res.status).toBe(200);
    expect(res.body.history).toHaveLength(2);
    const [del, upd] = res.body.history;
    expect(del).toMatchObject({ batchId: second.body.batchId, op: "delete", after: null, editorName: "a***", source: "app", reverted: false });
    // delete は before のフィールド全部が「変わった」扱い
    expect(del.changedFields.sort()).toEqual(["lyricist", "modifiedAt", "title"]);
    expect(upd).toMatchObject({
      batchId: first.body.batchId,
      op: "update",
      changedFields: ["title"],
      before: { title: "旧題", lyricist: "作詞者" },
      after: { title: "新題", lyricist: "作詞者" },
    });
  });

  it("limit で件数を絞る。不正な limit は既定 (30) に戻す。CloudKit 未反映の batch は出さない", async () => {
    for (const title of ["a", "b", "c"]) {
      await postEdits([{ op: "update", recordType: "Song", recordName: "s9", fields: { title } }]);
    }
    await exec("UPDATE edit_batch SET cloudkit_ok = 0 WHERE id = (SELECT MIN(id) FROM edit_batch)");

    expect((await callJson("GET", "/master/Song/s9/history?limit=1", { env: ckEnv })).body.history).toHaveLength(1);
    expect((await callJson("GET", "/master/Song/s9/history?limit=abc", { env: ckEnv })).body.history).toHaveLength(2);
    expect((await callJson("GET", "/master/Song/s9/history?limit=-5", { env: ckEnv })).body.history).toHaveLength(2);
  });

  it("create の履歴は after のキーを変更フィールドにする。壊れた JSON は null で返す", async () => {
    const created = await postEdits([{ op: "create", recordType: "Song", fields: { title: "新曲" } }]);
    const name = created.body.results[0].recordName;
    await exec("UPDATE edit_history SET before_json = '{broken' WHERE batch_id = ?", created.body.batchId);

    const res = await callJson("GET", `/master/Song/${name}/history`, { env: ckEnv });
    const [entry] = res.body.history;
    expect(entry.before).toBeNull();
    expect(entry.changedFields).toEqual(["title"]);
  });
});
