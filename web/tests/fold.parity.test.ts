/**
 * 畳み込みのパリティ検証。
 *
 * 検索の照合規則の唯一の正は Rust の `imas-text-fold` で、ブラウザ側はその wasm を使う
 * (`src/lib/search/fold.ts`)。**このテストは「ブラウザで使う実体が Rust と一致するか」の検収**で、
 * Rust の bin が出したフィクスチャ (`parity/fold.json`: 入力 → 畳み後) を全件流して突き合わせる。
 *
 * wasm がまだ生成されていない環境 (`npm run wasm` 前) では、パリティを取りようがないので
 * **skip ではなく明示的に失敗させる**。「テストが緑だから検索も正しい」という誤解を作らないため。
 */
import { describe, expect, it, beforeAll } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { pathToFileURL } from "node:url";
import type { FoldParity } from "../src/lib/schema/FoldParity";

const DATA = path.resolve(process.env.IMAS_WEB_DATA ?? "./data");
const PARITY = path.join(DATA, "parity/fold.json");
const FOLD_MODULE = path.resolve("./public/fold/imas_fold_wasm.js");

type Fold = (text: string) => string;

let fold: Fold;

beforeAll(async () => {
  expect(
    fs.existsSync(FOLD_MODULE),
    `${FOLD_MODULE} がありません。先に \`npm run wasm\` を実行してください ` +
      "(検索の畳み込みは imas-text-fold の wasm が実体です)。",
  ).toBe(true);
  const mod = (await import(pathToFileURL(FOLD_MODULE).href)) as {
    default: () => Promise<unknown>;
    fold: Fold;
  };
  await mod.default();
  fold = mod.fold;
});

describe("fold のパリティ (Rust ↔ ブラウザ)", () => {
  const parity = JSON.parse(fs.readFileSync(PARITY, "utf8")) as FoldParity;

  it("フィクスチャが空でない", () => {
    expect(parity.cases.length).toBeGreaterThan(0);
  });

  it("全ケースで Rust の畳み結果と一致する", () => {
    const mismatches = parity.cases
      .map((c) => ({ ...c, got: fold(c.in) }))
      .filter((c) => c.got !== c.out);
    expect(mismatches, `不一致 ${mismatches.length} 件 / 全 ${parity.cases.length} 件`).toEqual([]);
  });

  it("畳み込みは冪等 (畳んだものをもう一度畳んでも変わらない)", () => {
    const unstable = parity.cases.filter((c) => fold(c.out) !== c.out);
    expect(unstable).toEqual([]);
  });
});
