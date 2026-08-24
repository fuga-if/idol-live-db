//! イベント一覧絞り込みの FFI 面。ロジックは domain::event_list_filtering。

use crate::domain::event_list_filtering::{EventFilterCriteria, EventFilterItem};

/// 絞り込みを適用し、残すイベントの index 列 (入力順) を返す。
///
/// エンティティ全体は渡さず「必要フィールドの射影 + 解決済み条件 → index 列」の
/// 1 呼び出しで済ませ、呼び出し側が自国の配列を index で引く (FFI 境界の規約)。
/// マーク集合・会場 id 集合の解決 (show→event 逆引き等) は呼び出し側が済ませてから渡す。
#[uniffi::export]
pub fn filter_event_indices(
    items: Vec<EventFilterItem>,
    criteria: EventFilterCriteria,
) -> Vec<u32> {
    crate::domain::event_list_filtering::filter_event_indices(&items, &criteria)
}
