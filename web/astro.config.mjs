// @ts-check
import fs from "node:fs";
import path from "node:path";
import { defineConfig } from "astro/config";
import sitemap from "@astrojs/sitemap";
import { dataRoot } from "./scripts/data-root.mjs";

/**
 * sitemap のための routes.json の索引。
 *
 * ここで作るのは「decode 済みパス → routes.json の正規パス」の対応表 1 つだけで、
 * URL の組み立て規則も index / noindex の判断も持たない (どちらも Rust が決めている)。
 *
 * なぜ引き当てが要るか:
 *  - Astro が sitemap に出す `loc` は `@` を percent-encode せず生で書く。
 *    `share_text.rs` に「SNS が `@` で URL を切ってしまい 404 になった」実害の記録があり、
 *    配信物に 2 通りの綴りを出したくない。**正は routes.json の `path`** なので、
 *    `serialize` でそこに引き当てて書き戻す。
 *  - noindex の判定も同じ対応表を使う (綴りの揺れで取りこぼす余地を無くす)。
 *
 * ※ web/data が無い状態 (npm run check だけ回すとき) でも config が壊れないようにする。
 */
function routeIndex() {
  const empty = { canonical: /** @type {Map<string, string>} */ (new Map()), noindex: new Set() };
  const file = path.join(dataRoot(), "routes.json");
  if (!fs.existsSync(file)) return empty;
  try {
    const routes = JSON.parse(fs.readFileSync(file, "utf8"));
    const canonical = new Map();
    for (const r of routes.routes ?? []) canonical.set(decodePath(r.path), r.path);
    const noindex = new Set();
    for (const p of routes.noindexPaths ?? []) noindex.add(decodePath(p));
    return { canonical, noindex };
  } catch {
    return empty;
  }
}

/** 綴りの揺れを吸収するための鍵。decode できない綴りはそのまま鍵にする。 */
function decodePath(/** @type {string} */ p) {
  try {
    return decodeURIComponent(p);
  } catch {
    return p;
  }
}

/** @type {ReturnType<typeof routeIndex> | null} */
let routesCache = null;
/**
 * sitemap を実際に書き出すときまで routes.json を読まない。
 * config はページを 1 枚も作らないコマンド (astro check / astro info) でも読まれ、
 * そこで data/ を要求すると「型検査したいだけなのに export が要る」になる。
 */
const routes = () => (routesCache ??= routeIndex());

/**
 * Rust が出した配信物 (検索索引と themes.css) を `dist/` へ写す。
 *
 * `web/data/` は public/ の外に置いてある (詳細ページ 7,600 個を dist に出さないため) ので、
 * 配信が要るファイルだけをここで運ぶ。検索索引は `dist/search/` に置く
 * (`/search/` の index.html と同じディレクトリに同居できる)。
 */
function copyGeneratedAssets() {
  return {
    name: "imas:copy-generated-assets",
    hooks: {
      /** @param {{ dir: URL, logger: { info: (m: string) => void, warn: (m: string) => void } }} ctx */
      "astro:build:done": ({ dir, logger }) => {
        const root = dataRoot();

        // テーマ (エンティティ色の CSS 変数)。無いと全ページが neutral 表示になる。
        const themes = path.join(root, "themes.css");
        if (fs.existsSync(themes)) {
          fs.copyFileSync(themes, new URL("themes.css", dir));
          logger.info(`themes.css を配置しました (${fs.statSync(themes).size} B)`);
        } else {
          logger.warn(`${themes} がありません (色が neutral のままになります)`);
        }

        // 検索索引。
        const src = path.join(root, "search");
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

        // 一覧の絞り込み素材。一覧 HTML とは別ファイルにしてあり、絞り込みを
        // 開いた人だけが取りに行く (HTML の重さを増やさないため)。
        const idx = path.join(root, "index");
        const fdest = new URL("filters/", dir);
        fs.mkdirSync(fdest, { recursive: true });
        let m = 0;
        for (const name of fs.readdirSync(idx)) {
          if (!name.endsWith("-filter.json")) continue;
          fs.copyFileSync(path.join(idx, name), new URL(name, fdest));
          m += 1;
        }
        logger.info(`絞り込み素材 ${m} ファイルを dist/filters/ に配置しました`);
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
    copyGeneratedAssets(),
    sitemap({
      filter: (page) =>
        !page.includes("/404") && !routes().noindex.has(decodePath(new URL(page).pathname)),
      // `loc` を routes.json の綴りに揃える (Astro は `@` を生で出すため)。
      serialize: (item) => {
        const url = new URL(item.url);
        const canonical = routes().canonical.get(decodePath(url.pathname));
        if (canonical) item.url = new URL(canonical, url.origin).href;
        return item;
      },
    }),
  ],
  vite: { build: { assetsInlineLimit: 0 } },
});
