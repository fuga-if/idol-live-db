// タグ 3 プール (曲 / アイドル / ユニット) の特性テスト。migrations を当てたローカル D1 で、
// index.ts の入口から本番と同じ経路を通す。応答のキー・ステータス・Cache-Control を固定する。
//
// ⚠️ 集計の増減の「重複や未投票の取り消し」の扱いは P2-16 で直すので、ここでは固定しない
//    (test/device_counters.test.ts が直した後の挙動を固定する)。

import { describe, expect, it } from "vitest";
import { bearer, callJson, device, makeEnv } from "./support/worker";
import { exec, insertUser, row, rows } from "./support/d1";

interface Pool {
  label: string;
  /** タグの語彙 (マスタ) の API。 */
  master: string;
  table: string;
  historyTable: string;
  reportTable: string;
  /** タグを付ける対象の API の接頭辞 (/songs など)。 */
  entity: string;
  entityKey: "song_id" | "idol_id" | "unit_id";
  linkTable: string;
  deviceTable: string;
  /** GET master/:id の応答で、付いている対象を並べるキー。 */
  detailKey: "songs" | "idols" | "units";
}

const POOLS: Pool[] = [
  {
    label: "曲",
    master: "/tags",
    table: "tags",
    historyTable: "tag_description_history",
    reportTable: "tag_reports",
    entity: "/songs",
    entityKey: "song_id",
    linkTable: "song_tags",
    deviceTable: "device_song_tag",
    detailKey: "songs",
  },
  {
    label: "アイドル",
    master: "/idol-tags",
    table: "idol_tag_master",
    historyTable: "idol_tag_description_history",
    reportTable: "idol_tag_reports",
    entity: "/idols",
    entityKey: "idol_id",
    linkTable: "idol_tags",
    deviceTable: "device_idol_tag",
    detailKey: "idols",
  },
  {
    label: "ユニット",
    master: "/unit-tags",
    table: "unit_tag_master",
    historyTable: "unit_tag_description_history",
    reportTable: "unit_tag_reports",
    entity: "/units",
    entityKey: "unit_id",
    linkTable: "unit_tags",
    deviceTable: "device_unit_tag",
    detailKey: "units",
  },
];

// 作成者・編集者 (created_by / updated_by。端末 ID か uid) は応答に載せない (Q-10)。
const TAG_KEYS = [
  "category", "color", "created_at", "description", "id",
  "is_official", "name", "status", "updated_at",
];

const LIST_CACHE = "public, max-age=60, stale-while-revalidate=300";
const DETAIL_CACHE = "public, max-age=300, stale-while-revalidate=1800";
const SIMILAR_CACHE = "public, max-age=600, stale-while-revalidate=3600";

async function createTag(pool: Pool, name: string, deviceId = "dev-a", extra: Record<string, unknown> = {}) {
  return callJson("POST", pool.master, { headers: device(deviceId), body: { name, ...extra } });
}

async function applyTags(pool: Pool, entityId: string, tagIds: string[], deviceId = "dev-a") {
  return callJson("POST", `${pool.entity}/${encodeURIComponent(entityId)}/tags`, {
    headers: device(deviceId),
    body: { tag_ids: tagIds },
  });
}

async function voteCount(pool: Pool, entityId: string, tagId: string): Promise<number | null> {
  const r = await row<{ vote_count: number }>(
    `SELECT vote_count FROM ${pool.linkTable} WHERE ${pool.entityKey} = ? AND tag_id = ?`,
    entityId,
    tagId
  );
  return r?.vote_count ?? null;
}

describe("曲タグ: 語彙の作成 (POST /tags。ハンドラは 3 プール共通なので曲で代表)", () => {
  const pool = POOLS[0];

  it("X-Device-Id が無ければ 400", async () => {
    const res = await callJson("POST", pool.master, { body: { name: "x" } });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "X-Device-Id header is required" });
  });

  it("不正な JSON は 400", async () => {
    const res = await callJson("POST", pool.master, { headers: device("dev-a"), body: "{" });
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "invalid JSON body" });
  });

  it("name と説明・分類・色を検証する", async () => {
    const cases: Array<[Record<string, unknown>, string]> = [
      [{}, "name is required"],
      [{ name: "   " }, "name must be 1-30 characters"],
      [{ name: "あ".repeat(31) }, "name must be 1-30 characters"],
      [{ name: "ok", description: 1 }, "description must be a string"],
      [{ name: "ok", description: "a".repeat(301) }, "description must be 300 characters or less"],
      [{ name: "ok", category: "c".repeat(31) }, "category must be 30 characters or less"],
      [{ name: "ok", color: "red" }, "color must be a #RRGGBB hex code"],
    ];
    for (const [body, message] of cases) {
      const res = await callJson("POST", pool.master, { headers: device("dev-a"), body });
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body).toEqual({ error: message });
    }
  });

  it("201 で作ったタグを返す。id は名前の slug", async () => {
    const res = await createTag(pool, "  Fresh Tag  ", "dev-a", {
      description: "説明", category: "mood", color: "#12abEF",
    });
    expect(res.status).toBe(201);
    expect(res.body.created).toBe(true);
    const tag = res.body.tag;
    expect(Object.keys(tag).sort()).toEqual(TAG_KEYS);
    expect(tag).toMatchObject({
      id: "fresh-tag",
      name: "Fresh Tag",
      description: "説明",
      category: "mood",
      color: "#12abEF",
      is_official: 0,
      status: "active",
    });
    expect(typeof tag.created_at).toBe("number");
    expect(tag.updated_at).toBe(tag.created_at);
    // 作成者の端末 ID は表には残す (応答には出さない)。
    expect(await row(`SELECT created_by, updated_by FROM ${pool.table} WHERE id = 'fresh-tag'`))
      .toEqual({ created_by: "dev-a", updated_by: null });
  });

  it("日本語の名前は tag_ + base64url の先頭 16 文字、衝突したら -2", async () => {
    const first = await createTag(pool, "エモい");
    expect(first.body.tag.id).toBe("tag_" + btoa(unescape(encodeURIComponent("エモい")))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "").slice(0, 16));
    // 同じ slug になる別名 (大文字小文字だけ違う) は -2 を付ける。
    await createTag(pool, "Same");
    const second = await createTag(pool, "SAME");
    expect(second.status).toBe(201);
    expect(second.body.tag.id).toBe("same-2");
  });

  it("同名は 409 で既存のタグを返す", async () => {
    await createTag(pool, "dup", "dev-a");
    const res = await createTag(pool, "dup", "dev-b");
    expect(res.status).toBe(409);
    expect(res.body.created).toBe(false);
    expect(res.body.tag).toMatchObject({ id: "dup", name: "dup" });
    expect(Object.keys(res.body.tag).sort()).toEqual(TAG_KEYS);
  });
});

describe("タグ作成の上限 (1 端末 1 日 10 件、3 プール共有)", () => {
  it("11 件目は 429", async () => {
    for (let i = 0; i < 10; i++) {
      const pool = POOLS[i % POOLS.length];
      const res = await createTag(pool, `quota-${i}`, "dev-quota");
      expect(res.status).toBe(201);
    }
    const res = await createTag(POOLS[1], "quota-10", "dev-quota");
    expect(res.status).toBe(429);
    expect(res.body).toEqual({ error: "Daily tag creation limit reached" });
    // 別の端末は影響を受けない。
    expect((await createTag(POOLS[1], "quota-other", "dev-other")).status).toBe(201);
  });
});

describe("曲タグ: 一覧と詳細 (ハンドラは 3 プール共通なので曲で代表)", () => {
  const pool = POOLS[0];

  it("一覧は削除済みを除き、付与数の多い順。公開キャッシュ", async () => {
    await createTag(pool, "alpha", "dev-a", { description: "d".repeat(50), category: "mood" });
    await createTag(pool, "beta", "dev-a", { category: "scene" });
    await createTag(pool, "gone", "dev-a");
    await exec(`UPDATE ${pool.table} SET status = 'removed' WHERE id = 'gone'`);
    await applyTags(pool, "e1", ["beta"], "dev-1");
    await applyTags(pool, "e2", ["beta"], "dev-2");
    await applyTags(pool, "e1", ["alpha"], "dev-1");

    const res = await callJson("GET", pool.master);
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe(LIST_CACHE);
    expect(res.body.total).toBe(2);
    expect(res.body.tags.map((t: any) => [t.id, t.total_uses])).toEqual([["beta", 2], ["alpha", 1]]);
    expect(Object.keys(res.body.tags[0]).sort()).toEqual(
      ["category", "color", "created_at", "description_preview", "id", "name", "total_uses"]
    );
    expect(res.body.tags[1].description_preview).toBe("d".repeat(40));

    const filtered = await callJson("GET", `${pool.master}?category=scene&sort=name`);
    expect(filtered.body).toMatchObject({ total: 1, tags: [{ id: "beta" }] });
  });

  it("検索語の % と _ は文字として扱う", async () => {
    await createTag(pool, "100%", "dev-a");
    await createTag(pool, "1000", "dev-a");
    const res = await callJson("GET", `${pool.master}?search=${encodeURIComponent("0%")}`);
    expect(res.body.tags.map((t: any) => t.name)).toEqual(["100%"]);
  });

  it("詳細は付いている対象を票数順で返す。公開キャッシュ", async () => {
    await createTag(pool, "detail", "dev-a");
    await applyTags(pool, "e1", ["detail"], "dev-1");
    await applyTags(pool, "e2", ["detail"], "dev-1");
    await applyTags(pool, "e2", ["detail"], "dev-2");

    const res = await callJson("GET", `${pool.master}/detail`);
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe(DETAIL_CACHE);
    expect(Object.keys(res.body).sort()).toEqual([pool.detailKey, "tag"].sort());
    expect(Object.keys(res.body.tag).sort()).toEqual(TAG_KEYS);
    expect(res.body[pool.detailKey]).toEqual([
      { [pool.entityKey]: "e2", vote_count: 2 },
      { [pool.entityKey]: "e1", vote_count: 1 },
    ]);
  });

  it("詳細: 無いタグと削除済みは 404", async () => {
    await createTag(pool, "removed", "dev-a");
    await exec(`UPDATE ${pool.table} SET status = 'removed' WHERE id = 'removed'`);
    for (const id of ["removed", "missing"]) {
      const res = await callJson("GET", `${pool.master}/${id}`);
      expect(res.status).toBe(404);
      expect(res.body).toEqual({ error: "Tag not found" });
    }
  });
});

describe.each(POOLS)("$label タグ: 説明の編集 (PUT $master/:id) と履歴", (pool) => {
  const UID = "001094.edit-user";

  it("未ログインは 401、BAN は 403", async () => {
    await createTag(pool, "tt", "dev-a");
    const anon = await callJson("PUT", `${pool.master}/tt`, { body: { description: "x" } });
    expect(anon.status).toBe(401);
    expect(anon.body).toEqual({ error: "Unauthorized" });

    await insertUser(UID, { isBanned: true });
    const banned = await callJson("PUT", `${pool.master}/tt`, {
      headers: await bearer(UID), body: { description: "x" },
    });
    expect(banned.status).toBe(403);
    expect(banned.body).toEqual({ error: "Banned" });
  });

  it("更新したタグを返し、説明が変わったら前後を履歴に積む。編集者は端末 ID (無ければ uid) で、応答では先頭 8 文字", async () => {
    await insertUser(UID);
    await createTag(pool, "tt", "dev-a", { description: "before" });
    const res = await callJson("PUT", `${pool.master}/tt`, {
      headers: { ...(await bearer(UID)), ...device("dev-edit") },
      body: { description: "after", color: "#000000" },
    });
    expect(res.status).toBe(200);
    expect(Object.keys(res.body)).toEqual(["tag"]);
    expect(res.body.tag).toMatchObject({ id: "tt", description: "after", color: "#000000" });
    expect(Object.keys(res.body.tag).sort()).toEqual(TAG_KEYS);
    expect(await row(`SELECT created_by, updated_by FROM ${pool.table} WHERE id = 'tt'`))
      .toEqual({ created_by: "dev-a", updated_by: "dev-edit" });

    // 色だけの変更は履歴を積まない。端末 ID が無いときは uid が編集者になる。
    await callJson("PUT", `${pool.master}/tt`, { headers: await bearer(UID), body: { color: "#111111" } });
    await callJson("PUT", `${pool.master}/tt`, { headers: await bearer(UID), body: { description: "third" } });

    const history = await callJson("GET", `${pool.master}/tt/history`);
    expect(history.status).toBe(200);
    expect(history.res.headers.get("Cache-Control")).toBeNull();
    expect(history.body).toHaveLength(2);
    expect(Object.keys(history.body[0]).sort()).toEqual(
      ["description_after", "description_before", "edited_at", "edited_by", "id", "tag_id"]
    );
    const byAfter = Object.fromEntries(history.body.map((h: any) => [h.description_after, h]));
    expect(byAfter.after).toMatchObject({ tag_id: "tt", description_before: "before", edited_by: "dev-edit" });
    expect(byAfter.third).toMatchObject({ description_before: "after", edited_by: UID.slice(0, 8) });
    // 表には全体が残る。
    expect(await row(`SELECT edited_by FROM ${pool.historyTable} WHERE description = 'third'`))
      .toEqual({ edited_by: UID });

    // 編集は "edit" の日次枠を使う (マスタ編集と共有)。
    const quota = await row<{ count: number }>(
      "SELECT count FROM rate_limits WHERE user_id = ? AND action = 'edit'", UID
    );
    expect(quota?.count).toBe(3);
  });
});

describe.each(POOLS)("$label タグ: 削除 (DELETE $master/:id、admin のみ)", (pool) => {
  const ADMIN = "001094.admin";
  const USER = "001094.user";

  it("未ログインは 401、一般ユーザーは 403", async () => {
    await createTag(pool, "tt", "dev-a");
    expect((await callJson("DELETE", `${pool.master}/tt`)).status).toBe(401);
    await insertUser(USER);
    const res = await callJson("DELETE", `${pool.master}/tt`, { headers: await bearer(USER) });
    expect(res.status).toBe(403);
    expect(res.body).toEqual({ error: "Forbidden" });
  });

  it("admin は status を removed にする (冪等)。付与実績は残す。無いタグは 404", async () => {
    await createTag(pool, "tt", "dev-a");
    await applyTags(pool, "e1", ["tt"], "dev-1");
    const env = makeEnv({ ADMIN_USER_IDS: ADMIN });
    for (let i = 0; i < 2; i++) {
      const res = await callJson("DELETE", `${pool.master}/tt`, { headers: await bearer(ADMIN), env });
      expect(res.status).toBe(200);
      expect(res.body).toEqual({ id: "tt", status: "removed" });
    }
    expect(await voteCount(pool, "e1", "tt")).toBe(1);
    const missing = await callJson("DELETE", `${pool.master}/missing`, { headers: await bearer(ADMIN), env });
    expect(missing.status).toBe(404);
  });

  it("users.is_admin の admin も削除できる", async () => {
    await createTag(pool, "tt", "dev-a");
    await insertUser(ADMIN, { isAdmin: true });
    const res = await callJson("DELETE", `${pool.master}/tt`, { headers: await bearer(ADMIN) });
    expect(res.status).toBe(200);
  });
});

describe.each(POOLS)("$label タグ: 通報 (POST $master/:id/report)", (pool) => {
  it("同じ端末は 1 日 1 回。3 件で under_review になる", async () => {
    await createTag(pool, "tt", "dev-a");
    const first = await callJson("POST", `${pool.master}/tt/report`, {
      headers: device("dev-r1"), body: { reason: "spam" },
    });
    expect(first.status).toBe(200);
    expect(first.body).toEqual({ ok: true, total_reports: 1 });

    const again = await callJson("POST", `${pool.master}/tt/report`, { headers: device("dev-r1"), body: {} });
    expect(again.status).toBe(429);
    expect(again.body).toEqual({ error: "Already reported today" });

    await callJson("POST", `${pool.master}/tt/report`, { headers: device("dev-r2"), body: {} });
    expect((await row<{ status: string }>(`SELECT status FROM ${pool.table} WHERE id = 'tt'`))?.status)
      .toBe("active");
    const third = await callJson("POST", `${pool.master}/tt/report`, { headers: device("dev-r3"), body: {} });
    expect(third.body).toEqual({ ok: true, total_reports: 3 });
    expect((await row<{ status: string }>(`SELECT status FROM ${pool.table} WHERE id = 'tt'`))?.status)
      .toBe("under_review");
    const reasons = await rows<{ reason: string | null }>(
      `SELECT reason FROM ${pool.reportTable} ORDER BY id`
    );
    expect(reasons.map((r) => r.reason)).toEqual(["spam", null, null]);
  });
});

describe.each(POOLS)("$label タグ: 付与と取り外し ($entity/:id/tags)", (pool) => {
  it("付けた端末が外すと票が減り、0 になった行は消える", async () => {
    await createTag(pool, "t1", "dev-a");
    await applyTags(pool, "e1", ["t1"], "dev-a");
    await applyTags(pool, "e1", ["t1"], "dev-b");

    const first = await callJson("DELETE", `${pool.entity}/e1/tags/t1`, { headers: device("dev-a") });
    expect(first.status).toBe(200);
    expect(first.body).toEqual({ [pool.entityKey]: "e1", tag_id: "t1", removed: true });
    expect(await voteCount(pool, "e1", "t1")).toBe(1);

    await callJson("DELETE", `${pool.entity}/e1/tags/t1`, { headers: device("dev-b") });
    expect(await voteCount(pool, "e1", "t1")).toBeNull();
    expect(await rows(`SELECT * FROM ${pool.deviceTable}`)).toEqual([]);
  });
});

describe("曲タグ: 入力の検証と付与 (ハンドラは 3 プール共通なので曲で代表)", () => {
  const pool = POOLS[0];
  const UID = "001094.edit-user";

  it("説明の編集: 無いタグは 404、削除済みは 403、不正な JSON は 400", async () => {
    await insertUser(UID);
    const auth = await bearer(UID);
    await createTag(pool, "tt", "dev-a");
    await exec(`UPDATE ${pool.table} SET status = 'removed' WHERE id = 'tt'`);

    expect((await callJson("PUT", `${pool.master}/missing`, { headers: auth, body: {} })).body)
      .toEqual({ error: "Tag not found" });
    const removed = await callJson("PUT", `${pool.master}/tt`, { headers: auth, body: {} });
    expect(removed.status).toBe(403);
    expect(removed.body).toEqual({ error: "Tag has been removed" });

    await exec(`UPDATE ${pool.table} SET status = 'active' WHERE id = 'tt'`);
    const invalid = await callJson("PUT", `${pool.master}/tt`, { headers: auth, body: "{" });
    expect(invalid.status).toBe(400);
    expect(invalid.body).toEqual({ error: "invalid JSON body" });
  });

  it("通報: 端末 ID 必須。無いタグは 404", async () => {
    await createTag(pool, "tt", "dev-a");
    expect((await callJson("POST", `${pool.master}/tt/report`, { body: {} })).status).toBe(400);
    const missing = await callJson("POST", `${pool.master}/missing/report`, {
      headers: device("dev-r"), body: {},
    });
    expect(missing.status).toBe(404);
    expect(missing.body).toEqual({ error: "Tag not found" });
  });

  it("端末 ID 必須。tag_ids は空でない配列", async () => {
    const path = `${pool.entity}/e1/tags`;
    expect((await callJson("POST", path, { body: { tag_ids: ["x"] } })).status).toBe(400);
    for (const body of [{}, { tag_ids: [] }, { tag_ids: "x" }]) {
      const res = await callJson("POST", path, { headers: device("dev-a"), body });
      expect(res.status).toBe(400);
      expect(res.body).toEqual({ error: "tag_ids must be a non-empty array" });
    }
    const invalid = await callJson("POST", path, { headers: device("dev-a"), body: "{" });
    expect(invalid.body).toEqual({ error: "invalid JSON body" });
  });

  it("存在して削除されていないタグだけを付け、付けた id を返す", async () => {
    await createTag(pool, "t1", "dev-a");
    await createTag(pool, "t2", "dev-a");
    await exec(`UPDATE ${pool.table} SET status = 'removed' WHERE id = 't2'`);
    const res = await applyTags(pool, "e/1", ["t1", "t2", "nope"], "dev-a");
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ [pool.entityKey]: "e/1", applied_tag_ids: ["t1"] });
    expect(await voteCount(pool, "e/1", "t1")).toBe(1);
    expect(await voteCount(pool, "e/1", "t2")).toBeNull();

    // 別の端末が付けると票が増える。
    await applyTags(pool, "e/1", ["t1"], "dev-b");
    expect(await voteCount(pool, "e/1", "t1")).toBe(2);
  });

  it("一覧は削除済みを除いて票数順。自分が付けたタグを my_tag_ids で返す", async () => {
    await createTag(pool, "t1", "dev-a");
    await createTag(pool, "t2", "dev-a");
    await createTag(pool, "t3", "dev-a");
    await applyTags(pool, "e1", ["t1"], "dev-a");
    await applyTags(pool, "e1", ["t2", "t3"], "dev-b");
    await applyTags(pool, "e1", ["t2"], "dev-c");
    await exec(`UPDATE ${pool.table} SET status = 'removed' WHERE id = 't3'`);

    const mine = await callJson("GET", `${pool.entity}/e1/tags`, { headers: device("dev-b") });
    expect(mine.status).toBe(200);
    expect(mine.res.headers.get("Cache-Control")).toBeNull();
    expect(mine.body.tags).toEqual([
      { id: "t2", name: "t2", color: null, category: null, vote_count: 2 },
      { id: "t1", name: "t1", color: null, category: null, vote_count: 1 },
    ]);
    expect([...mine.body.my_tag_ids].sort()).toEqual(["t2", "t3"]);

    const anon = await callJson("GET", `${pool.entity}/e1/tags?anon=1`);
    expect(anon.body.my_tag_ids).toEqual([]);
  });

  it("取り外しも端末 ID 必須", async () => {
    const res = await callJson("DELETE", `${pool.entity}/e1/tags/t1`);
    expect(res.status).toBe(400);
    expect(res.body).toEqual({ error: "X-Device-Id header is required" });
  });
});

describe("曲タグ: song_tag_counts (類似曲の分母) の追従", () => {
  it("付与と取り外しで、その曲の有効タグ数を数え直す", async () => {
    const pool = POOLS[0];
    await createTag(pool, "aa", "dev-a");
    await createTag(pool, "bb", "dev-a");
    await applyTags(pool, "s1", ["aa", "bb"], "dev-a");
    expect(await row("SELECT tag_count FROM song_tag_counts WHERE song_id = 's1'")).toEqual({ tag_count: 2 });
    await callJson("DELETE", "/songs/s1/tags/aa", { headers: device("dev-a") });
    expect(await row("SELECT tag_count FROM song_tag_counts WHERE song_id = 's1'")).toEqual({ tag_count: 1 });
  });
});

describe("類似 (/songs|idols|units/:id/similar)", () => {
  /** 付与の実績を直接入れる (類似の計算だけを見たいので API を通さない)。 */
  async function seedLinks(pool: Pool, links: Array<[string, string, number]>) {
    for (const [entityId, tagId, votes] of links) {
      await exec(
        `INSERT OR IGNORE INTO ${pool.table} (id, name, created_by, created_at, updated_at)
         VALUES (?, ?, 'dev', 1, 1)`,
        tagId, tagId
      );
      await exec(
        `INSERT INTO ${pool.linkTable} (${pool.entityKey}, tag_id, vote_count) VALUES (?, ?, ?)`,
        entityId, tagId, votes
      );
    }
  }

  it("曲: 減衰つき Jaccard の降順。分母は song_tag_counts。公開キャッシュ", async () => {
    await seedLinks(POOLS[0], [
      ["s1", "a", 1], ["s1", "b", 1],
      ["s2", "a", 3], ["s2", "b", 1],
      ["s3", "a", 5], ["s3", "c", 1], ["s3", "d", 1],
    ]);
    await exec(
      "INSERT INTO song_tag_counts (song_id, tag_count) VALUES ('s1', 2), ('s2', 2), ('s3', 3)"
    );
    const res = await callJson("GET", "/songs/s1/similar");
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe(SIMILAR_CACHE);
    // s2: 2 / (2 + 2 - 2 + 5) / s3: 1 / (2 + 3 - 1 + 5)
    expect(res.body).toEqual({
      song_id: "s1",
      songs: [
        { song_id: "s2", shared_tags: 2, vote_score: 4, score: 2 / 7 },
        { song_id: "s3", shared_tags: 1, vote_score: 5, score: 1 / 9 },
      ],
    });
    const limited = await callJson("GET", "/songs/s1/similar?limit=1");
    expect(limited.body.songs).toHaveLength(1);
  });

  it("曲: 削除済みタグは数えない", async () => {
    await seedLinks(POOLS[0], [["s1", "a", 1], ["s2", "a", 1]]);
    await exec("UPDATE tags SET status = 'removed' WHERE id = 'a'");
    const res = await callJson("GET", "/songs/s1/similar");
    expect(res.body).toEqual({ song_id: "s1", songs: [] });
  });

  it.each([
    [POOLS[1], "/idols", "idols"],
    [POOLS[2], "/units", "units"],
  ] as const)("$1: 共有タグ数 → 票数合計の降順。公開キャッシュ", async (pool, prefix, key) => {
    await seedLinks(pool, [
      ["x", "a", 1], ["x", "b", 1],
      ["y", "a", 2], ["y", "b", 2],
      ["z", "a", 9],
      ["w", "b", 1],
    ]);
    const res = await callJson("GET", `${prefix}/x/similar`);
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe(SIMILAR_CACHE);
    expect(res.body).toEqual({
      [pool.entityKey]: "x",
      [key]: [
        { [pool.entityKey]: "y", shared_tags: 2, score: 4 },
        { [pool.entityKey]: "z", shared_tags: 1, score: 9 },
        { [pool.entityKey]: "w", shared_tags: 1, score: 1 },
      ],
    });
  });
});

describe("GET /tags/activity", () => {
  it("曲とアイドルのタグ付けを横断して返す。公開キャッシュ", async () => {
    await createTag(POOLS[0], "song-tag", "dev-a");
    await createTag(POOLS[1], "idol-tag", "dev-a");
    await applyTags(POOLS[0], "s1", ["song-tag"], "dev-1");
    await applyTags(POOLS[0], "s1", ["song-tag"], "dev-2");
    await applyTags(POOLS[1], "i1", ["idol-tag"], "dev-1");

    const res = await callJson("GET", "/tags/activity?window_days=3");
    expect(res.status).toBe(200);
    expect(res.res.headers.get("Cache-Control")).toBe("public, max-age=600, stale-while-revalidate=1800");
    expect(Object.keys(res.body).sort()).toEqual(["recent", "rising_entities", "trending_tags", "window_days"]);
    expect(res.body.window_days).toBe(3);
    expect(res.body.recent).toHaveLength(3);
    expect(Object.keys(res.body.recent[0]).sort()).toEqual(
      ["created_at", "domain", "entity_id", "tag_category", "tag_color", "tag_id", "tag_name"]
    );
    expect(res.body.trending_tags.map((t: any) => [t.domain, t.tag_id, t.recent_count, t.total_count]))
      .toEqual([["song", "song-tag", 2, 2], ["idol", "idol-tag", 1, 1]]);
    expect(res.body.rising_entities).toEqual([
      { domain: "song", entity_id: "s1", tag_id: "song-tag", tag_name: "song-tag", tag_color: null, recent_count: 2 },
    ]);
  });
});
