// migrations/0050: アイドルの容姿 (髪) の公式タグ。カテゴリは既存の「魅力・外見」(charm)。語はオーナーの確認表
// (data/research/appearance_20261010/idol_appearance_review_20261010.csv の「入れるタグ」列) とそろえてある。

import { describe, expect, it } from "vitest";
import { callJson, device } from "./support/worker";

describe("アイドルの容姿の公式タグ (migration 0050)", () => {
  it("魅力・外見の分類に 45 語が公式として入る", async () => {
    const res = await callJson("GET", "/idol-tags?category=charm&sort=name");
    expect(res.status).toBe(200);
    expect(res.body.total).toBe(45);
    const names = res.body.tags.map((t: any) => t.name);
    for (const name of ["黒髪", "白髪・銀髪", "ボブ〜ミディアムヘア", "三つ編み・編み込み", "外はね", "跳ね毛", "おでこ", "髪飾り"]) {
      expect(names).toContain(name);
    }
    expect(res.body.tags.every((t: any) => t.category === "charm")).toBe(true);
  });

  it("詳細では公式と分かる", async () => {
    const res = await callJson("GET", "/idol-tags/official_appearance_hair_brown");
    expect(res.status).toBe(200);
    expect(res.body.tag).toMatchObject({ name: "茶髪", category: "charm", is_official: 1, description: "髪色" });
  });

  it("利用者の端末は運営の端末 ID (official:) を名乗れない", async () => {
    const res = await callJson("POST", "/idols/765as_天海春香/tags", {
      headers: device("official:appearance-20261010"),
      body: { tag_ids: ["official_appearance_hair_brown"] },
    });
    expect(res.status).toBe(400);
  });
});
