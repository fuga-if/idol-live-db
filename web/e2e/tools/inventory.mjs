// @ts-check
/**
 * E2E の「母集団」= 画面と操作の一覧を、ソースから機械的に作る。
 *
 * 人が「どこをテストすべきか」を思い出すのではなく、ここが拾ったものすべてに
 * シナリオ台帳 (ledger/scenarios/*.json) の covers が当たっているかを
 * ledger.mjs が突き合わせる。新しいページや操作を書けば、ここが勝手に拾って
 * 「シナリオが無い」で落ちる。
 *
 * 拾うもの (3 種類):
 *   route:<URL の形>          src/pages/** の 1 ファイル = 1 URL 種別。例 `route:/songs/[songId]/`
 *   island:<ファイル>         ブラウザで動く JS を持つ .astro (`<script>` のあるもの)
 *   op:<ファイル>#<関数>/<受け手>:<イベント>
 *                             addEventListener の呼び出し 1 つ = 操作 1 つ
 *                             例 `op:src/lib/search/island.ts#init/input:input`
 *
 * 決まりごと:
 *   - 読めないもの (イベント名が文字列リテラルでも配列リテラルでもない等) は errors に入れ、
 *     黙って捨てない。errors が 1 件でもあれば終了コード 1。
 *   - 生成物 (src/lib/schema, src/lib/fold, src/lib/query) と型定義は母集団に入れない。
 *   - JSON-LD 用の `<script type="application/ld+json">` は JS ではないので island にしない。
 *
 * 使い方:
 *   node e2e/tools/inventory.mjs           一覧を標準出力へ
 *   node e2e/tools/inventory.mjs --write   e2e/ledger/inventory.generated.json を書き換える
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

const WEB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
export const INVENTORY_FILE = path.join(WEB, "e2e/ledger/inventory.generated.json");

const EXCLUDE_DIRS = ["src/lib/schema", "src/lib/fold", "src/lib/query"];

/** @param {string} dir @returns {string[]} web/ からの相対パス (区切りは /) */
function walk(dir) {
  /** @type {string[]} */
  const out = [];
  for (const ent of fs.readdirSync(path.join(WEB, dir), { withFileTypes: true })) {
    const rel = `${dir}/${ent.name}`;
    if (ent.isDirectory()) {
      if (!EXCLUDE_DIRS.includes(rel)) out.push(...walk(rel));
    } else if (/\.(astro|ts|mjs|js)$/.test(ent.name) && !ent.name.endsWith(".d.ts")) {
      out.push(rel);
    }
  }
  return out.sort();
}

/** `src/pages/songs/[songId].astro` → `/songs/[songId]/` */
function routeOf(/** @type {string} */ file) {
  let p = file.replace(/^src\/pages/, "").replace(/\.astro$/, "");
  p = p.replace(/\/index$/, "/");
  if (p === "/404") return "/404";
  return p.endsWith("/") ? p : `${p}/`;
}

/** .astro の中のブラウザ用 `<script>` (JSON-LD 等を除く) の本文。 */
function clientScripts(/** @type {string} */ text) {
  /** @type {string[]} */
  const out = [];
  for (const m of text.matchAll(/<script(\s[^>]*)?>([\s\S]*?)<\/script>/g)) {
    const attrs = m[1] ?? "";
    if (/type\s*=\s*["'](?!module)/.test(attrs) || /is:inline/.test(attrs)) continue;
    out.push(m[2] ?? "");
  }
  return out;
}

/** 呼び出しを囲む、名前の付いた一番内側の関数。無ければ `<top>`。 */
function enclosingName(/** @type {ts.Node} */ node) {
  for (let n = node.parent; n; n = n.parent) {
    if ((ts.isFunctionDeclaration(n) || ts.isMethodDeclaration(n)) && n.name) return n.name.getText();
    if ((ts.isArrowFunction(n) || ts.isFunctionExpression(n)) && ts.isVariableDeclaration(n.parent)) {
      return n.parent.name.getText();
    }
  }
  return "<top>";
}

/**
 * addEventListener の呼び出しを拾う。
 * @param {string} file
 * @param {string} code
 * @param {string[]} errors
 * @returns {string[]}
 */
function opsIn(file, code, errors) {
  const sf = ts.createSourceFile(file, code, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
  /** @type {string[]} */
  const keys = [];
  /** @param {ts.Node} node */
  const visit = (node) => {
    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === "addEventListener"
    ) {
      const receiver = node.expression.expression.getText().replace(/\s+/g, "").replace(/\?$/, "");
      const where = `${enclosingName(node)}/${receiver}`;
      const arg = node.arguments[0];
      /** @type {string[]} */
      let events = [];
      if (arg && ts.isStringLiteralLike(arg)) {
        events = [arg.text];
      } else if (arg && ts.isIdentifier(arg)) {
        // `for (const type of ["copy", "cut"]) x.addEventListener(type, ...)` の形だけ読める。
        events = loopLiterals(node, arg.text) ?? [];
      } else if (arg && ts.isConditionalExpression(arg)) {
        const a = arg.whenTrue;
        const b = arg.whenFalse;
        if (ts.isStringLiteralLike(a) && ts.isStringLiteralLike(b)) events = [a.text, b.text];
      }
      if (events.length === 0) {
        const { line } = sf.getLineAndCharacterOfPosition(node.getStart());
        errors.push(`${file}:${line + 1} のイベント名が読めない (文字列リテラルで書くこと): ${node.getText().slice(0, 80)}`);
      }
      for (const ev of events) keys.push(`op:${file}#${where}:${ev}`);
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return keys;
}

/** `for (const <name> of [ "a", "b" ])` の中なら ["a", "b"]。 */
function loopLiterals(/** @type {ts.Node} */ node, /** @type {string} */ name) {
  for (let n = node.parent; n; n = n.parent) {
    if (ts.isForOfStatement(n) && ts.isVariableDeclarationList(n.initializer)) {
      const decl = n.initializer.declarations[0];
      if (decl && decl.name.getText() === name && ts.isArrayLiteralExpression(n.expression)) {
        const items = n.expression.elements;
        if (items.every((e) => ts.isStringLiteralLike(e))) return items.map((e) => /** @type {ts.StringLiteral} */ (e).text);
      }
      return null;
    }
  }
  return null;
}

/** @returns {{ targets: string[], errors: string[] }} */
export function extractInventory() {
  /** @type {string[]} */
  const errors = [];
  /** @type {Set<string>} */
  const targets = new Set();
  for (const file of walk("src")) {
    const text = fs.readFileSync(path.join(WEB, file), "utf8");
    if (file.startsWith("src/pages/") && file.endsWith(".astro")) targets.add(`route:${routeOf(file)}`);
    /** @type {string[]} */
    let ops = [];
    if (file.endsWith(".astro")) {
      const scripts = clientScripts(text);
      if (scripts.length > 0) targets.add(`island:${file}`);
      for (const s of scripts) ops.push(...opsIn(file, s, errors));
    } else {
      ops = opsIn(file, text, errors);
    }
    // 同じ関数・同じ受け手・同じイベントが 2 回あれば #2, #3 … を付ける。
    /** @type {Map<string, number>} */
    const seen = new Map();
    for (const k of ops) {
      const n = (seen.get(k) ?? 0) + 1;
      seen.set(k, n);
      targets.add(n === 1 ? k : `${k}#${n}`);
    }
  }
  return { targets: [...targets].sort(), errors };
}

/** 母集団のキーが指すソースファイル (web/ からの相対)。 */
export function fileOfTarget(/** @type {string} */ key) {
  if (key.startsWith("route:")) {
    const r = key.slice("route:".length);
    for (const f of walk("src/pages")) if (f.endsWith(".astro") && routeOf(f) === r) return f;
    return null;
  }
  const rest = key.replace(/^(island|op):/, "");
  return rest.split("#")[0] ?? null;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const result = extractInventory();
  for (const e of result.errors) console.error(`✗ ${e}`);
  if (process.argv.includes("--write")) {
    fs.writeFileSync(INVENTORY_FILE, `${JSON.stringify({ targets: result.targets }, null, 2)}\n`);
    console.log(`${path.relative(WEB, INVENTORY_FILE)} を書きました (${result.targets.length} 件)`);
  } else {
    console.log(JSON.stringify(result, null, 2));
  }
  process.exitCode = result.errors.length === 0 ? 0 : 1;
}
