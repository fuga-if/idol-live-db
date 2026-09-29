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
import { readJson } from "../src/lib/data";
import type { FoldCase } from "../src/lib/schema/FoldCase";
import type { SearchManifest } from "../src/lib/schema/SearchManifest";
import type { SearchShard } from "../src/lib/schema/SearchShard";

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

/**
 * 索引の区切り (`sep`) が、本文のフィールドの境界と揃っていること。
 *
 * 島の照合は `row.f.includes(fold(q))` の 1 行で、フィールドをまたいで当たらない根拠は
 * 「区切りが本文に現れない」ことだけ。区切りが曲名などに混ざると、`split(sep)` が
 * フィールドの境界とずれる。ここでは実際にブラウザが使う fold (wasm) で見る:
 *   - 先頭のフィールドは、表示名 (`n`) を畳んだものと一致する (索引は名前から始まる)
 *   - 空のフィールドが無い (索引は空文字を載せない。区切りの重複や端の区切りも無い)
 *   - 表示名・補助表記に区切りが入っていない
 */
describe("検索索引の区切り (Rust ↔ ブラウザ)", () => {
  it("先頭のフィールドが表示名を畳んだものと一致し、空のフィールドが無い", () => {
    const manifest = readJson<SearchManifest>("search/manifest.json");
    const broken: string[] = [];
    let checked = 0;
    for (const meta of manifest.shards) {
      const shard = readJson<SearchShard>(meta.url.replace(/^\//, ""));
      for (const row of shard.rows) {
        if (row.n.includes(shard.sep) || (row.s ?? "").includes(shard.sep)) {
          broken.push(`${shard.kind}: 表示に区切りが入っている ${JSON.stringify(row.n)}`);
        }
        if (row.f === "") continue; // 名前も読みも空の行 (索引に載るものが無い)。
        const fields = row.f.split(shard.sep);
        if (fields.some((f) => f === "")) {
          broken.push(`${shard.kind}: 空のフィールドがある ${JSON.stringify(row.n)}`);
        }
        if (row.n !== "" && fields[0] !== fold(row.n)) {
          broken.push(`${shard.kind}: 先頭のフィールドが名前と違う ${JSON.stringify(row.n)}`);
        }
        checked += 1;
      }
    }
    expect(checked, "確かめた行が無い").toBeGreaterThan(0);
    expect(broken.slice(0, 20), `${broken.length} 件`).toEqual([]);
  });
});
