import fs from "node:fs";
import { test, expect, ignoreBlockedRequests } from "../../support/test";

/** フィクスチャのルート台帳。全ページ種別の代表 URL がここに揃っている。 */
const routes: { path: string; kind: string }[] = JSON.parse(
  fs.readFileSync(new URL("../../../data-fixture/routes.json", import.meta.url), "utf8"),
).routes;

test.describe("全ページ種別が開ける", { tag: "@PAGE-001" }, () => {
  for (const r of routes) {
    test(`${r.kind} ${r.path}`, async ({ page, problems }) => {
      const res = await page.goto(r.path);
      expect(res?.status(), r.path).toBe(200);
      await expect(page.locator("h1").first()).toBeVisible();
      // ヘッダの検索窓とタブは全ページにある (ここが崩れると回遊できない)。
      await expect(page.locator("header")).toBeVisible();
      ignoreBlockedRequests(problems);
      problems.expectClean();
    });
  }
});

test("知らない URL は 404 で返し、その場の検索窓から探し直せる", { tag: "@PAGE-002" }, async ({ page, problems }) => {
  const res = await page.goto("/no-such-page-e2e/");
  expect(res?.status()).toBe(404);
  await expect(page.locator("h1").first()).toBeVisible();
  const box = page.locator(".hero .search-box__input");
  await box.fill("Thank");
  await box.press("Enter");
  await expect(page).toHaveURL(/\/search\/\?q=Thank/);
  await expect(page.locator("[data-search-results]").getByRole("link", { name: /Thank You!/ })).toBeVisible();
  ignoreBlockedRequests(problems);
  problems.expectClean();
});

test("末尾のスラッシュが無い URL はスラッシュ付きに寄せる", { tag: "@PAGE-003" }, async ({ page }) => {
  await page.goto("/songs");
  await expect(page).toHaveURL("/songs/");
});
