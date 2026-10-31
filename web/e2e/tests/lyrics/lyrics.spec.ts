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

  test("振り仮名・被せ・歌い分け・歌詞と同じ文字のコールをアプリと同じに出す", { tag: "@LYRICS-004" }, async ({ page }) => {
    await mockLyricsApi(page, LYRICS, {
      lines: [
        // 振り仮名 (親字《よみ》) と括弧の被せ。未来が歌う。
        { text: "五輪咲《ごりん》の夢を（夢を）", kind: "lyric", calls: [], singers: ["ml_kasuga_mirai"], partBreaks: [] },
        // 途中で歌う人が変わる行 (前半は 2 人)。歌詞と同じ文字のコール (同時) と、別の文字のコール。
        {
          text: "はいはいここから",
          kind: "lyric",
          singers: ["ml_kasuga_mirai", "ml_mogami_shizuka"],
          partBreaks: [{ at: 4, singers: ["ml_mogami_shizuka"] }],
          calls: [
            { id: "c1", start: 0, end: 4, text: "ハイハイ", timing: "over" },
            { id: "c2", start: 4, end: 8, text: "オーイ", timing: "after" },
          ],
        },
      ],
    });
    await page.goto("/songs/ml_sample/");
    await page.locator("[data-lyrics-load]").click();
    const lines = page.locator("[data-lyrics-body] .lyrics__line");
    const first = lines.nth(0);
    const second = lines.nth(1);
    await expect(first).toBeVisible();

    // 記号は出さず、読みは親字の上 (<rt>)。
    await expect(first.locator("ruby")).toHaveCount(1);
    await expect(first.locator("rt")).toHaveText("ごりん");
    await expect(first).not.toContainText("《");
    // 被せは小さい字。
    await expect(first.locator(".lyrics__run--aside")).toHaveText("（夢を）");
    // 1 人の字は担当色、行の下に名前。
    await expect(first.locator(".lyrics__run[data-part]").first()).toHaveAttribute("data-theme", "idol:ml_kasuga_mirai");
    await expect(first.locator(".lyrics__parts")).toHaveText("未来");

    // 2 人で歌う字は縞、名前は途中で変わるところを「→」でつなぐ。
    await expect(second.locator(".lyrics__run[data-stripes='2']")).toHaveText("はいはい");
    await expect(second.locator(".lyrics__parts")).toHaveText("未来・静香 → 静香");
    // 歌詞と同じ文字のコールは行に並べず、歌詞を濃く敷く。別の文字のコールは並べる。
    await expect(second.locator(".lyrics__anchor[data-echo]")).toHaveText("はいはい");
    await expect(second.locator(".lyrics__call")).toHaveCount(1);
    await expect(second.locator(".lyrics__call")).toHaveText("オーイ");
  });
});
