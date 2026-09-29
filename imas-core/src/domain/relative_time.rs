//! 投稿・編集の「3日前」のような相対時刻の言い方 (Q-08k / R-C-06)。
//!
//! Android に 3 通り (「今」と「たった今」、`yyyy/MM/dd` と `yyyy/M/d`) 書かれていて、
//! iOS は `RelativeDateTimeFormatter` (OS の言い回し) を使っていた。ここで 1 つに決める。

use chrono::DateTime;

use crate::domain::jst_day::jst;

/// `epoch_ms` の時刻を `now_ms` から見た言い方にする。
///
/// 1 分未満 (と未来) は `たった今`、1 時間未満は `N分前`、1 日未満は `N時間前`、
/// 30 日未満は `N日前`、それより前は JST の日付 (`2026/9/3`)。
pub fn relative_time(epoch_ms: i64, now_ms: i64) -> String {
    let seconds = (now_ms - epoch_ms) / 1000;
    match seconds {
        ..60 => "たった今".to_string(),
        60..3_600 => format!("{}分前", seconds / 60),
        3_600..86_400 => format!("{}時間前", seconds / 3_600),
        86_400..2_592_000 => format!("{}日前", seconds / 86_400),
        _ => DateTime::from_timestamp_millis(epoch_ms)
            .map(|t| t.with_timezone(&jst()).format("%Y/%-m/%-d").to_string())
            .unwrap_or_default(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const NOW: i64 = 1_790_000_000_000;

    #[test]
    fn steps_from_now_to_a_date() {
        let ago = |seconds: i64| relative_time(NOW - seconds * 1000, NOW);
        assert_eq!(ago(0), "たった今");
        assert_eq!(ago(-120), "たった今", "未来の時刻も「たった今」");
        assert_eq!(ago(59), "たった今");
        assert_eq!(ago(60), "1分前");
        assert_eq!(ago(3_599), "59分前");
        assert_eq!(ago(3_600), "1時間前");
        assert_eq!(ago(86_399), "23時間前");
        assert_eq!(ago(86_400), "1日前");
        assert_eq!(ago(86_400 * 29), "29日前");
    }

    #[test]
    fn older_than_thirty_days_is_the_jst_date() {
        // 2026-09-02T15:30:00Z = JST 2026-09-03 00:30。
        let t = 1_788_363_000_000;
        assert_eq!(relative_time(t, t + 86_400_000 * 40), "2026/9/3");
    }
}
