// migrations/0050: アイドルの「容姿」の公式タグ。語はオーナーの確認表
// (data/fixes/idol_appearance_review_20261010.csv の「入れるタグ」列) とそろえてある。

import { describe, expect, it } from "vitest";
import { callJson } from "./support/worker";

describe("アイドルの容姿の公式タグ (migration 0050)", () => {
  it("容姿の分類で 40 語が公式として一覧に出る", async () => {
    const res = await callJson("GET", "/idol-tags?category=appearance&sort=name");
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(40);
    const names = res.body.tags.map((t: any) => t.name);
    for (const name of ["黒髪", "水色の髪", "ロングヘア", "ツインテール", "おでこ出し", "髪飾り"]) {
      expect(names).toContain(name);
    }
    expect(res.body.tags.every((t: any) => t.category === "appearance")).toBe(true);
  });

  it("詳細では公式と分かる", async () => {
    const res = await callJson("GET", "/idol-tags/official_appearance_hair_black");
    expect(res.status).toBe(200);
    expect(res.body.tag).toMatchObject({ name: "黒髪", category: "appearance", is_official: 1, description: "髪色" });
  });
});
