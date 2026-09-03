/**
 * 検索語の畳み込み — **差し替え可能な import 面 (配管であって規則ではない)**。
 *
 * 畳み規則の唯一の正は Rust の `imas-text-fold` crate であり、TS 側に規則を書くことは
 * 禁止されている (BRIEF 絶対制約 3 / INV-1)。ここがやるのは
 * 「wasm の `fold` をロードして関数として返す」ことだけ。
 *
 * - Plan W (本命): `npm run wasm` が wasm-pack の出力を `web/public/fold/` に置き、
 *   ここが実行時に `/fold/imas_fold_wasm.js` を動的 import する。
 * - Plan F (退避): 同じパスに TS 移植の glue を置く。**その場合もこのファイルは変えない**
 *   (import 面が同じ形なので、実体だけ差し替わる)。
 *
 * バンドルせず実行時 URL で取りに行くのは、wasm が未生成でも他の 7,600 ページの
 * ビルドが通るようにするため (検索は /search/ だけの関心事で、他ページを人質に取らない)。
 *
 * 索引側 (haystack) は Rust の bin が畳んで JSON に出しているので、ブラウザで畳むのは
 * 検索語 (needle) だけ。したがって wasm は /search/ を実際に使うときにだけ要る。
 */

export type Fold = (text: string) => string;

interface FoldModule {
  default: (init?: unknown) => Promise<unknown>;
  fold: Fold;
}

/** 生成物の場所。public/ 配下なので、そのまま配信 URL になる。 */
const FOLD_MODULE_URL = "/fold/imas_fold_wasm.js";

let cached: Promise<Fold> | null = null;

/**
 * wasm を 1 回だけ初期化して `fold` を返す。
 * 失敗しても呼び出し側が「検索を使えない」と案内できるよう、例外はそのまま投げる。
 */
export function loadFold(): Promise<Fold> {
  cached ??= (async () => {
    const url = FOLD_MODULE_URL;
    const mod = (await import(/* @vite-ignore */ url)) as FoldModule;
    await mod.default();
    return mod.fold;
  })();
  return cached;
}
