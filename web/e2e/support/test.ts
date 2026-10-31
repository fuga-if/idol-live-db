/**
 * E2E の共通の土台。すべてのテストはここの `test` / `expect` を使う。
 *
 * - **外へは出さない。** 自分のオリジン (localhost) 以外への通信は既定で止める
 *   (Apple Music のジャケ画像、歌詞 API など)。歌詞 API を使うテストは
 *   `page.route` で差し替えてから開く (後から登録した route が先に当たる)。
 * - **壊れたら気づく。** ページの例外・console.error・CSP 違反を `problems` に集める。
 *   `expectClean()` で 0 件を確かめる。CSP は `style-src 'self'` (inline 不可) なので、
 *   インライン style を書いた瞬間に見た目が死ぬ。その手の事故をここで拾う。
 */
import { test as base, expect, type Page } from "@playwright/test";

export interface Problems {
  list: string[];
  /** ここまでに例外・console.error・CSP 違反が 1 件も無いこと。 */
  expectClean(): void;
}

export const test = base.extend<{ problems: Problems }>({
  problems: async ({ page }, use) => {
    const list: string[] = [];
    page.on("pageerror", (e) => list.push(`pageerror: ${e.message}`));
    page.on("console", (m) => {
      if (m.type() === "error") list.push(`console.error: ${m.text()}`);
    });
    await page.addInitScript(() => {
      document.addEventListener("securitypolicyviolation", (e) => {
        console.error(`CSP 違反: ${e.violatedDirective} ${e.blockedURI}`);
      });
    });
    await use({
      list,
      expectClean() {
        expect(list, list.join("\n")).toEqual([]);
      },
    });
  },
  page: async ({ page }, use) => {
    await page.route(
      (url) => url.hostname !== "localhost",
      (route) => route.abort("blockedbyclient"),
    );
    await use(page);
  },
});

export { expect };

/** 外部を止めたことで出る console.error (読み込み失敗) は問題として数えない。 */
export function ignoreBlockedRequests(problems: Problems): void {
  const keep = problems.list.filter((m) => !/ERR_BLOCKED_BY_CLIENT|Failed to load resource/.test(m));
  problems.list.splice(0, problems.list.length, ...keep);
}

/** 歌詞 API (Worker) を差し替える。`body` が null なら 500 を返す。 */
export async function mockLyricsApi(page: Page, pattern: RegExp, body: unknown | null, status = 200): Promise<string[]> {
  const hits: string[] = [];
  await page.route(pattern, (route) => {
    hits.push(route.request().url());
    if (body === null) return route.fulfill({ status: 500, body: "" });
    return route.fulfill({
      status,
      contentType: "application/json",
      headers: { "access-control-allow-origin": "*" },
      body: JSON.stringify(body),
    });
  });
  return hits;
}
