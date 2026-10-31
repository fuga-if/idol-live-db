import { test, expect, mockLyricsApi } from "../../support/test";

const LYRICS = /\/songs\/[^/]+\/lyrics$/;

test.describe("曲ページの歌詞とコールガイド", () => {
  test("静的な HTML に歌詞は無く、押したときに 1 曲ぶんだけ取って表示する", { tag: "@LYRICS-001" }, async ({ page }) => {
    const hits = await mockLyricsApi(page, LYRICS, {
      lines: [
        { text: "はじめの一行", kind: "lyric", calls: [] },
        { text: "ハイ！ハイ！", kind: "call", calls: [] },
      ],
    });
    await page.goto("/songs/ml_sample/");
    // 許諾番号は押す前から見える位置にある。
    await expect(page.locator(".lyrics__license")).toContainText("JASRAC");
    await expect(page.locator("[data-lyrics-body]")).toBeHidden();
    expect(hits).toHaveLength(0);

    await page.locator("[data-lyrics-load]").click();
    const body = page.locator("[data-lyrics-body]");
    await expect(body).toBeVisible();
    await expect(body).toContainText("はじめの一行");
    await expect(body).toBeFocused();
    await expect(page.locator("[data-lyrics-load]")).toBeHidden();
    expect(hits).toHaveLength(1);
  });

  test("取れなかったら案内を出し、もう一度押せる", { tag: "@LYRICS-002" }, async ({ page }) => {
    await mockLyricsApi(page, LYRICS, null);
    await page.goto("/songs/ml_sample/");
    const button = page.locator("[data-lyrics-load]");
    await button.click();
    await expect(page.locator("[data-lyrics-status]")).toHaveText(/読み込めませんでした/);
    await expect(button).toBeEnabled();
  });

  test("歌詞の本文はコピー・切り取り・ドラッグできない", { tag: "@LYRICS-003" }, async ({ page }) => {
    await mockLyricsApi(page, LYRICS, { lines: [{ text: "はじめの一行", kind: "lyric", calls: [] }] });
    await page.goto("/songs/ml_sample/");
    await page.locator("[data-lyrics-load]").click();
    const line = page.locator("[data-lyrics-body] .lyrics__line").first();
    await expect(line).toBeVisible();
    for (const type of ["copy", "cut", "dragstart"]) {
      const prevented = await line.evaluate((el, t) => {
        const ev = new Event(t, { bubbles: true, cancelable: true });
        el.dispatchEvent(ev);
        return ev.defaultPrevented;
      }, type);
      expect(prevented, type).toBe(true);
    }
  });
});
