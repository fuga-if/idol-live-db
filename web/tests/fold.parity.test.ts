/**
 * 畳み込みのパリティ検証。
 *
 * 検索の照合規則の唯一の正は Rust の `imas-text-fold` で、ブラウザ側はその wasm を使う
 * (`src/lib/search/fold.ts`)。**このテストは「ブラウザで使う実体が Rust と一致するか」の検収**で、
 * Rust の bin が出したフィクスチャ (`parity/fold.json`: 入力 → 畳み後) を全件流して突き合わせる。
 *
 * 突き合わせの本体は `wasm/imas-fold-wasm/parity.mjs` で、CLI (`check-parity.mjs`) と共有する。
 * 検査を 2 回書くと、片方だけ厳しい/緩いという事態が起き得るため。
 *
 * wasm がまだ生成されていない環境 (`npm run wasm` 前) では、パリティを取りようがないので
 * **skip ではなく明示的に失敗させる**。「テストが緑だから検索も正しい」という誤解を作らないため。
 */
import { describe, expect, it, beforeAll } from "vitest";
import path from "node:path";
import {
  MISSING_WASM_HINT,
  formatMismatches,
  loadFold,
  mismatches,
  readCases,
  wasmExists,
} from "../wasm/imas-fold-wasm/parity.mjs";
import { dataRoot } from "../scripts/data-root.mjs";
import type { FoldCase } from "../src/lib/schema/FoldCase";

const PARITY = path.join(dataRoot(), "parity/fold.json");

type Fold = (text: string) => string;

let fold: Fold;
let cases: FoldCase[];

beforeAll(async () => {
  expect(wasmExists(), MISSING_WASM_HINT).toBe(true);
  fold = await loadFold();
  cases = await readCases(PARITY);
});

describe("fold のパリティ (Rust ↔ ブラウザ)", () => {
  it("フィクスチャが空でない", () => {
    expect(cases.length).toBeGreaterThan(0);
  });

  it("全ケースで Rust の畳み結果と一致する", () => {
    const failures = mismatches(fold, cases);
    expect(failures.length, failures.length > 0 ? formatMismatches(failures, cases.length) : "").toBe(
      0,
    );
  });

  it("畳み込みは冪等 (畳んだものをもう一度畳んでも変わらない)", () => {
    const unstable = cases.filter((c) => fold(c.out) !== c.out);
    expect(unstable).toEqual([]);
  });
});
