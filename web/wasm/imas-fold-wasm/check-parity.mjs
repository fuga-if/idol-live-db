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
// wasm は web/src/lib/fold/ に wasm-pack が出したものを読む。
//
// Astro 側 (vitest) にも同じ突き合わせを置くが、こちらは npm に一切依存せず
// `node` だけで回るので、wasm を作り直した直後の確認に使える。

import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

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

const glue = resolve(webRoot, "src/lib/fold/imas_fold_wasm.js");
const wasmPath = resolve(webRoot, "src/lib/fold/imas_fold_wasm_bg.wasm");
if (!existsSync(glue) || !existsSync(wasmPath)) {
  console.error(
    "wasm がまだ無い。web/wasm/imas-fold-wasm で以下を実行すること:\n" +
      "  wasm-pack build --release --target web --out-dir ../../src/lib/fold",
  );
  process.exit(2);
}

// --target web の既定は fetch(new URL(..., import.meta.url)) なので、
// Node では .wasm のバイト列を直接渡す。
const { default: init, fold } = await import(glue);
await init({ module_or_path: await readFile(wasmPath) });

const { schemaVersion, cases } = JSON.parse(await readFile(fixturePath, "utf8"));
if (schemaVersion !== 1) {
  console.error(`知らない schemaVersion: ${schemaVersion}`);
  process.exit(2);
}

const failures = [];
for (const { in: input, out: expected } of cases) {
  const actual = fold(input);
  if (actual !== expected) failures.push({ input, expected, actual });
}

// 落ちる原因はたいてい目に見えない文字 (制御文字・結合する濁点) なので、必ずエスケープして出す。
const show = (s) =>
  JSON.stringify(s).replace(
    /[\u0000-\u001F\u0300-\u036F\u3099\u309A]/g,
    (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"),
  );

if (failures.length > 0) {
  console.error(`パリティ不一致 ${failures.length} / ${cases.length} 件:`);
  for (const f of failures.slice(0, 20)) {
    console.error(`  in=${show(f.input)}\n    rust=${show(f.expected)}\n    wasm=${show(f.actual)}`);
  }
  if (failures.length > 20) console.error(`  ... 他 ${failures.length - 20} 件`);
  process.exit(1);
}

console.log(`パリティ一致: ${cases.length} 件 (${fixturePath})`);
