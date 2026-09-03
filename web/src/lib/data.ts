/**
 * `web/data/**.json` を読む **唯一の入口**。
 *
 * ここに join / filter / sort / 「今日」の判定 / 色の決定を **1 行も書かない** (INV-1)。
 * それらはすべて imas-core (Rust) が済ませて JSON に落としてあり、Astro は
 * 「読んで HTML の要素に置く」だけをする。
 *
 * `IMAS_WEB_DATA` でデータ根を差し替えられる (`npm run dev:fixture` が
 * `./data-fixture` を指す)。実データが来ても呼び出し側のコードは変わらない。
 */
import fs from "node:fs";
import path from "node:path";
import type { SiteMeta } from "./schema/SiteMeta";
import type { RoutesFile } from "./schema/RoutesFile";
import type { RouteKind } from "./schema/RouteKind";

/** JSON の互換性ゲート。Rust の DTO と揃える。 */
export const SCHEMA_VERSION = 1;

const ROOT = path.resolve(process.env.IMAS_WEB_DATA ?? "./data");

/**
 * データ根の下から JSON を 1 個読む。
 * schemaVersion を持つファイルは必ず突き合わせ、ずれていたらビルドを落とす
 * (古い web/data のまま新しいテンプレートで組み上がるのを防ぐ)。
 */
export function readJson<T>(rel: string): T {
  const file = path.join(ROOT, rel);
  if (!fs.existsSync(file)) {
    throw new Error(
      `データが見つかりません: ${file}\n` +
        "先に `npm run export` (実データ) を回すか、IMAS_WEB_DATA=./data-fixture を指定してください。",
    );
  }
  const value = JSON.parse(fs.readFileSync(file, "utf8")) as T & {
    schemaVersion?: number;
  };
  if (value.schemaVersion !== undefined && value.schemaVersion !== SCHEMA_VERSION) {
    throw new Error(
      `schemaVersion が一致しません: ${file} (${value.schemaVersion} != ${SCHEMA_VERSION})`,
    );
  }
  return value;
}

/** データ根 (診断メッセージ用)。 */
export const dataRoot = (): string => ROOT;

/* --------------------------------------------------------------------------
 * サイト全体で 1 回だけ読むもの。
 * 詳細ページ (約 7,600 個) は都度読む = ビルド中の常駐メモリを一定に保つ。
 * ----------------------------------------------------------------------- */

let metaCache: SiteMeta | null = null;
/** `meta.json` — 件数・「今日」(JST)・アプリと外部サイトへのリンク。 */
export const meta = (): SiteMeta => (metaCache ??= readJson<SiteMeta>("meta.json"));

let routesCache: RoutesFile | null = null;
/** `routes.json` — 全ルート。`getStaticPaths` はこれを返すだけにする。 */
export const routes = (): RoutesFile => (routesCache ??= readJson<RoutesFile>("routes.json"));

/**
 * ページ 1 枚ぶんの JSON。`RouteEntry.data` に入っている相対パスをそのまま渡す
 * (ファイル名の組み立て規則を TS 側に持たないため)。
 */
export const page = <T>(dataPath: string): T => readJson<T>(dataPath);

/**
 * `getStaticPaths` の定型。ルート種別と params 名を渡すと
 * `{ params, props: { data } }` の配列になる。
 *
 * `RouteEntry.key` が params に渡す値 (`id` は DB 上の id であって URL の材料にしない)。
 * ここでの `filter` は「このルートファイルが担当する行を拾う」配線であって、
 * 表示規則ではない (何を出すか / どう並べるかは Rust が routes.json を作る時点で決めている)。
 */
export function pathsFor(
  kind: RouteKind,
  paramName: string,
): { params: Record<string, string>; props: { data: string } }[] {
  return routes()
    .routes.filter((r) => r.kind === kind && r.key !== null)
    .map((r) => ({ params: { [paramName]: r.key! }, props: { data: r.data } }));
}

/**
 * パラメータを取らない単独ページ (トップ / 一覧のトップ など) の JSON パス。
 * 見つからなければビルドを落とす (ページだけ空で出る事故を防ぐ)。
 */
export function routeData(kind: RouteKind, urlPath: string): string {
  const hit = routes().routes.find((r) => r.kind === kind && r.path === urlPath);
  if (!hit) {
    throw new Error(`routes.json に ${kind} の ${urlPath} がありません`);
  }
  return hit.data;
}
