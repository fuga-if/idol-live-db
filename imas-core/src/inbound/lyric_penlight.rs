//! ペンライトの指示 (ペンラ芸) の FFI 口。規則は domain::lyric_penlight。

use crate::domain::lyric_penlight as d;
pub use crate::domain::lyric_penlight::{PenlightColor, PenlightColorKind, PenlightPreset};

/// 色の指示 (`oshi` / `idol:<id>` / `#RRGGBB`) を読む。書き方が違えば `None`。
#[uniffi::export]
pub fn lyric_penlight_color(spec: String) -> Option<PenlightColor> {
    d::parse_color(&spec)
}

/// 決まった色を保存する値 (`#RRGGBB`) に書く。
#[uniffi::export]
pub fn lyric_penlight_fixed_value(rgb: u32) -> String {
    d::fixed_color_value(rgb)
}

/// 決まった色の選択肢。
#[uniffi::export]
pub fn lyric_penlight_presets() -> Vec<PenlightPreset> {
    d::presets()
}

/// 色の名前。`given` (アイドルの色ならアプリが渡す名前) が優先。名付けられなければ `None`。
#[uniffi::export]
pub fn lyric_penlight_color_name(spec: Option<String>, given: Option<String>) -> Option<String> {
    d::color_name(spec.as_deref(), given.as_deref())
}

/// 古いアプリ向けの代わりの文言 (保存するときコールの text に入れる)。
#[uniffi::export]
pub fn lyric_penlight_fallback_text(
    color: Option<String>,
    color_name: Option<String>,
    note: Option<String>,
) -> String {
    d::fallback_text(color.as_deref(), color_name.as_deref(), note.as_deref())
}
