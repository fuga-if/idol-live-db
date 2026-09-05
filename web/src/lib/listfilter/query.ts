/**
 * 一覧の絞り込みエンジン — **差し替え可能な import 面 (配管であって規則ではない)**。
 *
 * 実体は `imas-core` の domain を wasm にしたもの (`web/wasm/imas-query-wasm`)。
 * 絞り込みの条件も並び順も向こうが持っており、ここがやるのは
 * 「wasm をロードし、生テーブルを渡して `Query` を組む」ことだけ。
 * `src/lib/search/fold.ts` と同じ流儀。
 *
 * 生テーブル (10MB) と wasm (640KB) は**絞り込みを開くまで取りに行かない**。
 * 一覧を読むだけの人には 1 バイトも配らない。
 */
import type { Query } from "../query/imas_query_wasm";

// 条件の型は Rust が出す (`imas-core` の `SongQuery` を ts-rs が生成)。
// ここに interface を手書きすると、軸を 1 本足したときに片方だけ古いまま残る。
export type { SongQuery } from "../schema/SongQuery";

/** 生テーブルの置き場所。dist/snapshot/ へは astro.config の copy-generated-assets が置く。 */
const TABLES_URL = "/snapshot/tables.json";

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
      fetch(TABLES_URL).then((r) => {
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

export type { IdolQuery } from "../schema/IdolQuery";

/** `Query.facets()` が返す選択肢。値は `SongQuery` にそのまま渡す文字列。 */
export interface SongFacets {
  brands: FacetOption[];
  idols: FacetOption[];
  cdSeries: FacetOption[];
  seriesGroups: FacetOption[];
  /** 並べ替え。既定方向もコアが決めた値をそのまま使う。 */
  sorts: SortOption[];
}

/** `Query.idol_facets()` が返す選択肢。 */
export interface IdolFacets {
  brands: FacetOption[];
  attributes: FacetOption[];
  sorts: SortOption[];
}

export interface FacetOption {
  value: string;
  label: string;
}

export interface SortOption {
  key: string;
  label: string;
  defaultAscending: boolean;
}
