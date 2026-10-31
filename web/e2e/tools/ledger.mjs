// @ts-check
/**
 * シナリオ台帳の突き合わせ。ブラウザは使わない (数秒で終わる)。
 *
 * 3 つを突き合わせる:
 *   母集団   ソースから機械的に作った画面・操作の一覧 (inventory.mjs)
 *   台帳     e2e/ledger/scenarios/*.json (人と AI が書く。何を確かめるかの正)
 *   テスト   e2e/tests/**\/*.spec.ts の `tag: "@AREA-001"`
 *
 * 落とす条件:
 *   1. 母集団が inventory.generated.json と違う          → `npm run e2e:inventory` で更新してコミット
 *   2. 母集団を読めなかった箇所がある (inventory の errors)
 *   3. どのシナリオの covers にも入っていない画面・操作がある (= 新しく足したのにシナリオが無い)
 *   4. covers が母集団に無いキーを指している (消した・名前が変わった)
 *   5. シナリオの形が崩れている (id の重複・書式、status、pending の理由が空)
 *   6. implemented なのにテストが無い / pending なのにテストがある
 *   7. テストのタグが台帳に無い id を指している
 *   8. pending が pending-baseline.json より増えた / 済んだのに baseline に残っている
 *
 * pending を増やすのは「やらない理由を書いて、差分でレビューに出す」ときだけ:
 *   node e2e/tools/ledger.mjs --accept-pending   baseline を今の pending に書き換える
 *
 * --json を付けると結果を JSON で出す (changed.mjs が使う)。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { extractInventory, INVENTORY_FILE } from "./inventory.mjs";
import { collectTestIds } from "./test-ids.mjs";

const WEB = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const SCENARIO_DIR = path.join(WEB, "e2e/ledger/scenarios");
const BASELINE_FILE = path.join(WEB, "e2e/ledger/pending-baseline.json");
const ID_PATTERN = /^[A-Z]+-\d{3}$/;
const STATUSES = ["implemented", "pending"];

/**
 * @typedef {{ id: string, title: string, status: string, pendingReason: string | null, covers: string[], file: string }} Scenario
 */

/** @returns {Scenario[]} */
export function loadScenarios() {
  /** @type {Scenario[]} */
  const out = [];
  for (const name of fs.readdirSync(SCENARIO_DIR).filter((n) => n.endsWith(".json")).sort()) {
    const doc = JSON.parse(fs.readFileSync(path.join(SCENARIO_DIR, name), "utf8"));
    for (const s of doc.scenarios ?? []) out.push({ ...s, file: name });
  }
  return out;
}

/** @param {string[]} a */
const sorted = (a) => [...a].sort();

export function checkLedger() {
  /** @type {string[]} */
  const errors = [];
  const inventory = extractInventory();
  const population = new Set(inventory.targets);

  // 1, 2. 母集団
  for (const e of inventory.errors) errors.push(`母集団を読めない: ${e}`);
  const committed = fs.existsSync(INVENTORY_FILE) ? JSON.parse(fs.readFileSync(INVENTORY_FILE, "utf8")).targets : [];
  const added = inventory.targets.filter((t) => !committed.includes(t));
  const removed = committed.filter((/** @type {string} */ t) => !population.has(t));
  if (added.length || removed.length) {
    errors.push(
      [
        "inventory.generated.json がソースと合っていない。`npm run e2e:inventory` で更新してコミットする。",
        ...added.map((t) => `  + ${t}`),
        ...removed.map((/** @type {string} */ t) => `  - ${t}`),
      ].join("\n"),
    );
  }

  // 5. シナリオの形
  const scenarios = loadScenarios();
  /** @type {Map<string, Scenario>} */
  const byId = new Map();
  for (const s of scenarios) {
    if (!ID_PATTERN.test(s.id ?? "")) errors.push(`${s.file}: id「${s.id}」の書式が違う (AREA-001 の形)`);
    if (byId.has(s.id)) errors.push(`${s.file}: id ${s.id} が重複している (${byId.get(s.id)?.file} にもある)`);
    byId.set(s.id, s);
    if (!s.title?.trim()) errors.push(`${s.id}: title が空`);
    if (!STATUSES.includes(s.status)) errors.push(`${s.id}: status は ${STATUSES.join(" / ")} のどれか (今は「${s.status}」)`);
    if (s.status === "pending" && !s.pendingReason?.trim()) errors.push(`${s.id}: pending なのに pendingReason が空`);
    if (s.status === "implemented" && s.pendingReason) errors.push(`${s.id}: implemented なのに pendingReason が残っている`);
    if (!Array.isArray(s.covers) || s.covers.length === 0) errors.push(`${s.id}: covers が空 (何を確かめるシナリオか書く)`);
  }

  // 3, 4. 母集団と covers
  /** @type {Map<string, string[]>} */
  const coverIndex = new Map();
  for (const s of scenarios) {
    for (const key of s.covers ?? []) {
      if (!population.has(key)) errors.push(`シナリオ ${s.id} の covers「${key}」が母集団に無い。消したか名前が変わった`);
      coverIndex.set(key, [...(coverIndex.get(key) ?? []), s.id]);
    }
  }
  const uncovered = inventory.targets.filter((t) => !coverIndex.has(t));
  for (const t of uncovered) {
    errors.push(`「${t}」にシナリオが無い。e2e/ledger/scenarios/ のどこかの covers に入れる (新しいシナリオを足すか、既存のを広げる)`);
  }

  // 6, 7. テストとの突き合わせ
  const tests = collectTestIds();
  for (const e of tests.errors) errors.push(e);
  /** @type {Map<string, string[]>} */
  const testsById = new Map();
  for (const t of tests.tests) for (const id of t.ids) testsById.set(id, [...(testsById.get(id) ?? []), t.where]);
  for (const s of scenarios) {
    const has = testsById.has(s.id);
    if (s.status === "implemented" && !has) errors.push(`実装済みシナリオ ${s.id} に対応するテストが無い (tag: "@${s.id}" を付ける)`);
    if (s.status === "pending" && has) errors.push(`pending のシナリオ ${s.id} にテストがある (${testsById.get(s.id)?.join(", ")})。implemented にする`);
  }
  for (const [id, where] of testsById) {
    if (!byId.has(id)) errors.push(`テストのタグ @${id} が台帳に無い (${where.join(", ")})`);
  }

  // 8. pending の baseline
  const pending = sorted(scenarios.filter((s) => s.status === "pending").map((s) => s.id));
  const baseline = fs.existsSync(BASELINE_FILE) ? JSON.parse(fs.readFileSync(BASELINE_FILE, "utf8")).pending : [];
  const newPending = pending.filter((id) => !baseline.includes(id));
  const resolved = baseline.filter((/** @type {string} */ id) => !pending.includes(id));
  if (newPending.length) {
    errors.push(
      `pending が増えた: ${newPending.join(", ")}。テストを書いて implemented にする。` +
        "どうしても後回しにするなら理由を書いて `npm run e2e:ledger -- --accept-pending` (baseline の差分がレビューに出る)",
    );
  }
  if (resolved.length) {
    errors.push(`pending ではなくなったのに baseline に残っている: ${resolved.join(", ")}。\`npm run e2e:ledger -- --accept-pending\` で外す`);
  }

  return {
    errors,
    scenarios,
    population: inventory.targets,
    pending,
    summary: {
      targets: inventory.targets.length,
      scenarios: scenarios.length,
      implemented: scenarios.filter((s) => s.status === "implemented").length,
      pending: pending.length,
    },
  };
}

export function writeBaseline(/** @type {string[]} */ pending) {
  fs.writeFileSync(BASELINE_FILE, `${JSON.stringify({ pending }, null, 2)}\n`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  let result = checkLedger();
  if (process.argv.includes("--accept-pending")) {
    writeBaseline(result.pending);
    console.log(`pending-baseline.json を書き換えました (${result.pending.length} 件)。差分をコミットしてください`);
    result = checkLedger();
  }
  if (process.argv.includes("--json")) {
    console.log(JSON.stringify(result));
  } else {
    for (const e of result.errors) console.error(`✗ ${e}`);
    const s = result.summary;
    console.log(
      `${result.errors.length === 0 ? "✓" : "✗"} 画面・操作 ${s.targets} 件 / シナリオ ${s.scenarios} 件 (実装済み ${s.implemented}・pending ${s.pending})`,
    );
  }
  process.exitCode = result.errors.length === 0 ? 0 : 1;
}
