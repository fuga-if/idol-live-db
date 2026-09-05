//! 日付 (`yyyy-MM-dd`) を画面に置く形へ分ける。**曜日も期間の畳み方もここで 1 回だけ決める。**
//!
//! 出面は行の左端に「日付ブロック」(月日を大きく、曜日と年を小さく) を置く。
//! 文字列を切る・曜日を求める・期間を 1 本にする判断を受け手に持たせない
//! (TS は `Date` を触らない) ための置き場で、[`crate::domain::short_year_month`] と
//! 同じ流儀で部分日付 (`"2024-08"` / `"2024"`) や日付でない文字列は**捏造せずそのまま返す**。

use super::short_year_month::ymd_components;
use chrono::{Datelike, NaiveDate};

/// 曜日の日本語 1 文字。`Weekday::num_days_from_monday()` の順。
const WEEKDAYS_JA: [&str; 7] = ["月", "火", "水", "木", "金", "土", "日"];

/// 分解した日付。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DateParts {
    /// `"2026"`。年が読めなければ空。
    pub year: String,
    /// `"9/12"`。年月までなら `"8月"`、年だけなら空、解釈できなければ原文。
    pub month_day: String,
    /// `"土"`。日まで揃った実在の日付にだけ入る。
    pub weekday: Option<&'static str>,
}

/// `yyyy-MM-dd` を暦として解釈する。部分日付・空・存在しない日付は `None`。
fn parse_ymd(date: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(date, "%Y-%m-%d").ok()
}

fn weekday_of(date: NaiveDate) -> &'static str {
    WEEKDAYS_JA[date.weekday().num_days_from_monday() as usize]
}

/// 日付ブロック用に分ける。
pub fn date_parts(date: &str) -> DateParts {
    if let Some(d) = parse_ymd(date) {
        return DateParts {
            year: d.year().to_string(),
            month_day: format!("{}/{}", d.month(), d.day()),
            weekday: Some(weekday_of(d)),
        };
    }
    let comps = ymd_components(date);
    let month = comps.get(1).and_then(|m| m.parse::<u32>().ok());
    match (comps.as_slice(), month) {
        ([y, _], Some(m)) if is_year(y) && (1..=12).contains(&m) => DateParts {
            year: (*y).to_string(),
            month_day: format!("{m}月"),
            weekday: None,
        },
        ([y], _) if is_year(y) => {
            DateParts { year: (*y).to_string(), month_day: String::new(), weekday: None }
        }
        _ => DateParts { year: String::new(), month_day: date.to_string(), weekday: None },
    }
}

fn is_year(s: &str) -> bool {
    s.len() == 4 && s.bytes().all(|b| b.is_ascii_digit())
}

/// `"2026-09-19"` → `"2026-09-19 (土)"`。曜日が決まらない入力は原文のまま。
pub fn with_weekday(date: &str) -> String {
    match parse_ymd(date) {
        Some(d) => format!("{date} ({})", weekday_of(d)),
        None => date.to_string(),
    }
}

/// `"2026-09-13"` → `"9/13 (日)"`。行の中に短く添えるときの形。
/// 部分日付は曜日なし (`"8月"`)、月日が取れない入力は原文のまま。
pub fn short_with_weekday(date: &str) -> String {
    let parts = date_parts(date);
    match (parts.month_day.is_empty(), parts.weekday) {
        (true, _) => date.to_string(),
        (false, Some(w)) => format!("{} ({w})", parts.month_day),
        (false, None) => parts.month_day,
    }
}

/// 期間の終端。**初日と違う日にだけ `Some`** (1 日で終わるものに終端は無い)。
/// 「同じ日を 2 度出さない」判断はここ 1 箇所。
pub fn range_end<'a>(first: Option<&str>, last: Option<&'a str>) -> Option<&'a str> {
    match (first, last) {
        (Some(f), Some(l)) if f != l => Some(l),
        _ => None,
    }
}

/// 開催期間を曜日つきで 1 本に (`2026-09-19 (土) 〜 2026-09-20 (日)`)。
/// 1 日で終わるライブは 1 つだけ、片方しか無ければそれだけ。
pub fn range_with_weekday(first: Option<&str>, last: Option<&str>) -> Option<String> {
    match (first, range_end(first, last)) {
        (Some(f), Some(l)) => Some(format!("{} 〜 {}", with_weekday(f), with_weekday(l))),
        (Some(f), None) => Some(with_weekday(f)),
        (None, _) => last.map(with_weekday),
    }
}

/// 行に添える終端 (`〜 9/13 (日)`)。初日は日付ブロックが持つので、ここは終端だけ。
/// 1 日で終わるライブでは `None`。
pub fn until_display(first: Option<&str>, last: Option<&str>) -> Option<String> {
    range_end(first, last).map(|l| format!("〜 {}", short_with_weekday(l)))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2026-09-19 は土曜。ライブは週末に集中するので、曜日が 1 日ずれると全行が嘘になる。
    #[test]
    fn full_date_is_split_with_its_weekday() {
        assert_eq!(
            date_parts("2026-09-19"),
            DateParts { year: "2026".into(), month_day: "9/19".into(), weekday: Some("土") }
        );
        assert_eq!(date_parts("2026-04-03").weekday, Some("金"));
        assert_eq!(date_parts("2024-02-29").weekday, Some("木"));
    }

    /// 月日はゼロ埋めしない (`9/19` であって `09/19` ではない)。
    #[test]
    fn month_day_has_no_zero_padding() {
        assert_eq!(date_parts("2005-01-05").month_day, "1/5");
    }

    /// 年月までの部分日付は月まで出し、曜日は付けない。
    #[test]
    fn partial_dates_keep_what_is_known() {
        assert_eq!(
            date_parts("2024-08"),
            DateParts { year: "2024".into(), month_day: "8月".into(), weekday: None }
        );
        assert_eq!(
            date_parts("2024"),
            DateParts { year: "2024".into(), month_day: String::new(), weekday: None }
        );
    }

    /// 解釈できない入力は捏造しない (原文を月日の位置にそのまま置く)。
    #[test]
    fn unparsable_input_passes_through() {
        assert_eq!(
            date_parts("未定"),
            DateParts { year: String::new(), month_day: "未定".into(), weekday: None }
        );
        assert_eq!(date_parts("").month_day, "");
        // 存在しない日付 (2 月 30 日) も暦としては解釈しない。
        assert_eq!(date_parts("2024-02-30").weekday, None);
        assert_eq!(date_parts("2024-02-30").month_day, "2024-02-30");
        assert_eq!(date_parts("2024-").weekday, None);
    }

    #[test]
    fn weekday_suffix_is_added_only_when_known() {
        assert_eq!(with_weekday("2026-09-19"), "2026-09-19 (土)");
        assert_eq!(with_weekday("2026-09"), "2026-09");
        assert_eq!(short_with_weekday("2026-09-13"), "9/13 (日)");
        assert_eq!(short_with_weekday("2026-09"), "9月");
        assert_eq!(short_with_weekday("未定"), "未定");
        assert_eq!(short_with_weekday("2026"), "2026");
    }

    /// 期間表記。同じ日なら 1 つ、片方しか無ければそれだけ。
    #[test]
    fn ranges_collapse_single_days() {
        assert_eq!(range_end(Some("2026-09-19"), Some("2026-09-20")), Some("2026-09-20"));
        assert_eq!(range_end(Some("2026-09-19"), Some("2026-09-19")), None);
        assert_eq!(range_end(None, Some("2026-09-19")), None);
        assert_eq!(
            range_with_weekday(Some("2026-09-19"), Some("2026-09-20")),
            Some("2026-09-19 (土) 〜 2026-09-20 (日)".to_string())
        );
        assert_eq!(
            range_with_weekday(Some("2026-09-19"), Some("2026-09-19")),
            Some("2026-09-19 (土)".to_string())
        );
        assert_eq!(range_with_weekday(None, Some("2026-09-19")), Some("2026-09-19 (土)".to_string()));
        assert_eq!(range_with_weekday(None, None), None);
        assert_eq!(
            until_display(Some("2026-09-12"), Some("2026-09-13")),
            Some("〜 9/13 (日)".to_string())
        );
        assert_eq!(until_display(Some("2026-09-12"), Some("2026-09-12")), None);
    }
}
