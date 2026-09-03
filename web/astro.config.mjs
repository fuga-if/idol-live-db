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

export default defineConfig({
  site: "https://imas-live-web.tokata3011.workers.dev",
  output: "static",
  trailingSlash: "always",
  // CSP (public/_headers) が `style-src 'self'` = unsafe-inline 無しなので、
  // CSS は必ず外部ファイルにする ("auto" だと小さい CSS が <style> に入って全ページで死ぬ)。
  build: { format: "directory", inlineStylesheets: "never" },
  compressHTML: true,
  integrations: [
    sitemap({
      filter: (page) => {
        const p = new URL(page).pathname;
        return !p.includes("/404") && !noindex.has(p);
      },
    }),
  ],
  vite: { build: { assetsInlineLimit: 0 } },
});
