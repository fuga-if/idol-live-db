// 端末集計のカウンタ (タグ 3 プール・お気に入り) は、端末の行が実際に変わったときだけ動く。
//   - 同じ端末の再送では増えない。
//   - 付けていない端末の取り消しでは減らない。
//   - tag_ids に同じ id が重複していても +1 だけ。
// D1 の changes() の意味に依存するので、スタブではなく実 D1 で確かめる。

import { describe, expect, it } from "vitest";
import { callJson, device, makeEnv } from "./support/worker";
import { exec, meterD1, row } from "./support/d1";

const POOLS = [
  { label: "曲", master: "tags", entity: "/songs", link: "song_tags", key: "song_id" },
  { label: "アイドル", master: "idol_tag_master", entity: "/idols", link: "idol_tags", key: "idol_id" },
] as const;

type Pool = (typeof POOLS)[number];

async function seedTag(pool: Pool, id: string) {
  await exec(
    `INSERT INTO ${pool.master} (id, name, created_by, created_at, updated_at) VALUES (?, ?, 'dev', 1, 1)`,
    id, id
  );
}

async function votes(pool: Pool, entityId: string, tagId: string): Promise<number | null> {
  const r = await row<{ vote_count: number }>(
    `SELECT vote_count FROM ${pool.link} WHERE ${pool.key} = ? AND tag_id = ?`, entityId, tagId
  );
  return r?.vote_count ?? null;
}

const apply = (pool: Pool, entityId: string, tagIds: string[], deviceId: string, env = makeEnv()) =>
  callJson("POST", `${pool.entity}/${entityId}/tags`, { headers: device(deviceId), body: { tag_ids: tagIds }, env });

const remove = (pool: Pool, entityId: string, tagId: string, deviceId: string, env = makeEnv()) =>
  callJson("DELETE", `${pool.entity}/${entityId}/tags/${tagId}`, { headers: device(deviceId), env });

describe("タグの票 (ハンドラは 3 プール共通なので曲で代表)", () => {
  const pool = POOLS[0];

  it("同じ端末の再送では増えない", async () => {
    await seedTag(pool, "t1");
    expect((await apply(pool, "e1", ["t1"], "dev-a")).body.applied_tag_ids).toEqual(["t1"]);
    expect((await apply(pool, "e1", ["t1"], "dev-a")).body.applied_tag_ids).toEqual([]);
    expect(await votes(pool, "e1", "t1")).toBe(1);
  });

  it("tag_ids に同じ id が重複していても +1 だけ", async () => {
    await seedTag(pool, "t1");
    const res = await apply(pool, "e1", ["t1", "t1", "t1"], "dev-a");
    expect(res.body.applied_tag_ids).toEqual(["t1"]);
    expect(await votes(pool, "e1", "t1")).toBe(1);
  });

  it("付けていない端末が外しても減らない", async () => {
    await seedTag(pool, "t1");
    await apply(pool, "e1", ["t1"], "dev-a");
    const res = await remove(pool, "e1", "t1", "dev-b");
    expect(res.body).toEqual({ [pool.key]: "e1", tag_id: "t1", removed: false });
    expect(await votes(pool, "e1", "t1")).toBe(1);
  });
});

// 読み取り行数は曲とアイドル・ユニットで違う。アイドルとユニットは同じ文なのでアイドルで代表する。
describe.each(POOLS)("$label タグの票", (pool) => {
  it("D1 の読み取り行数は変更前を超えない", async () => {
    await seedTag(pool, "t1");
    await seedTag(pool, "t2");
    // 変更前の実測 (曲 / アイドル・ユニット): 付与 3 / 1、再付与 7 / 4、
    // 付けていない端末が外す 5 / 2、外す 8 / 5。
    const budget = pool.label === "曲"
      ? { first: 3, again: 7, stranger: 5, remove: 8 }
      : { first: 1, again: 4, stranger: 2, remove: 5 };
    const m = meterD1();
    const env = makeEnv({ DB: m.db });
    const measure = async (work: () => Promise<unknown>) => {
      m.reset();
      await work();
      return m.usage.rowsRead;
    };
    expect(await measure(() => apply(pool, "e1", ["t1"], "dev-a", env))).toBeLessThanOrEqual(budget.first);
    expect(await measure(() => apply(pool, "e1", ["t1"], "dev-a", env))).toBeLessThanOrEqual(budget.again);
    expect(await measure(() => remove(pool, "e1", "t2", "dev-a", env))).toBeLessThanOrEqual(budget.stranger);
    expect(await measure(() => remove(pool, "e1", "t1", "dev-a", env))).toBeLessThanOrEqual(budget.remove);
  });
});

describe("お気に入りの数", () => {
  const toggle = (value: boolean, deviceId: string, env = makeEnv()) =>
    callJson("POST", "/favorites/toggle", { headers: device(deviceId), body: { song_id: "s1", value }, env });

  it("同じ端末の再送では増えない", async () => {
    await toggle(true, "dev-a");
    expect((await toggle(true, "dev-a")).body).toEqual({ song_id: "s1", count: 1 });
  });

  it("登録していない端末の解除では減らない", async () => {
    await toggle(true, "dev-a");
    expect((await toggle(false, "dev-b")).body).toEqual({ song_id: "s1", count: 1 });
  });

  it("D1 の読み取り行数は変更前を超えない", async () => {
    // 変更前の実測: 登録 1、再登録 4、登録していない端末の解除 4、解除 5。
    const m = meterD1();
    const env = makeEnv({ DB: m.db });
    const measure = async (work: () => Promise<unknown>) => {
      m.reset();
      await work();
      return m.usage.rowsRead;
    };
    expect(await measure(() => toggle(true, "dev-a", env))).toBeLessThanOrEqual(1);
    expect(await measure(() => toggle(true, "dev-a", env))).toBeLessThanOrEqual(4);
    expect(await measure(() => toggle(false, "dev-b", env))).toBeLessThanOrEqual(4);
    expect(await measure(() => toggle(false, "dev-a", env))).toBeLessThanOrEqual(5);
  });
});
