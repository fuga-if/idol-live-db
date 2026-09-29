// 畳み込みのパリティ突き合わせ本体。
//
// 「Rust が書き出した入力→畳み後の対応表を wasm に流して全件一致するか」は、
// CLI (check-parity.mjs) と vitest (web/tests/fold.parity.test.ts) の両方が要る。
// 検査そのものを 2 回書くと、片方だけ厳しい/緩いという事態が起き得るので 1 本にする。
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import { SCHEMA_VERSION } from "../../scripts/data-root.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const webRoot = resolve(here, "../..");

/** wasm-pack (`--target web`) が出す glue と .wasm の場所。 */
export const GLUE_PATH = resolve(webRoot, "src/lib/fold/imas_fold_wasm.js");
export const WASM_PATH = resolve(webRoot, "src/lib/fold/imas_fold_wasm_bg.wasm");

export const MISSING_WASM_HINT =
  "wasm がまだ無い。web/wasm/imas-fold-wasm で以下を実行すること:\n" +
  "  wasm-pack build --release --target web --out-dir ../../src/lib/fold";

/** wasm が生成済みか。 */
export const wasmExists = () => existsSync(GLUE_PATH) && existsSync(WASM_PATH);

/**
 * wasm を初期化して `fold` を返す。
 *
 * `--target web` の glue は既定で `fetch(new URL(...))` するので、
 * Node では .wasm のバイト列を直接渡す。
 * @returns {Promise<(text: string) => string>}
 */
export async function loadFold() {
  const mod = await import(GLUE_PATH);
  await mod.default({ module_or_path: await readFile(WASM_PATH) });
  return mod.fold;
}

/**
 * パリティフィクスチャ (`<data>/parity/fold.json`) を読む。
 * @param {string} fixturePath
 * @returns {Promise<{ in: string, out: string }[]>}
 */
export async function readCases(fixturePath) {
  const { schemaVersion, cases } = JSON.parse(await readFile(fixturePath, "utf8"));
  if (schemaVersion !== SCHEMA_VERSION) {
    throw new Error(`知らない schemaVersion: ${schemaVersion} (期待 ${SCHEMA_VERSION})`);
  }
  return cases;
}

/**
 * 目に見えない文字 (制御文字・結合する濁点) を \uXXXX に開く。
 * パリティが落ちる原因はたいていこれなので、報告は必ずこれを通す。
 */
const INVISIBLE = new RegExp("[\\u0000-\\u001F\\u0300-\\u036F\\u3099\\u309A]", "g");

/** @param {string} s */
export const show = (s) =>
  JSON.stringify(s).replace(INVISIBLE, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"));

/**
 * 全件を `fold` に流し、一致しなかったものを返す。
 * @param {(text: string) => string} fold
 * @param {{ in: string, out: string }[]} cases
 * @returns {{ input: string, expected: string, actual: string }[]}
 */
export function mismatches(fold, cases) {
  const failures = [];
  for (const { in: input, out: expected } of cases) {
    const actual = fold(input);
    if (actual !== expected) failures.push({ input, expected, actual });
  }
  return failures;
}

/**
 * 不一致を人間が読める形にする (CLI とテストの両方の報告文に使う)。
 * @param {{ input: string, expected: string, actual: string }[]} failures
 * @param {number} total
 */
export function formatMismatches(failures, total) {
  const head = `パリティ不一致 ${failures.length} / ${total} 件:`;
  const lines = failures
    .slice(0, 20)
    .map((f) => `  in=${show(f.input)}\n    rust=${show(f.expected)}\n    wasm=${show(f.actual)}`);
  if (failures.length > 20) lines.push(`  ... 他 ${failures.length - 20} 件`);
  return [head, ...lines].join("\n");
}
