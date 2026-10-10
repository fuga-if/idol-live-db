// 検索語の畳み込み。規則は imas-text-fold が唯一の実体で、これは imas-fold-wasm
// (web/wasm/imas-fold-wasm) をそのまま使う。索引側 (terms.term) は Rust の web-export が
// 同じ関数で畳んで SQL に書くので、両側が同じ規則を通る。
// `npm run wasm` で src/fold/ が生成される (gitignore)。
import wasmModule from "./fold/imas_fold_wasm_bg.wasm";
import { initSync, fold } from "./fold/imas_fold_wasm.js";

initSync({ module: wasmModule });

export { fold };
