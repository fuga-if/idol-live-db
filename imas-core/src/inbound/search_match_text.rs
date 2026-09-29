//! 検索で絞った曲の行に添える「なぜ出ているか」の文の FFI 面。
//! 規則は [`crate::domain::search_match_text`]。

use crate::domain::search_match_text::{self as domain, SearchMatchRowInput, SearchMatchScope};

/// 画面に出ている行ぶんの文を 1 回で返す (入力と同じ並び・同じ数。当たらない行は `None`)。
#[uniffi::export]
pub fn search_match_texts(rows: Vec<SearchMatchRowInput>, scope: SearchMatchScope, needle: String) -> Vec<Option<String>> {
    domain::search_match_texts(&rows, scope, &needle)
}
