//! テキスト検索カタログの FFI 面。ロジックは domain::text_search_index。

use crate::domain::text_search_index::{self, TextSearchIndex};

/// 全項目ぶんの検索索引を 1 回で前処理して抱えるカタログ。
///
/// iOS の旧設計は「曲ごとに索引を持ち、打鍵ごとに全曲 matches() を呼ぶ」だったが、
/// それを素直に FFI 化すると打鍵ごとに 2,000+ 回の境界越えになる。ここでは
/// **1 打鍵 = `matching_indices` 1 呼び出し**に畳む (FFI 境界の規約)。
/// 項目そのものは渡さず、フィールド文字列の射影で一括構築し、当たった項目の
/// index 列を返す。呼び出し側は自国の配列を index で引く。
#[derive(uniffi::Object)]
pub struct TextSearchCatalog {
    items: Vec<TextSearchIndex>,
}

#[uniffi::export]
impl TextSearchCatalog {
    /// 項目ごとのフィールド列で一括構築する (読み込み時の 1 回だけ)。
    /// 空文字のフィールドは索引に載らないので、nil 相当は空文字で埋めても除いてもよい。
    #[uniffi::constructor]
    pub fn new(items: Vec<Vec<String>>) -> Self {
        Self {
            items: items.into_iter().map(TextSearchIndex::new).collect(),
        }
    }

    /// 検索語を含む項目の index 列 (入力順)。空の検索語は全項目 (絞り込まない)。
    pub fn matching_indices(&self, needle: String) -> Vec<u32> {
        text_search_index::matching_indices(&self.items, &needle)
    }
}

/// 検索語が当たった範囲を、**元の文字列のバイト位置**で返す (当たらなければ None)。
///
/// ハイライトを敷く側が使う。`matching_indices` と同じ畳み込みを通るので、
/// 「一覧に出ているのに範囲が無い」も「載っていないのに範囲がある」も起きない。
/// 呼び出し側で `contains` 等を書いて規則を二重に持たないこと。
#[uniffi::export]
pub fn text_search_match_range(haystack: String, needle: String) -> Option<TextMatchRange> {
    text_search_index::match_range(&haystack, &needle)
        .map(|(start, end)| TextMatchRange { start, end })
}

/// 元の文字列における一致範囲 (UTF-8 バイト位置)。
///
/// 文字数ではなくバイト位置なのは、呼び出し側 (Swift の `String.Index`) が
/// UTF-8 位置から直接 String.Index を作れるため。文字数だと数え直しが要る。
#[derive(uniffi::Record)]
pub struct TextMatchRange {
    pub start: u32,
    pub end: u32,
}
