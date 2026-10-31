import { test, expect } from "../../support/test";

/** セトリのある公演ページ。歌唱者の表示とセトリの詳しさの切り替えが両方載っている。 */
const SHOW = "/shows/sh_sample_1/";

test.describe("表示の好み (端末に保存)", () => {
  test("歌唱者の表示を切り替えると、その場で変わり、次に開いても残る", { tag: "@PREF-001" }, async ({ page }) => {
    await page.goto(SHOW);
    const select = page.locator("[data-performer-select]");
    await expect(select).toBeVisible();
    await expect(page.locator("body")).toHaveAttribute("data-performer-name", "idol");
    await select.selectOption("cast");
    await expect(page.locator("body")).toHaveAttribute("data-performer-name", "cast");
    await page.reload();
    await expect(page.locator("body")).toHaveAttribute("data-performer-name", "cast");
    await expect(select).toHaveValue("cast");
  });

  test("セトリの詳しさを切り替えると、その場で変わり、次に開いても残る", { tag: "@PREF-002" }, async ({ page }) => {
    await page.goto(SHOW);
    const select = page.locator("[data-setlist-select]");
    await expect(select).toBeVisible();
    await expect(page.locator("body")).toHaveAttribute("data-setlist-display", "normal");
    await select.selectOption("detailed");
    await expect(page.locator("body")).toHaveAttribute("data-setlist-display", "detailed");
    await page.reload();
    await expect(page.locator("body")).toHaveAttribute("data-setlist-display", "detailed");
  });
});
