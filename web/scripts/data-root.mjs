// web-export (Rust) の出力を読むときの共通の入口。
//
// データ根と schemaVersion は、Astro のページ・prebuild の門番・vitest・
// パリティ検査の 4 経路すべてが同じものを見る必要がある。以前は 7 箇所が
// `path.resolve(process.env.IMAS_WEB_DATA ?? "./data")` と `const SCHEMA_VERSION = 1`
// を写経していて、片方だけ直すと「dev では通るが build で落ちる」がすぐ作れた。
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
