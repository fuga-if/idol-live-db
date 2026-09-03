// @ts-check
import fs from "node:fs";
import path from "node:path";
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";

/**
 * sitemap から外すパス集合。
 * 「どのページを index させないか」の判断は Rust (SeoBlock.robots) が持ち、
 * ここはその結果 (routes.json の noindexPaths) を写すだけ。
 * ※ web/data が無い状態 (npm run check だけ回すとき) でも config が壊れないようにする。
 */
function noindexPaths() {
  const root = path.resolve(process.env.IMAS_WEB_DATA ?? "./data");
  const file = path.join(root, "routes.json");
  if (!fs.existsSync(file)) return new Set();
  try {
    const routes = JSON.parse(fs.readFileSync(file, "utf8"));
    return new Set(routes.noindexPaths ?? []);
  } catch {
    return new Set();
  }
}

const noindex = noindexPaths();

/**
 * 検索索引 (`<data>/search/*.json`) を `dist/search/` へ写す。
 * `web/data/` は public/ の外に置いてある (詳細ページ 7,600 個を dist に出さないため) ので、
 * 配信が要るファイルだけをここで運ぶ。index.html と同じディレクトリに同居できる。
 */
function copySearchIndex() {
  return {
    name: "imas:copy-search-index",
    hooks: {
      /** @param {{ dir: URL, logger: { info: (m: string) => void, warn: (m: string) => void } }} ctx */
      "astro:build:done": ({ dir, logger }) => {
        const src = path.join(path.resolve(process.env.IMAS_WEB_DATA ?? "./data"), "search");
        if (!fs.existsSync(src)) {
          logger.warn(`検索索引が見つかりません: ${src} (/search/ は結果を出せません)`);
          return;
        }
        const dest = new URL("search/", dir);
        fs.mkdirSync(dest, { recursive: true });
        let n = 0;
        for (const name of fs.readdirSync(src)) {
          if (!name.endsWith(".json")) continue;
          fs.copyFileSync(path.join(src, name), new URL(name, dest));
          n += 1;
        }
        logger.info(`検索索引 ${n} ファイルを dist/search/ に配置しました`);
      },
    },
  };
}

export default defineConfig({
  site: "https://imas-live-web.tokata3011.workers.dev",
  output: "static",
  trailingSlash: "always",
  // CSP (public/_headers) が `style-src 'self'` = unsafe-inline 無しなので、
  // CSS は必ず外部ファイルにする ("auto" だと小さい CSS が <style> に入って全ページで死ぬ)。
  build: { format: "directory", inlineStylesheets: "never" },
  compressHTML: true,
  integrations: [
    copySearchIndex(),
    sitemap({
      filter: (page) => {
        const p = new URL(page).pathname;
        // percent-encode の揺れ (Astro は `@` を素で出す) で取りこぼさないよう両方見る。
        let decoded = p;
        try {
          decoded = decodeURIComponent(p);
        } catch {
          /* 不正なエスケープはそのまま扱う */
        }
        return !p.includes("/404") && !noindex.has(p) && !noindex.has(decoded);
      },
    }),
  ],
  vite: { build: { assetsInlineLimit: 0 } },
});
