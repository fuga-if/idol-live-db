// @ts-check
/**
 * テストコードからシナリオ id を読む。
 *
 * `test("…", { tag: "@SEARCH-001" }, …)` と `test.describe("…", { tag: [...] }, …)` の
 * tag に書いた `@AREA-001` の形だけを拾う。describe に付けた id は中のテスト全部に掛かる。
 * TypeScript の構文木で読むので、コメントや文字列の中の `@AREA-001` は拾わない。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const WEB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const TEST_DIR = "e2e/tests";
export const SCENARIO_TAG = /^@([A-Z]+-\d{3})$/;

/** @param {string} dir @returns {string[]} */
function specs(dir) {
  /** @type {string[]} */
  const out = [];
  for (const ent of fs.readdirSync(path.join(WEB, dir), { withFileTypes: true })) {
    const rel = `${dir}/${ent.name}`;
    if (ent.isDirectory()) out.push(...specs(rel));
    else if (ent.name.endsWith(".spec.ts")) out.push(rel);
  }
  return out.sort();
}

/** `test(...)` / `test.describe(...)` / `test.skip(...)` などの呼び出しか。 */
function isTestCall(/** @type {ts.CallExpression} */ call) {
  const e = call.expression;
  if (ts.isIdentifier(e)) return e.text === "test";
  return ts.isPropertyAccessExpression(e) && ts.isIdentifier(e.expression) && e.expression.text === "test";
}

/** @returns {{ tests: { file: string, where: string, ids: string[] }[], errors: string[] }} */
export function collectTestIds() {
  /** @type {{ file: string, where: string, ids: string[] }[]} */
  const tests = [];
  /** @type {string[]} */
  const errors = [];
  for (const file of specs(TEST_DIR)) {
    const sf = ts.createSourceFile(file, fs.readFileSync(path.join(WEB, file), "utf8"), ts.ScriptTarget.Latest, true);
    /** @param {ts.Node} node */
    const visit = (node) => {
      if (ts.isCallExpression(node) && isTestCall(node)) {
        const opts = node.arguments.find(ts.isObjectLiteralExpression);
        const tag = opts?.properties.find(
          (p) => ts.isPropertyAssignment(p) && p.name.getText() === "tag",
        );
        if (tag && ts.isPropertyAssignment(tag)) {
          const values = ts.isArrayLiteralExpression(tag.initializer) ? [...tag.initializer.elements] : [tag.initializer];
          /** @type {string[]} */
          const ids = [];
          for (const v of values) {
            const { line } = sf.getLineAndCharacterOfPosition(v.getStart());
            if (!ts.isStringLiteralLike(v)) {
              errors.push(`${file}:${line + 1} の tag は文字列リテラルで書く (台帳と機械的に突き合わせるため)`);
              continue;
            }
            const m = SCENARIO_TAG.exec(v.text);
            if (m?.[1]) ids.push(m[1]);
          }
          if (ids.length) {
            const { line } = sf.getLineAndCharacterOfPosition(node.getStart());
            tests.push({ file, where: `${file}:${line + 1}`, ids });
          }
        }
      }
      ts.forEachChild(node, visit);
    };
    visit(sf);
  }
  return { tests, errors };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  console.log(JSON.stringify(collectTestIds(), null, 2));
}
