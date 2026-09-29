//! 画面に出す語彙の FFI 面。ロジック (表) は [`crate::domain::vocabulary`]。
//!
//! アプリは起動時に 1 回引いて、生値 → 語の表として持っておく (行ごとに呼ばない)。

use crate::domain::vocabulary::{self as domain, Vocabulary};

/// 語彙の一式 (曲種別・催しの種別と性格・参加形態・チケットの日程・タグのカテゴリ)。
/// 各語は短い形 (`short_label`) と正式な形 (`label`) を持つ。
#[uniffi::export]
pub fn vocabulary() -> Vocabulary {
    domain::vocabulary()
}

/// 曲種別の生値 → 語 (`songs.song_type`)。古い端末 DB の `group` はユニット、
/// 選択肢に出さない古い値 (`original` / `unknown`) も語を返す。知らない値は `None` (出さない)。
/// 一覧の行など多数の値を引くときは、`vocabulary()` を 1 回引いて表として持つこと。
#[uniffi::export]
pub fn song_type_term(value: String) -> Option<crate::domain::vocabulary::VocabularyTerm> {
    domain::song_type(&value).map(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn song_type_term_reads_legacy_and_unknown_values() {
        assert_eq!(song_type_term("group".into()).map(|t| t.value), Some("unit".to_string()), "group はユニット");
        assert_eq!(song_type_term("solo".into()).map(|t| t.value), Some("solo".to_string()));
        assert_eq!(song_type_term("original".into()).map(|t| t.label), Some("オリジナル".to_string()));
        assert_eq!(song_type_term("unknown".into()).map(|t| t.label), Some("不明".to_string()));
        assert_eq!(song_type_term("mystery".into()), None);
    }
}
