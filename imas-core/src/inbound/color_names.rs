//! 色の読み上げ名の FFI 面。規則は [`crate::domain::color_names`]。

/// 色の読み上げ名 (`ピンク` / 表に無ければ `#RRGGBB` / 無ければ `不明`)。
/// 色の数は有界なので、一覧で使うなら OS 側で hex ごとに覚えておくとよい。
#[uniffi::export]
pub fn color_accessibility_name(hex: Option<String>) -> String {
    crate::domain::color_names::color_name(hex.as_deref())
}

/// ペンライトの色の帯の読み上げ (`ペンライト: 2色 ピンク、白`)。帯 1 本で 1 回。
#[uniffi::export]
pub fn penlight_accessibility_label(hexes: Vec<String>) -> String {
    crate::domain::color_names::penlight_label(&hexes)
}
