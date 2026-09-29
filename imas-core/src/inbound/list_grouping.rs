//! 一覧を塊に分ける規則の FFI 面。規則は [`crate::domain::list_grouping`]。

use crate::domain::list_grouping::{self as domain, IndexGroup, VenueAreaEntry};

/// 会場を都道府県ごとの塊にする (公演数の多い地域が上・同じなら名前順・「その他」は末尾)。
/// 入力は絞り込んだ後の並び。返るのは見出しと入力への添字。
#[uniffi::export]
pub fn group_venues_by_area(venues: Vec<VenueAreaEntry>) -> Vec<IndexGroup> {
    domain::group_venues_by_area(&venues)
}

/// 日付 (`YYYY-MM-DD`) を年ごとの塊にする (新しい年が上・見出しは `2026年`)。
/// 塊の中は入力の並びのまま。
#[uniffi::export]
pub fn group_indices_by_year_desc(dates: Vec<String>) -> Vec<IndexGroup> {
    domain::group_indices_by_year_desc(&dates)
}
