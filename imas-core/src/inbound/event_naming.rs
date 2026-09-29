//! ライブ名の行表示の FFI 面。規則は [`crate::domain::event_naming`]。

/// 行に出す短いライブ名 (先頭の作品名を 1 つ落とす)。省略するかの設定は OS 側で見て、
/// 省略しないときは呼ばない。ライブ名の数は有界なので、OS 側で名前ごとに覚えておくとよい。
#[uniffi::export]
pub fn event_short_name(name: String) -> String {
    crate::domain::event_naming::event_short_name(&name).to_string()
}

/// [`event_short_name`] の一括版 (入力と同じ並び)。一覧を組むときに 1 回で済ませる。
#[uniffi::export]
pub fn event_short_names(names: Vec<String>) -> Vec<String> {
    names
        .iter()
        .map(|name| crate::domain::event_naming::event_short_name(name).to_string())
        .collect()
}
