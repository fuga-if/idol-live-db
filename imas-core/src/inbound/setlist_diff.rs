//! セトリ差分判定の FFI 面。ロジックは domain::setlist_diff。
//!
//! エンティティ全体ではなく射影 (`SetlistItemDiffRow`) を受け、送るべき index 列を
//! 返す (呼び出し側が自国の配列を index で引き直す)。1 ユーザー操作 = 1 呼び出し。

use crate::domain::setlist_diff::SetlistItemDiffRow;

/// 送る必要のある item の index だけ返す (新規 + 値が変わったもの)。順序は入力のまま。
///
/// `original` は編集前のスナップショット (順不同でよい。無い id は新規扱い)。
#[uniffi::export]
pub fn setlist_item_indexes_needing_sync(
    items: Vec<SetlistItemDiffRow>,
    original: Vec<SetlistItemDiffRow>,
) -> Vec<u32> {
    crate::domain::setlist_diff::item_indexes_needing_sync(&items, &original)
}

/// 送る必要のある出演者の index だけ返す (新規追加のみ)。順序は入力のまま。
///
/// recordName の生成規則は呼び出し側の所有物なので、規則適用済みの文字列列で受ける。
#[uniffi::export]
pub fn setlist_performer_indexes_needing_sync(
    record_names: Vec<String>,
    initial_record_names: Vec<String>,
) -> Vec<u32> {
    crate::domain::setlist_diff::performer_indexes_needing_sync(&record_names, &initial_record_names)
}
