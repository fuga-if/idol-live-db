// D1 に投げる SQL の全部。ここに無いクエリは投げない。
//
// 費用の方針 (docs/ARCHITECTURE-data-api.md):
//   * どのクエリも主キー / 索引で引く。フルスキャンになる形は書かない
//     (test/queries.test.ts が EXPLAIN QUERY PLAN で固定している)。
//   * 一覧は LIMIT 必須。OFFSET は使わず、`ord` を鍵にしたキーセット方式で続きを読む。
//   * 読み取り行数が最も増えるのは前方一致 (q)。範囲は畳んだ語の前方一致に限る。

export type ListKind = "idol" | "song" | "unit";

export const MAX_LIMIT = 100;
export const DEFAULT_LIMIT = 20;

/** 前方一致の上端。U+10FFFF はどの語の続きよりも大きい。 */
export const PREFIX_END = "\u{10FFFF}";

export const SQL_VERSION = "SELECT value FROM meta WHERE key = 'version'";
export const SQL_META = "SELECT key, value FROM meta";
export const SQL_DOC = "SELECT body FROM docs WHERE kind = ?1 AND id = ?2";

const TABLE = { idol: "idols", song: "songs", unit: "units" } as const;
const COLUMNS = {
  idol: "x.ord, x.id, x.brand_id, x.name, x.name_kana, x.is_external",
  song: "x.ord, x.id, x.brand_id, x.title, x.title_kana, x.release_date",
  unit: "x.ord, x.id, x.brand_id, x.name, x.name_kana, x.is_permanent",
} as const;

export interface ListFilter {
  kind: ListKind;
  /** 畳み済みの前方一致の語 */
  prefix?: string;
  brand?: string;
  /** アイドルの持ち歌で絞る (kind=song のみ) */
  idol?: string;
  cursor: number;
  /** 1 ページの件数 (続きがあるか見るため +1 して読む) */
  limit: number;
}

export interface Built {
  sql: string;
  binds: (string | number)[];
}

/** 一覧のクエリを組む。バインド変数だけが動き、SQL の形は filter の組み合わせで決まる。 */
export function buildList(f: ListFilter): Built {
  const table = TABLE[f.kind];
  const cols = COLUMNS[f.kind];
  const binds: (string | number)[] = [];
  const bind = (v: string | number) => {
    binds.push(v);
    return `?${binds.length}`;
  };
  const brand = (): string => (f.brand !== undefined ? ` AND x.brand_id = ${bind(f.brand)}` : "");

  if (f.prefix !== undefined) {
    // 検索語の索引 (terms) を範囲で引いて、本体を主キーで引く。同じ行が複数の語で
    // 当たるので ord で畳む。
    const sql =
      `SELECT ${cols} FROM terms t JOIN ${table} x ON x.ord = t.ord ` +
      `WHERE t.kind = ${bind(f.kind)} AND t.term >= ${bind(f.prefix)} AND t.term < ${bind(f.prefix + PREFIX_END)} ` +
      `AND x.ord > ${bind(f.cursor)}${brand()} GROUP BY x.ord ORDER BY x.ord LIMIT ${bind(f.limit + 1)}`;
    return { sql, binds };
  }
  if (f.idol !== undefined) {
    const sql =
      `SELECT ${cols} FROM song_idols si JOIN songs x ON x.ord = si.song_ord ` +
      `WHERE si.idol_id = ${bind(f.idol)} AND si.song_ord > ${bind(f.cursor)}${brand()} ` +
      `ORDER BY si.song_ord LIMIT ${bind(f.limit + 1)}`;
    return { sql, binds };
  }
  if (f.brand !== undefined) {
    const sql =
      `SELECT ${cols} FROM ${table} x WHERE x.brand_id = ${bind(f.brand)} AND x.ord > ${bind(f.cursor)} ` +
      `ORDER BY x.ord LIMIT ${bind(f.limit + 1)}`;
    return { sql, binds };
  }
  const sql =
    `SELECT ${cols} FROM ${table} x WHERE x.ord > ${bind(f.cursor)} ORDER BY x.ord LIMIT ${bind(f.limit + 1)}`;
  return { sql, binds };
}

/** テストが全組み合わせを EXPLAIN するための一覧。 */
export function allListShapes(): ListFilter[] {
  const out: ListFilter[] = [];
  for (const kind of ["idol", "song", "unit"] as ListKind[]) {
    for (const prefix of [undefined, "あ"]) {
      for (const brand of [undefined, "ml"]) {
        for (const idol of kind === "song" && prefix === undefined ? [undefined, "ml_x"] : [undefined]) {
          out.push({ kind, prefix, brand, idol, cursor: 0, limit: 20 });
        }
      }
    }
  }
  return out;
}
