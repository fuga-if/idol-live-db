import { test, expect } from "../../support/test";

test.describe("P名刺 (/p/)", () => {
  test("読めない名刺は「読み取れませんでした」と出し、アプリへの導線は残す", { tag: "@CARD-001" }, async ({ page }) => {
    await page.goto("/p/#this-is-not-a-card");
    await expect(page.getByText("この名刺は読み取れませんでした")).toBeVisible();
  });
});
