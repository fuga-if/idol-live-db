import { test, expect, mockLyricsApi, ignoreBlockedRequests } from "../../support/test";

test.describe("検索", () => {
  test("名前を打つと種別ごとに結果が出て、結果から曲のページへ行ける", { tag: "@SEARCH-001" }, async ({ page, problems }) => {
    await page.goto("/search/");
    // JS が動いたら「JS を有効にすると…」の案内は下がる。
    await expect(page.locator("[data-search-fallback]")).toBeHidden();
    const input = page.locator("[data-search-input]");
    await input.click();
    await input.fill("さんきゅー");
    const results = page.locator("[data-search-results]");
    await expect(results.getByRole("heading", { name: "楽曲" })).toBeVisible();
    // Enter を押してもページは送信されない (島が横取りする)。検索語は URL に写るだけで、
    // 共有・再読み込みでも同じ結果になる。
    let navigated = false;
    page.on("framenavigated", (f) => {
      if (f === page.mainFrame()) navigated = true;
    });
    await input.press("Enter");
    await expect(page).toHaveURL(/\/search\/\?q=/);
    expect(navigated).toBe(false);
    await results.getByRole("link", { name: /Thank You!/ }).click();
    await expect(page).toHaveURL("/songs/ml_sample/");
    ignoreBlockedRequests(problems);
    problems.expectClean();
  });

  test("ひらがな・カタカナ・大文字小文字の違いを畳んで当てる", { tag: "@SEARCH-002" }, async ({ page }) => {
    await page.goto("/search/");
    const input = page.locator("[data-search-input]");
    await input.fill("カスガミライ");
    await expect(page.locator("[data-search-results]").getByRole("link", { name: /春日未来/ })).toBeVisible();
    await input.fill("THANK YOU");
    await expect(page.locator("[data-search-results]").getByRole("link", { name: /Thank You!/ })).toBeVisible();
  });

  test("当たらない語では 0 件と伝え、結果を空にする", { tag: "@SEARCH-003" }, async ({ page }) => {
    await page.goto("/search/");
    const input = page.locator("[data-search-input]");
    await input.fill("さんきゅー");
    await expect(page.locator("[data-search-results] a").first()).toBeVisible();
    await input.fill("ぜったいにないことば");
    await expect(page.locator("[data-search-results] a")).toHaveCount(0);
    await expect(page.locator("[data-search-status]")).not.toBeEmpty();
  });

  test("歌詞モードでは歌詞 API に 1 回だけ問い合わせ、一致箇所を添えて曲を出す", { tag: "@SEARCH-004" }, async ({ page }) => {
    const hits = await mockLyricsApi(page, /\/lyrics\/search\?/, {
      query: "ありがとう",
      hits: [{ songId: "ml_sample", snippets: [{ snippet: "いつもありがとうの歌", matchStart: 3, matchLength: 5 }] }],
    });
    await page.goto("/search/");
    await page.getByText("歌詞", { exact: true }).click();
    const input = page.locator("[data-search-input]");
    await input.pressSequentially("ありがとう");
    const results = page.locator("[data-search-results]");
    await expect(results.locator("mark")).toHaveText("ありがとう");
    await expect(results.getByRole("link", { name: /Thank You!/ })).toBeVisible();
    // 打鍵ごとには飛ばさない (まとめて 1 回)。
    expect(hits).toHaveLength(1);
    expect(decodeURIComponent(hits[0] ?? "")).toContain("q=ありがとう");
  });

  test("歌詞の一致箇所はコピー・切り取り・ドラッグできない", { tag: "@SEARCH-005" }, async ({ page }) => {
    await mockLyricsApi(page, /\/lyrics\/search\?/, {
      query: "ありがとう",
      hits: [{ songId: "ml_sample", snippets: [{ snippet: "いつもありがとうの歌", matchStart: 3, matchLength: 5 }] }],
    });
    await page.goto("/search/?mode=lyrics&q=ありがとう");
    const snippet = page.locator(".search-snippet").first();
    await expect(snippet).toBeVisible();
    for (const type of ["copy", "cut", "dragstart"]) {
      const prevented = await snippet.evaluate((el, t) => {
        const ev = new Event(t, { bubbles: true, cancelable: true });
        el.dispatchEvent(ev);
        return ev.defaultPrevented;
      }, type);
      expect(prevented, type).toBe(true);
    }
  });

  test("歌詞 API が落ちていたら失敗を伝える", { tag: "@SEARCH-006" }, async ({ page }) => {
    await mockLyricsApi(page, /\/lyrics\/search\?/, null);
    await page.goto("/search/?mode=lyrics&q=ありがとう");
    await expect(page.locator("[data-search-status]")).toHaveText(/失敗/);
  });
});
