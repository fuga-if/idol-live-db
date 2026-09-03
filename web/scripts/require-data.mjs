#!/usr/bin/env node
// astro build の直前 (npm run prebuild) に走る門番。
//
// web/data/ (web-export bin の出力) が無いまま `astro build` へ進むと、
// getStaticPaths が空データで「0 ページ」を静かにビルドしてしまう。
// ここで存在確認と schemaVersion 検査を行い、無ければ即座に失敗させる。
//
// データ入力元は IMAS_WEB_DATA (未設定なら ./data)。src/lib/data.ts の
// ROOT 解決と同じ規則 (npm run dev:fixture の ./data-fixture 切替も同じ経路)。
import fs from "node:fs";
import path from "node:path";

const SCHEMA_VERSION = 1;

const root = path.resolve(process.env.IMAS_WEB_DATA ?? "./data");
const metaPath = path.join(root, "meta.json");

function fail(message) {
  console.error(`[require-data] ${message}`);
  console.error(`[require-data] IMAS_WEB_DATA=${process.env.IMAS_WEB_DATA ?? "(未設定)"} / 参照先: ${root}`);
  console.error(
    "[require-data] 実データが要る場合は `npm run export` (imas-core の web-export bin を実行)。" +
      " フィクスチャで開発する場合は `npm run dev:fixture` を使ってください。",
  );
  process.exit(1);
}

if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) {
  fail(`データディレクトリが無い: ${root}`);
}

if (!fs.existsSync(metaPath)) {
  fail(`meta.json が無い: ${metaPath}`);
}

let meta;
try {
  meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
} catch (err) {
  fail(`meta.json の parse に失敗: ${err instanceof Error ? err.message : String(err)}`);
}

if (meta.schemaVersion !== SCHEMA_VERSION) {
  fail(
    `schemaVersion 不一致: meta.json は ${JSON.stringify(meta.schemaVersion)}、` +
      `require-data.mjs は ${SCHEMA_VERSION} を期待。imas-core (web-export) と web の型 (src/lib/schema) の版がずれています。`,
  );
}

console.log(
  `[require-data] OK: ${metaPath} (schemaVersion=${meta.schemaVersion}, todayJst=${meta.todayJst ?? "?"}, dataVersion=${meta.dataVersion ?? "?"})`,
);
