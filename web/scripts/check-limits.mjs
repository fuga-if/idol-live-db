#!/usr/bin/env node
// `npm run build` の最後 (astro build の直後) に dist/ を走査し、
// Cloudflare Workers Static Assets の上限に接近/超過していないかを確認する。
//
// 実際の上限: 20,000 ファイル / 1 ファイル 25 MiB (docs/ARCHITECTURE-web.md §10)。
// ここでは早めに気付けるよう安全マージンを取った閾値で判定する:
//   - ファイル数 > 18,000        → exit 1 (上限 20,000 の 90%)
//   - 単一ファイル > 20 MiB      → exit 1 (上限 25 MiB の 80%)
//   - 総サイズ                   → 警告のみ (Cloudflare 側の総サイズ上限に確立した数値が
//                                   無いため exit 1 にはしない。リーダー決定 DECISIONS.md C4)
// 1 ページの重さ (HTML 1 枚が圧縮後 1 MiB 未満) も見る。規則は page-weight.mjs。
import fs from "node:fs";
import path from "node:path";
import { walk } from "./walk.mjs";
import { MAX_PAGE_COMPRESSED_BYTES, measurePages } from "./page-weight.mjs";

const DIST = path.resolve("./dist");
const MAX_FILES = 18_000;
const MAX_FILE_BYTES = 20 * 1024 * 1024; // 20 MiB
const WARN_TOTAL_BYTES = 400 * 1024 * 1024; // 400 MiB (参考値。超えても失敗させない)

// ビルドパイプラインの複数ステップ (Rust の web-export / web-coder の copy フック /
// Astro の integrations) がそれぞれ書き出すファイル。1 つでも欠けると「一見ビルドは
// 成功したがサイトの一部機能が死んでいる」事故になる (例: themes.css が無いと全ページが
// 無彩色のまま無言で成功する)。ここで存在だけを機械的に確認する (中身の妥当性は見ない)。
const REQUIRED_FILES = [
  "themes.css", // imas-core が出すテーマトークン (web/data/themes.css → dist へコピー)
  "search/manifest.json", // 検索シャードの一覧 (/search/ island の起動に必須)
  "sitemap-index.xml", // @astrojs/sitemap の出力
  "robots.txt",
  "404.html",
  "_headers", // CSP / キャッシュ / X-Robots-Tag (astro.config の write-headers が scripts/headers.mjs で組む)
];

if (!fs.existsSync(DIST)) {
  console.error(`[check-limits] dist/ が無い: ${DIST} (先に astro build を実行)`);
  process.exit(1);
}

const missingRequired = REQUIRED_FILES.filter((rel) => !fs.existsSync(path.join(DIST, rel)));
if (missingRequired.length > 0) {
  console.error(`[check-limits] 必須ファイルが無い (ビルドの一部が無言で欠落している可能性):`);
  for (const rel of missingRequired) {
    console.error(`  - ${rel}`);
  }
  process.exit(1);
}

/** @type {{path: string, size: number}[]} */
const files = walk(DIST).map((full) => ({ path: full, size: fs.statSync(full).size }));

const totalBytes = files.reduce((sum, f) => sum + f.size, 0);
const largest = files.reduce((max, f) => (f.size > max.size ? f : max), { path: "(none)", size: 0 });

const fmtMB = (bytes) => (bytes / (1024 * 1024)).toFixed(1);

console.log(
  `[check-limits] files=${files.length} totalBytes=${totalBytes} (${fmtMB(totalBytes)}MB) ` +
    `largestFile=${path.relative(DIST, largest.path)} (${fmtMB(largest.size)}MB)`,
);

let failed = false;

if (files.length > MAX_FILES) {
  console.error(
    `[check-limits] ファイル数が上限に接近: ${files.length} > ${MAX_FILES} (Cloudflare 上限 20,000)`,
  );
  failed = true;
}

const oversized = files.filter((f) => f.size > MAX_FILE_BYTES);
if (oversized.length > 0) {
  console.error(`[check-limits] 20MiB を超えるファイルが ${oversized.length} 件 (Cloudflare 上限 25MiB):`);
  for (const f of oversized.slice(0, 10)) {
    console.error(`  - ${path.relative(DIST, f.path)} (${fmtMB(f.size)}MB)`);
  }
  failed = true;
}

// 閲覧者が受け取る大きさ (圧縮後) で 1 ページの重さを見る。
const pages = measurePages(files.filter((f) => f.path.endsWith(".html")).map((f) => f.path));
console.log(
  `[check-limits] heaviestPage=${path.relative(DIST, pages.largest.file)} ` +
    `(gzip ${(pages.largest.bytes / 1024).toFixed(0)}KiB / 上限 ${MAX_PAGE_COMPRESSED_BYTES / 1024}KiB)`,
);
if (pages.over.length > 0) {
  console.error(`[check-limits] 圧縮後 1MiB を超えるページが ${pages.over.length} 件:`);
  for (const p of pages.over.slice(0, 10)) {
    console.error(`  - ${path.relative(DIST, p.file)} (gzip ${fmtMB(p.bytes)}MB)`);
  }
  failed = true;
}

if (totalBytes > WARN_TOTAL_BYTES) {
  console.warn(
    `[check-limits] 警告: 総サイズが目安 (${fmtMB(WARN_TOTAL_BYTES)}MB) を超過: ${fmtMB(totalBytes)}MB。` +
      " Cloudflare 側の総サイズ上限に確立した数値が無いため失敗にはしないが、デプロイ時間の増加に注意。",
  );
}

if (failed) {
  process.exit(1);
}

console.log("[check-limits] OK");
