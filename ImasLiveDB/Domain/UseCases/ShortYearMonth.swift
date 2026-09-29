import Foundation

/// 公演日 (`"yyyy-MM-dd"`) を統計タイルに載る短縮表記 `"24.08"` にする。
///
/// 本体は imas-core (Rust) の `domain/short_year_month.rs`。ここは Swift らしい
/// 呼び口 (`ShortYearMonth.format`) を維持するだけの薄いラッパ。
/// なぜ短縮するか・不正入力を素通しする理由もそちらに記載。
enum ShortYearMonth {
    static func format(_ date: String) -> String {
        shortYearMonth(date: date)
    }
}
