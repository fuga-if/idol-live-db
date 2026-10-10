// migrations/0050: 髪のアイドルタグを退役する。消した後、アプリのタグの画面 (一覧・詳細・アイドルごとのタグ)
// から髪のタグだけが無くなり、髪以外のタグと他人の票は残ることを確かめる。
// migration は適用済みの DB に当てる前提なので、テストでは空の DB に行を足してからファイルの SQL を流す。

import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import { callJson } from "./support/worker";

const HAIR = ["ロングヘア", "黒髪", "白髪・銀髪", "ボブ〜ミディアムヘア", "ポニーテール", "おでこ", "アホ毛"];

async function exec(sql: string, ...binds: unknown[]) {
  await env.DB.prepare(sql).bind(...binds).run();
}

async function runMigration() {
  // vitest.config.ts が migrations/ を読んで TEST_MIGRATIONS に入れている (文に分割済み)。
  const m = env.TEST_MIGRATIONS.find((x) => x.name.startsWith("0050_retire_hair_idol_tags"));
  expect(m, "migration が見つからない").toBeDefined();
  await env.DB.batch(m!.queries.map((q) => env.DB.prepare(q)));
}

describe("髪のアイドルタグの退役 (migration 0050)", () => {
  it("髪のタグの行と票・履歴は消え、髪以外のタグは残る", async () => {
    const all = [...HAIR, "メガネ"];
    for (const [i, name] of all.entries()) {
      await exec(
        "INSERT INTO idol_tag_master (id, name, category, created_by, created_at, updated_at) VALUES (?, ?, 'charm', 'dev', 1, 1)",
        `t${i}`, name,
      );
      await exec("INSERT INTO idol_tags (idol_id, tag_id, vote_count) VALUES ('765as_天海春香', ?, 2)", `t${i}`);
      await exec("INSERT INTO device_idol_tag (device_id, idol_id, tag_id, created_at) VALUES ('d1', '765as_天海春香', ?, 1)", `t${i}`);
      await exec("INSERT INTO idol_tag_description_history (tag_id, description, edited_by, edited_at) VALUES (?, 'x', 'dev', 1)", `t${i}`);
    }
    const before = await callJson("GET", "/idol-tags?limit=100&sort=name&a=1");
    expect(before.body.tags.map((t: any) => t.name)).toContain("黒髪");

    await runMigration();

    // 一覧・詳細・アイドルごとのタグ (アプリのタグの画面が読む 3 つ) から髪のタグが消える。
    const list = await callJson("GET", "/idol-tags?limit=100&sort=name&a=2");
    expect(list.body.tags.map((t: any) => t.name)).toEqual(["メガネ"]);
    expect((await callJson("GET", "/idol-tags/t1")).status).toBe(404);
    const ofIdol = await callJson("GET", "/idols/765as_天海春香/tags?a=3");
    expect(ofIdol.status).toBe(200);
    expect(JSON.stringify(ofIdol.body)).not.toContain("黒髪");
    expect(JSON.stringify(ofIdol.body)).toContain("メガネ");

    for (const table of ["idol_tags", "device_idol_tag", "idol_tag_description_history"]) {
      const row = await env.DB.prepare(`SELECT count(*) AS n FROM ${table}`).first<{ n: number }>();
      expect(row?.n, table).toBe(1);
    }
  });

  it("流しても何度でも同じ結果 (2 回目は何も消さない)", async () => {
    await exec("INSERT INTO idol_tag_master (id, name, created_by, created_at, updated_at) VALUES ('k', 'クール', 'dev', 1, 1)");
    await runMigration();
    await runMigration();
    const row = await env.DB.prepare("SELECT count(*) AS n FROM idol_tag_master").first<{ n: number }>();
    expect(row?.n).toBe(1);
  });
});
