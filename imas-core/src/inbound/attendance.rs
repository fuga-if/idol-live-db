//! 参加形態 (現地 / 配信 / LV) の保存値の FFI 面。ロジックは domain::attendance。
//!
//! 1 公演に複数の形態を付けられる。`user_marks` の attended 行の `text_value` の
//! 読み書きはここを通す (区切りや並びを各 OS に書かない)。

/// `text_value` → 付いている形態 (語彙の順)。NULL・空は現地。
#[uniffi::export]
pub fn attendance_types(text_value: Option<String>) -> Vec<String> {
    crate::domain::attendance::attendance_types(text_value.as_deref())
}

/// 1 つの形態を付ける (`on`) / 外したあとの `text_value`。`None` なら参加マークごと外す。
/// `attended` はいま参加マークが付いているか。
#[uniffi::export]
pub fn attendance_set_type(
    current: Option<String>,
    attended: bool,
    attendance_type: String,
    on: bool,
) -> Option<String> {
    crate::domain::attendance::attendance_set_type(current.as_deref(), attended, &attendance_type, on)
}
