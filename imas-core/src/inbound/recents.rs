//! 「最近見たもの」の FFI 面。規則は [`crate::domain::recents`]。

/// 見た項目の鍵を先頭に積んだ並び (新しい順・重複なし・上限 20)。保存は OS が行う。
#[uniffi::export]
pub fn recents_after_visit(current_keys: Vec<String>, visited_key: String) -> Vec<String> {
    crate::domain::recents::recents_after_visit(&current_keys, &visited_key)
}
