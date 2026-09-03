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
import fs from "node:fs";
import path from "node:path";

const DIST = path.resolve("./dist");
const MAX_FILES = 18_000;
const MAX_FILE_BYTES = 20 * 1024 * 1024; // 20 MiB
const WARN_TOTAL_BYTES = 400 * 1024 * 1024; // 400 MiB (参考値。超えても失敗させない)

if (!fs.existsSync(DIST)) {
  console.error(`[check-limits] dist/ が無い: ${DIST} (先に astro build を実行)`);
  process.exit(1);
}

/** @type {{path: string, size: number}[]} */
const files = [];

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.isFile()) {
      files.push({ path: full, size: fs.statSync(full).size });
    }
  }
}
walk(DIST);

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
