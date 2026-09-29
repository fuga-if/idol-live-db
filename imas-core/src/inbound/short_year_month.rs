//! 公演日短縮表記の FFI 面。ロジックは domain::short_year_month。

#[uniffi::export]
pub fn short_year_month(date: String) -> String {
    crate::domain::short_year_month::short_year_month(&date)
}
