//! JST「今日」判定の FFI 面。ロジックは domain::jst_day。

#[uniffi::export]
pub fn jst_today(now_epoch_seconds: i64) -> String {
    crate::domain::jst_day::jst_today(now_epoch_seconds)
}

#[uniffi::export]
pub fn jst_is_today_or_later(date: String, now_epoch_seconds: i64) -> bool {
    crate::domain::jst_day::jst_is_today_or_later(date, now_epoch_seconds)
}
