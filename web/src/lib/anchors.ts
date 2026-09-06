/**
 * ページ内アンカーの名前。**Rust は断片を組まない** (URL の断片は Astro の描画の都合) ので、
 * id を振る側と `href` を作る側がこの 1 箇所を共有する。
 */

/** セトリの N 曲目 (`SetlistRow` が振り、曲ページの披露履歴が飛ぶ)。 */
export const setlistAnchorId = (number: number): string => `setlist-${number}`;

/** よみ目次の区画の先頭 (`KanaIndex` が飛び、一覧の行が振る)。 */
export const kanaAnchorId = (startIndex: number): string => `kana-${startIndex}`;
