/**
 * 検索語の畳み込み — **差し替え可能な import 面 (配管であって規則ではない)**。
 *
 * 畳み規則の唯一の正は Rust の `imas-text-fold` crate であり、TS 側に規則を書くことは
 * 禁止されている (BRIEF 絶対制約 3 / INV-1)。ここがやるのは
 * 「wasm の `fold` をロードして関数として返す」ことだけ。
 *
 * 実体は `npm run wasm` (wasm-pack `--target web`) が `src/lib/fold/` に出す生成物。
 * glue が `new URL("imas_fold_wasm_bg.wasm", import.meta.url)` で .wasm を取りに行き、
 * Vite がそれを解決して content-hash 付きのアセットとして dist に出す。
 * したがって **参照が壊れたらビルドが落ちる** (無言で検索だけ死ぬことがない)。
 *
 * 動的 import にしてあるのは、検索を実際に使うまで 9KB を転送しないため。
 * 索引側 (haystack) は Rust が畳んで JSON に載せてあるので、ブラウザで畳むのは検索語だけ。
 *
 * 畳み規則を変えるときは Rust (`imas-text-fold`) を先に変え、`parity/fold.json` を
 * 作り直して `npm run test:fold` を緑にすること。**このファイルは変えない。**
 */

export type Fold = (text: string) => string;

let cached: Promise<Fold> | null = null;

/**
 * wasm を 1 回だけ初期化して `fold` を返す。
 * 失敗しても呼び出し側が「検索を使えない」と案内できるよう、例外はそのまま投げる。
 */
export function loadFold(): Promise<Fold> {
  cached ??= (async () => {
    const mod = await import("../fold/imas_fold_wasm.js");
    await mod.default();
    return mod.fold;
  })();
  return cached;
}
