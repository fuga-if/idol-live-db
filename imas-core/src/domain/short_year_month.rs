//! 公演日 (`"yyyy-MM-dd"`) を統計タイルに載る短縮表記 `"24.08"` にする。
//!
//! タイルは横 3 つ並ぶので、フル日付だと確実に溢れる。年は下 2 桁で足りる
//! (このアプリが扱うのは 2005 年以降のライブなので 20xx で衝突しない)。
//!
//! 部分日付 (`"2024"` や `"2024-08"`) や空文字が DB に入ることがあるため、
//! 短縮できない入力はそのまま返す (捏造しない・クラッシュしない)。
//!
//! 原本は iOS `ShortYearMonth.format`。Swift の `split(separator:)` は空要素を
//! 落とす (`"2024-"` は 1 要素扱いで素通し) ため、Rust 側でも空要素を除外して
//! 同じ判定になるよう揃えている。

/// `"2024-08-03"` → `"24.08"`。区切れない入力は素通し。
pub fn short_year_month(date: &str) -> String {
    // Swift `split(separator: "-")` と同じく空要素は数えない。
    let comps: Vec<&str> = date.split('-').filter(|s| !s.is_empty()).collect();
    if comps.len() < 2 {
        return date.to_string();
    }
    // Swift `suffix(2)` 相当: 末尾 2 文字 (バイトでなく文字単位。年が 1 文字でも panic しない)。
    let year = comps[0];
    let skip = year.chars().count().saturating_sub(2);
    let short_year: String = year.chars().skip(skip).collect();
    // 月のゼロ埋めは落とさずそのまま使う ("24.8" だと桁が揃わず並びが汚れる)。
    format!("{}.{}", short_year, comps[1])
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 統計タイルは 3 つ横並びなので、短縮に失敗すると即レイアウト崩れになる。
    #[test]
    fn full_date_becomes_short_year_month() {
        assert_eq!(short_year_month("2024-08-03"), "24.08");
    }

    /// 月のゼロ埋めは落とさない ("24.8" だと桁が揃わず並びが汚れる)。
    #[test]
    fn keeps_zero_padded_month() {
        assert_eq!(short_year_month("2005-01-15"), "05.01");
    }

    /// 年月までしかない部分日付も短縮できる。
    #[test]
    fn year_month_only() {
        assert_eq!(short_year_month("2024-08"), "24.08");
    }

    /// 短縮できない入力はそのまま返す (捏造しない)。
    #[test]
    fn unsplittable_input_passes_through() {
        assert_eq!(short_year_month("2024"), "2024");
        assert_eq!(short_year_month(""), "");
        assert_eq!(short_year_month("未定"), "未定");
    }

    /// Swift `split` は空要素を落とすので、末尾ハイフンだけの入力は素通し
    /// (naive な `split('-')` だと 2 要素扱いになり "24." を捏造してしまう)。
    #[test]
    fn trailing_hyphen_passes_through_like_swift() {
        assert_eq!(short_year_month("2024-"), "2024-");
        assert_eq!(short_year_month("--"), "--");
    }

    /// 先頭や連続ハイフンも Swift 同様「空要素を除いた並び」で解釈する。
    #[test]
    fn empty_segments_are_ignored_like_swift() {
        assert_eq!(short_year_month("-2024-08"), "24.08");
        assert_eq!(short_year_month("2024--08"), "24.08");
    }

    /// 年が 2 文字未満でも panic せずそのまま使う (suffix(2) の挙動)。
    #[test]
    fn short_year_does_not_panic() {
        assert_eq!(short_year_month("5-01"), "5.01");
    }
}
