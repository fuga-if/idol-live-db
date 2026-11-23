import { test, expect, mockLyricsApi, ignoreBlockedRequests } from "../../support/test";

const LYRICS = /\/songs\/[^/]+\/lyrics$/;
const LINES = {
  lines: [
    { text: "はじめの一行", kind: "lyric", calls: [] },
    { text: "ふたつめの行です", kind: "lyric", calls: [] },
    { text: "五輪咲《ごりん》の夢を", kind: "lyric", calls: [] },
    { text: "おわりの行", kind: "lyric", calls: [] },
  ],
};

test.describe("歌詞の一部をリンクで共有する", () => {
  test("行を押すとその行が塗られ、帯からその行へのリンクをコピーできる (本文は写らない)", { tag: "@LYRICS-005" }, async ({ page, context, problems }) => {
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    await mockLyricsApi(page, LYRICS, LINES);
    await page.goto("/songs/ml_sample/#tab-lyrics");
    await page.locator("[data-lyrics-load]").click();
    await expect(page.locator("[data-lyrics-share-hint]")).toBeVisible();
    const bar = page.locator("[data-lyrics-share]");
    await expect(bar).toBeHidden();

    await page.locator(".lyrics__line").nth(1).locator(".lyrics__text").click();
    await expect(bar).toBeVisible();
    await expect(page.locator("[data-lyrics-share-lines]")).toHaveText("2行目");
    await expect(page.locator(".lyrics__mark")).toHaveCount(1);
    // 塗りは曲の歌い手の色 (フィクスチャは 2 人で歌う曲なのでブランド)。
    await expect(page.locator(".lyrics__marks")).toHaveAttribute("data-theme", "brand:ml");

    await page.locator("[data-lyrics-share-copy]").click();
    await expect(page.locator("[data-lyrics-share-copy]")).toHaveText("コピーしました");
    const copied = await page.evaluate(() => navigator.clipboard.readText());
    expect(copied).toMatch(/\/songs\/ml_sample\/#lyric-2$/);

    // ⌘C / Ctrl+C でも、写るのは本文ではなくリンク。
    const viaCopy = await page.evaluate(() => {
      const data = new DataTransfer();
      const ev = new ClipboardEvent("copy", { clipboardData: data, bubbles: true, cancelable: true });
      document.dispatchEvent(ev);
      return data.getData("text/plain");
    });
    expect(viaCopy).toMatch(/#lyric-2$/);

    // もう一度押すと外れる。外を押しても外れる。
    await page.locator(".lyrics__line").nth(1).locator(".lyrics__text").click();
    await expect(bar).toBeHidden();
    await expect(page.locator(".lyrics__mark")).toHaveCount(0);
    await page.locator(".lyrics__line").nth(0).locator(".lyrics__text").click();
    await expect(bar).toBeVisible();
    await page.locator("[data-lyrics-share-close]").click();
    await expect(bar).toBeHidden();
    await page.locator(".lyrics__line").nth(3).locator(".lyrics__text").click();
    await expect(bar).toBeVisible();
    await page.keyboard.press("Escape");
    await expect(bar).toBeHidden();
    await page.locator(".lyrics__line").nth(3).locator(".lyrics__text").click();
    await page.locator(".lyrics__license").click();
    await expect(bar).toBeHidden();
    ignoreBlockedRequests(problems);
    problems.expectClean();
  });

  test("マウスでなぞると字の位置まで選べ、URL に行と位置が入る", { tag: "@LYRICS-006" }, async ({ page, context, isMobile }) => {
    test.skip(isMobile, "なぞりはマウスの操作");
    await context.grantPermissions(["clipboard-read", "clipboard-write"]);
    await mockLyricsApi(page, LYRICS, LINES);
    await page.goto("/songs/ml_sample/#tab-lyrics");
    await page.locator("[data-lyrics-load]").click();
    // 1 行目の 3 字目の左から、2 行目の 4 字目の右まで。
    const charBox = async (line: number, index: number) =>
      page.locator(".lyrics__line").nth(line).locator(".lyrics__text").evaluate((el, i) => {
        const node = el.firstChild as Text;
        const r = document.createRange();
        r.setStart(node, i);
        r.setEnd(node, i + 1);
        const b = r.getBoundingClientRect();
        return { left: b.left, right: b.right, y: (b.top + b.bottom) / 2 };
      }, index);
    const a = await charBox(0, 2);
    const b = await charBox(1, 3);
    await page.mouse.move(a.left + 1, a.y);
    await page.mouse.down();
    await page.mouse.move((a.left + b.right) / 2, (a.y + b.y) / 2, { steps: 4 });
    await page.mouse.move(b.right - 1, b.y, { steps: 4 });
    await page.mouse.up();
    await expect(page.locator("[data-lyrics-share-lines]")).toHaveText("1〜2行目");
    await expect(page.locator(".lyrics__mark")).toHaveCount(2);
    await page.locator("[data-lyrics-share-copy]").click();
    const copied = await page.evaluate(() => navigator.clipboard.readText());
    expect(copied).toMatch(/#lyric-1\.2-2\.4$/);
  });

  test("共有された URL で開くと、歌詞のタブを開いて読み込み、その場所を塗って送る", { tag: "@LYRICS-007" }, async ({ page, problems }) => {
    const hits = await mockLyricsApi(page, LYRICS, LINES);
    await page.goto("/songs/ml_sample/#lyric-3-4");
    const body = page.locator("[data-lyrics-body]");
    await expect(body).toBeVisible();
    expect(hits).toHaveLength(1);
    await expect(page.locator("#song-tab-lyrics")).toBeChecked();
    await expect(page.locator(".lyrics__mark").first()).toBeVisible();
    await expect(page.locator("#lyric-line-3")).toHaveAttribute("data-picked", "");
    await expect(page.locator("#lyric-line-4")).toHaveAttribute("data-picked", "");
    await expect(page.locator("#lyric-line-1")).not.toHaveAttribute("data-picked", "");
    await expect(page.locator("#lyric-line-3")).toBeInViewport();
    // 着いただけでは共有の帯は出さない (読むのが先)。
    await expect(page.locator("[data-lyrics-share]")).toBeHidden();
    await expect(page.locator("[data-lyrics-status]")).toContainText("3〜4行目");

    // 行内の位置つき。振り仮名つきの字は丸ごと塗る。範囲外の数は行末に丸める。
    await page.evaluate(() => (location.hash = "#lyric-3.1-3.99"));
    await expect(page.locator("[data-lyrics-status]")).toContainText("(3行目)");
    expect(hits).toHaveLength(1);
    ignoreBlockedRequests(problems);
    problems.expectClean();
  });
});
