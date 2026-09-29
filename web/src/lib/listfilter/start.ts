/**
 * 絞り込みの島を、URL を見てすぐ起動するかの判定 (DOM に触らない純粋関数)。
 *
 * 島は約 10MB の生テーブルと wasm を取りに行くので、起動するのは島が復元できる条件が
 * URL にあるときだけにする。`?utm_...` のような関係の無いクエリでは起動しない (RedTeam L-7)。
 *
 * 島が知っているパラメータは、Rust が出した土台 (`queryBase` = `SongQuery` / `IdolQuery`)
 * の鍵と、並べ替えの `sort` / `dir`。ページが決めている軸 (`fixedAxes`) は島が読まないので除く。
 * 軸の名前をここに書き写さない。
 */
const SORT_PARAMS = ["sort", "dir"] as const;

export function hasIslandQuery(
  search: string,
  queryBase: Record<string, unknown>,
  fixedAxes: Iterable<string>,
): boolean {
  const fixed = new Set(fixedAxes);
  const known = new Set([...Object.keys(queryBase).filter((k) => !fixed.has(k)), ...SORT_PARAMS]);
  for (const [key, value] of new URLSearchParams(search)) {
    if (known.has(key) && value !== "") return true;
  }
  return false;
}
