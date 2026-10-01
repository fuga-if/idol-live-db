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

/// 紙面の日付欄 (`2026.09.24 THU`)。読めない日付は原文のまま。
pub fn masthead(date: &str) -> String {
    const EN: [&str; 7] = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];
    match parse_ymd(date) {
        Some(d) => format!(
            "{}.{:02}.{:02} {}",
            d.year(),
            d.month(),
            d.day(),
            EN[d.weekday().num_days_from_monday() as usize]
        ),
        None => date.to_string(),
    }
}

/// `today` から `date` まで何日か (どちらも `yyyy-MM-dd`)。過去・読めない日付は `None`。
pub fn days_until(today: &str, date: &str) -> Option<u32> {
    let days = (parse_ymd(date)? - parse_ymd(today)?).num_days();
    u32::try_from(days).ok()
}

fn is_year(s: &str) -> bool {
    s.len() == 4 && s.bytes().all(|b| b.is_ascii_digit())
}

/// 読み上げ用の 1 本 (`"2026年9月19日 土曜日"`)。日付ブロックの 3 分割は耳では
/// 「9/19 土 2026」と聞こえるので、支援技術にはこちらを渡す。部分日付は読める所まで。
pub fn spoken(date: &str) -> String {
    if let Some(d) = parse_ymd(date) {
        return format!("{}年{}月{}日 {}曜日", d.year(), d.month(), d.day(), weekday_of(d));
    }
    let parts = date_parts(date);
    if parts.year.is_empty() { parts.month_day } else { format!("{}年{}", parts.year, parts.month_day) }
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

/// アプリの画面に置く日付 (`11月7日(土)`)。今年でない日付は年を付ける (`2024年11月7日(土)`)。
///
/// 画面に ISO の日付 (`2026-11-07`) を出さないための 1 本 (docs/DESIGN_SYSTEM.md §16)。
/// 年月までの部分日付は `2024年8月`、年だけは `2024年`、読めない入力は原文のまま。
/// `today` は JST の今日 (`yyyy-MM-dd`)。今年かどうかだけに使う。
pub fn label_ja(date: &str, today: &str) -> String {
    let this_year = today.get(..4).filter(|y| is_year(y));
    if let Some(d) = parse_ymd(date) {
        let md = format!("{}月{}日({})", d.month(), d.day(), weekday_of(d));
        return if this_year == Some(d.year().to_string().as_str()) { md } else { format!("{}年{md}", d.year()) };
    }
    let parts = date_parts(date);
    match (parts.year.is_empty(), parts.month_day.is_empty()) {
        (false, false) => format!("{}年{}", parts.year, parts.month_day),
        (false, true) => format!("{}年", parts.year),
        _ => date.to_string(),
    }
}

/// 曜日の種類。土日を色で分けるため (祝日は持たない)。
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum WeekdayKind {
    /// 平日。
    Weekday,
    Saturday,
    Sunday,
    /// 曜日が決まらない (部分日付・読めない入力)。
    Unknown,
}

/// 半券の日付欄 (上の印字 / 大きい数字 / 下の印字)。
///
/// 日付は `NOV` / `07` / `SAT`、年月だけは `2024` / `08` / 空、年だけは 空 / `2024` / 空、
/// 読めない入力は 空 / 原文 / 空。月と曜日は英字 3 文字 (チケットの印字)。
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct TicketStubDate {
    pub top: String,
    pub big: String,
    pub bottom: String,
    pub weekday_kind: WeekdayKind,
}

const MONTHS_EN: [&str; 12] = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const WEEKDAYS_EN: [&str; 7] = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"];

/// 半券の日付欄に分ける。
pub fn ticket_stub(date: &str) -> TicketStubDate {
    if let Some(d) = parse_ymd(date) {
        let w = d.weekday().num_days_from_monday() as usize;
        let kind = match w {
            5 => WeekdayKind::Saturday,
            6 => WeekdayKind::Sunday,
            _ => WeekdayKind::Weekday,
        };
        return TicketStubDate {
            top: MONTHS_EN[d.month0() as usize].to_string(),
            big: format!("{:02}", d.day()),
            bottom: WEEKDAYS_EN[w].to_string(),
            weekday_kind: kind,
        };
    }
    let comps = ymd_components(date);
    let month = comps.get(1).and_then(|m| m.parse::<u32>().ok());
    match (comps.as_slice(), month) {
        ([y, _], Some(m)) if is_year(y) && (1..=12).contains(&m) => TicketStubDate {
            top: (*y).to_string(),
            big: format!("{m:02}"),
            bottom: String::new(),
            weekday_kind: WeekdayKind::Unknown,
        },
        ([y], _) if is_year(y) => TicketStubDate {
            top: String::new(),
            big: (*y).to_string(),
            bottom: String::new(),
            weekday_kind: WeekdayKind::Unknown,
        },
        _ => TicketStubDate {
            top: String::new(),
            big: date.to_string(),
            bottom: String::new(),
            weekday_kind: WeekdayKind::Unknown,
        },
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

/// 年の幅 (`2019` / `2019 – 2021`)。アルバムと CD シリーズの札に出す (Q-08e)。
/// 最初と最後の日付の先頭 4 桁が年として読めるものだけを使い、同じ年なら 1 つ、
/// 片方しか無ければそれだけ。
pub fn year_range(earliest: Option<&str>, latest: Option<&str>) -> Option<String> {
    let year = |d: Option<&str>| {
        d.and_then(|d| d.get(..4)).filter(|y| y.bytes().all(|b| b.is_ascii_digit())).map(str::to_string)
    };
    match (year(earliest), year(latest)) {
        (Some(f), Some(t)) if f != t => Some(format!("{f} – {t}")),
        (Some(y), _) | (None, Some(y)) => Some(y),
        (None, None) => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn year_range_collapses_the_same_year() {
        assert_eq!(year_range(Some("2019-03-01"), Some("2021-12-24")).as_deref(), Some("2019 – 2021"));
        assert_eq!(year_range(Some("2019-03-01"), Some("2019-12-24")).as_deref(), Some("2019"));
        assert_eq!(year_range(Some("2019"), None).as_deref(), Some("2019"));
        assert_eq!(year_range(None, Some("2020-01")).as_deref(), Some("2020"));
        assert_eq!(year_range(Some("未定"), Some("")), None);
        assert_eq!(year_range(None, None), None);
    }

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

#[cfg(test)]
mod label_ja_tests {
    use super::*;

    /// 今年は月日と曜日だけ。年をまたぐと年を付ける (一覧で去年の公演を今年と読み違えない)。
    #[test]
    fn this_year_drops_the_year() {
        assert_eq!(label_ja("2026-11-07", "2026-10-01"), "11月7日(土)");
        assert_eq!(label_ja("2025-12-13", "2026-10-01"), "2025年12月13日(土)");
        assert_eq!(label_ja("2027-01-09", "2026-10-01"), "2027年1月9日(土)");
    }

    #[test]
    fn partial_and_unknown_dates_are_not_invented() {
        assert_eq!(label_ja("2024-08", "2026-10-01"), "2024年8月");
        assert_eq!(label_ja("2024", "2026-10-01"), "2024年");
        assert_eq!(label_ja("未定", "2026-10-01"), "未定");
        assert_eq!(label_ja("", "2026-10-01"), "");
        // 今日が読めなくても、日付は年付きで出す (今年だと決めつけない)。
        assert_eq!(label_ja("2026-11-07", ""), "2026年11月7日(土)");
    }
}

#[cfg(test)]
mod masthead_tests {
    use super::*;

    #[test]
    fn masthead_formats_with_english_weekday() {
        assert_eq!(masthead("2026-09-24"), "2026.09.24 THU");
        assert_eq!(masthead("2026-09"), "2026-09");
    }

    #[test]
    fn days_until_counts_forward_only() {
        assert_eq!(days_until("2026-09-24", "2026-09-26"), Some(2));
        assert_eq!(days_until("2026-09-24", "2026-09-24"), Some(0));
        assert_eq!(days_until("2026-09-24", "2026-09-20"), None);
        assert_eq!(days_until("2026-09-24", "2026-10"), None);
    }
}

#[cfg(test)]
mod ticket_stub_tests {
    use super::*;

    #[test]
    fn full_date_has_month_day_weekday() {
        let s = ticket_stub("2026-11-07");
        assert_eq!((s.top.as_str(), s.big.as_str(), s.bottom.as_str()), ("NOV", "07", "SAT"));
        assert_eq!(s.weekday_kind, WeekdayKind::Saturday);
        assert_eq!(ticket_stub("2026-11-08").weekday_kind, WeekdayKind::Sunday);
        assert_eq!(ticket_stub("2026-10-28").weekday_kind, WeekdayKind::Weekday);
    }

    #[test]
    fn partial_dates_are_not_invented() {
        let ym = ticket_stub("2024-08");
        assert_eq!((ym.top.as_str(), ym.big.as_str(), ym.bottom.as_str()), ("2024", "08", ""));
        let y = ticket_stub("2024");
        assert_eq!((y.top.as_str(), y.big.as_str()), ("", "2024"));
        let raw = ticket_stub("未定");
        assert_eq!(raw.big, "未定");
        assert_eq!(raw.weekday_kind, WeekdayKind::Unknown);
    }
}
