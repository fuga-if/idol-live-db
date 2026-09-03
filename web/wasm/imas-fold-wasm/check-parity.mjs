#!/usr/bin/env node
// wasm 版の fold が、Rust が書き出したパリティフィクスチャと 1 件残らず一致するかを見る。
//
// ここが緑でないと「検索欄では当たるのに一覧に出ない」(あるいはその逆) が起きる。
// 索引側 (haystack) は Rust が畳んで JSON に載せてあり、検索語側 (needle) だけが
// ブラウザで畳まれるので、両側が同じ規則を通っていることを確かめる必要がある。
//
//   node check-parity.mjs [fold.json のパス]
//
// 既定は web/data/parity/fold.json、無ければ web/data-fixture/parity/fold.json。
// 検査の本体は parity.mjs (vitest の tests/fold.parity.test.ts と共有)。
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  MISSING_WASM_HINT,
  formatMismatches,
  loadFold,
  mismatches,
  readCases,
  wasmExists,
} from "./parity.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, "../..");

const candidates = [
  process.argv[2],
  resolve(webRoot, "data/parity/fold.json"),
  resolve(webRoot, "data-fixture/parity/fold.json"),
].filter(Boolean);

const fixturePath = candidates.find((p) => existsSync(p));
if (!fixturePath) {
  console.error(
    `パリティフィクスチャが無い。探した場所:\n  ${candidates.join("\n  ")}\n` +
      "先に web-export を回すこと " +
      "(cargo run --features web-export --bin web-export -- --sql ../db/master.sql --out ../web/data)",
  );
  process.exit(2);
}

if (!wasmExists()) {
  console.error(MISSING_WASM_HINT);
  process.exit(2);
}

let cases;
try {
  cases = await readCases(fixturePath);
} catch (err) {
  console.error(err instanceof Error ? err.message : String(err));
  process.exit(2);
}

const failures = mismatches(await loadFold(), cases);
if (failures.length > 0) {
  console.error(formatMismatches(failures, cases.length));
  process.exit(1);
}

console.log(`パリティ一致: ${cases.length} 件 (${fixturePath})`);
