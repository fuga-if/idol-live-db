//! 検索語の畳み込みをブラウザで行うための wasm ラッパ。
//!
//! ## ここに規則を書かないこと
//!
//! 中身は `imas_text_fold::fold` への 1 行委譲だけ。畳み方の判断は
//! `imas-text-fold` が唯一の実体で、この crate は **JS から呼べる形に整えるだけの配管**。
//!
//! ブラウザで畳むのは、検索語 (needle) 側だけがブラウザにあるから。索引側 (haystack) は
//! Rust の web-export が畳んで JSON に載せてある。両側が同じ規則を通らないと
//! 「アプリでは当たるのに Web では当たらない」が起きる。
//!
//! ## 使い方 (Astro の検索 island)
//!
//! ```js
//! const { default: init, fold } = await import("../lib/fold/imas_fold_wasm.js");
//! await init();
//! const q = fold(input.value);
//! rows.filter((r) => r.f.includes(q));
//! ```
//!
//! ビルド:
//! ```text
//! cd web/wasm/imas-fold-wasm
//! wasm-pack build --release --target web --out-dir ../../src/lib/fold
//! ```

use wasm_bindgen::prelude::*;

/// 検索語 / 索引テキストの畳み込み。規則は `imas-text-fold` が唯一の正。
///
/// 大文字小文字とカタカナ→ひらがなを畳み、単独の濁点・半濁点を直前のかなに合成する。
/// 濁点の有無そのものと全角半角は畳まない。
#[wasm_bindgen]
pub fn fold(text: &str) -> String {
    imas_text_fold::fold(text)
}
