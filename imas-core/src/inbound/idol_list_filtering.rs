//! アイドル一覧絞り込み・並べ替えの FFI 面。ロジックは domain::idol_list_filtering。
//!
//! エンティティ全体ではなく射影 (`IdolListEntry`) を受け、採用/整列した index 列を返す
//! (呼び出し側が自国の配列を index で引き直す)。1 ユーザー操作 = 1 呼び出し。
//! 並び順のメタ情報も、ケースごとの FFI 呼び出しループにならないよう表で一括して返す。

use crate::domain::idol_list_filtering::{
    IdolListEntry, IdolListFilterCriteria, IdolSortKind, IdolSortOrderMeta,
};

/// ブランド/属性/マイマーク/テキスト検索の絞り込みを適用し、採用した index 列を返す
/// (入力順を保持)。
#[uniffi::export]
pub fn filter_idol_list(entries: Vec<IdolListEntry>, criteria: IdolListFilterCriteria) -> Vec<u32> {
    crate::domain::idol_list_filtering::filter_idol_list(&entries, &criteria)
}

/// 指定の並び順で整列した index 列を返す。`ascending` が None なら既定方向。
/// 値なしの末尾送り・公式順での安定化は domain 側の契約を参照。
#[uniffi::export]
pub fn sort_idol_list(
    entries: Vec<IdolListEntry>,
    kind: IdolSortKind,
    ascending: Option<bool>,
) -> Vec<u32> {
    crate::domain::idol_list_filtering::sort_idol_list(&entries, kind, ascending)
}

/// 並び順メタ情報 (既定方向・ブランド区切り・ラベル文言) を全種別ぶん返す。
/// 呼び出し側はこれを 1 回だけ取得してキャッシュする想定。
#[uniffi::export]
pub fn idol_sort_order_table() -> Vec<IdolSortOrderMeta> {
    crate::domain::idol_list_filtering::sort_order_table()
}
