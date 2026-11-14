/**
 * 一覧の絞り込みエンジン — **差し替え可能な import 面 (配管であって規則ではない)**。
 *
 * 実体は `imas-core` の domain を wasm にしたもの (`web/wasm/imas-query-wasm`)。
 * 絞り込みの条件も並び順も選択肢も向こうが持っており、ここがやるのは
 * 「wasm をロードし、生テーブルを渡して `Query` を組む」ことだけ。
 * 選択肢の型 (`SongFacets` / `IdolFacets`) は ts-rs の生成物 (`../schema/`)。
 * `src/lib/search/fold.ts` と同じ流儀。
 *
 * 生テーブル (10MB) と wasm (640KB) は**絞り込みを開くまで取りに行かない**。
 * 一覧を読むだけの人には 1 バイトも配らない。
 */
import type { Query } from "../query/imas_query_wasm";

/** 生テーブルの置き場所。dist/snapshot/ へは astro.config の copy-generated-assets が置く。 */
const TABLES_URL = "/snapshot/tables.json";

// ビルドが中身から作った版を埋める (astro.config の vite.define)。版が変わったときだけ URL が
// 変わるので、10MB の生テーブルを長くキャッシュできる。置き場所そのものは上の定数のまま。
// vitest など define の無い経路では版なしで取る。
declare const __SNAPSHOT_TABLES_V__: string | undefined;
const TABLES_V = typeof __SNAPSHOT_TABLES_V__ === "string" ? __SNAPSHOT_TABLES_V__ : "";

let cached: Promise<Query> | null = null;

/**
 * wasm を 1 回だけ初期化し、生テーブルから組んだ `Query` を返す。
 *
 * 失敗しても呼び出し側が「絞り込みを使えない」と案内できるよう、例外はそのまま投げる。
 */
export function loadQuery(): Promise<Query> {
  cached ??= (async () => {
    const [mod, tables] = await Promise.all([
      import("../query/imas_query_wasm"),
      fetch(TABLES_V ? `${TABLES_URL}?v=${TABLES_V}` : TABLES_URL).then((r) => {
        if (!r.ok) throw new Error(`生テーブルを取得できない: ${r.status}`);
        return r.text();
      }),
    ]);
    await mod.default();
    // 索引はここで組み直す。配られるのは生テーブルだけで、派生は載っていない。
    return new mod.Query(tables);
  })();
  return cached;
}
