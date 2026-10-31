// @ts-check
/**
 * 変えたところに関係するシナリオだけを回す (`npm run e2e:changed`)。
 *
 * 1. 台帳の突き合わせ (ledger.mjs) を先に通す。落ちたらブラウザは起こさない。
 * 2. `git diff <基点>` (既定 origin/develop との merge-base + 作業中の変更) で変わった
 *    web/ のファイルを集める。
 * 3. 母集団のキー (route / island / op) がそのファイルを指していれば、そのキーを
 *    covers に持つシナリオを回す。変えた spec ファイルはそのまま回す。
 * 4. どのキーにも結び付かない web/src の変更 (共通の部品・CSS・lib・レイアウト) や
 *    フィクスチャ・設定の変更は、影響が読めないので全部回す。
 *
 *   node e2e/tools/changed.mjs [--base <ref>] [--dry-run] [-- <playwright への引数>]
 */
import { execFileSync, spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { checkLedger } from "./ledger.mjs";
import { fileOfTarget } from "./inventory.mjs";

const WEB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const argv = process.argv.slice(2);
const sep = argv.indexOf("--");
const own = sep === -1 ? argv : argv.slice(0, sep);
const passthrough = sep === -1 ? [] : argv.slice(sep + 1);
const baseArg = own.indexOf("--base");
const base = baseArg === -1 ? "origin/develop" : own[baseArg + 1];
const dryRun = own.includes("--dry-run");

const git = (/** @type {string[]} */ args) => execFileSync("git", args, { cwd: WEB, encoding: "utf8" }).trim();

const ledger = checkLedger();
if (ledger.errors.length) {
  for (const e of ledger.errors) console.error(`✗ ${e}`);
  console.error("✗ 台帳の突き合わせが通らないので E2E は回しません (npm run e2e:ledger)");
  process.exit(1);
}

const top = git(["rev-parse", "--show-toplevel"]);
const mergeBase = git(["merge-base", "HEAD", /** @type {string} */ (base)]);
const changed = new Set(
  [
    ...git(["diff", "--name-only", mergeBase, "--", "."]).split("\n"),
    ...git(["ls-files", "--others", "--exclude-standard", "--", "."]).split("\n").map((f) => path.relative(top, path.join(WEB, f))),
  ]
    .filter(Boolean)
    .map((f) => path.relative(WEB, path.join(top, f)).split(path.sep).join("/"))
    .filter((f) => !f.startsWith("..")),
);

/** 母集団のキーが指すファイル → キー。 */
/** @type {Map<string, string[]>} */
const keysByFile = new Map();
for (const key of ledger.population) {
  const f = fileOfTarget(key);
  if (f) keysByFile.set(f, [...(keysByFile.get(f) ?? []), key]);
}

/** @type {Set<string>} */
const ids = new Set();
/** @type {string[]} */
const specs = [];
/** @type {string[]} */
const unmapped = [];
for (const f of changed) {
  if (f.startsWith("e2e/tests/") && f.endsWith(".spec.ts")) {
    specs.push(f);
  } else if (keysByFile.has(f)) {
    for (const key of keysByFile.get(f) ?? []) {
      for (const s of ledger.scenarios) if (s.status === "implemented" && s.covers.includes(key)) ids.add(s.id);
    }
  } else if (/^(src|data-fixture|public|scripts)\//.test(f) || /^(astro\.config\.mjs|playwright\.config\.ts|wrangler\.jsonc|package\.json)$/.test(f) || f.startsWith("e2e/support/")) {
    unmapped.push(f);
  }
}

/** @type {string[]} */
let args;
if (unmapped.length) {
  console.log(`影響が読めない変更があるので全部回します:\n${unmapped.map((f) => `  ${f}`).join("\n")}`);
  args = [];
} else if (ids.size === 0 && specs.length === 0) {
  console.log(`${base} から web/ の画面・操作に関わる変更はありません。E2E は回しません`);
  process.exit(0);
} else {
  console.log(`回すシナリオ: ${[...ids].sort().join(", ") || "(なし)"}${specs.length ? `\n回す spec: ${specs.join(", ")}` : ""}`);
  args = [...specs];
  if (ids.size) args.push("--grep", [...ids].map((id) => `@${id}\\b`).join("|"));
}

if (dryRun) {
  console.log(`npx playwright test ${[...args, ...passthrough].join(" ")}`);
  process.exit(0);
}

const build = spawnSync("npm", ["run", "build:fixture"], { cwd: WEB, stdio: "inherit" });
if (build.status !== 0) process.exit(build.status ?? 1);
const run = spawnSync("npx", ["playwright", "test", ...args, ...passthrough], { cwd: WEB, stdio: "inherit" });
process.exit(run.status ?? 1);
