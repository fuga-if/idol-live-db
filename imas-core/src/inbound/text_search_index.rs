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
