// web-export (Rust) の出力を読むときの共通の入口。
//
// データ根と schemaVersion は、Astro のページ・prebuild の門番・vitest・
// パリティ検査の 4 経路すべてが同じものを見る必要がある。以前は 7 箇所が
// `path.resolve(process.env.IMAS_WEB_DATA ?? "./data")` と `const SCHEMA_VERSION = 1`
// を写経していて、片方だけ直すと「dev では通るが build で落ちる」がすぐ作れた。
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

/**
 * JSON の互換性ゲート。
 *
 * Rust ⇄ Node の境界は跨げないので、正は imas-core の
 * `src/web_export/dto/common.rs` (SiteMeta.schema_version)。
 * スキーマを破壊的に変えるときは Rust とここの 2 箇所を同時に上げること
 * (ずれれば meta.json の検査で即座に気付ける)。
 */
export const SCHEMA_VERSION = 1;

/**
 * データ根。`IMAS_WEB_DATA` で差し替えられる
 * (`npm run dev:fixture` が ./data-fixture を指す)。
 */
export function dataRoot() {
  return path.resolve(process.env.IMAS_WEB_DATA ?? "./data");
}

const versionCache = new Map();

/**
 * データ根の下のファイルの中身から作る短い版 (sha256 の先頭 12 桁)。
 *
 * `/themes.css` や `/snapshot/tables.json` は名前が固定で、そのままでは長くキャッシュさせられない
 * (中身は日次の再ビルドで変わる)。URL に `?v=<版>` を付けて参照すれば、中身が変わったときだけ
 * URL が変わるので、配信側は長いキャッシュを付けられる (scripts/headers.mjs)。
 * ファイルが無ければ空文字 (呼ぶ側は `?v=` を付けない)。
 */
export function assetVersion(rel) {
  let v = versionCache.get(rel);
  if (v === undefined) {
    try {
      v = crypto.createHash("sha256").update(fs.readFileSync(path.join(dataRoot(), rel))).digest("hex").slice(0, 12);
    } catch {
      v = "";
    }
    versionCache.set(rel, v);
  }
  return v;
}

/** `assetVersion` を付けた URL。版が取れなければ素の URL。 */
export function versionedUrl(url, rel) {
  const v = assetVersion(rel);
  return v ? `${url}?v=${v}` : url;
}
