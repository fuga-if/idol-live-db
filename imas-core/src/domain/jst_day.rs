//! 「今日」の判定を JST に固定するための共通ルール。
//!
//! DB に入っている公演日 (`shows.date`) は日本のライブの開催日で `"yyyy-MM-dd"` の文字列。
//! これを「今日」と文字列比較して「未来公演か」「次の公演はどれか」を出している。
//! 端末ローカルのタイムゾーンで「今日」を作ると海外ユーザーだけ判定が 1 日ずれるため、
//! JST (UTC+9 固定・夏時間なし) に固定する。
//!
//! `now` を epoch 秒で受け取るのはテストで日付境界を再現するため。呼ぶたびに計算する
//! (キャッシュすると日付が変わったとき「今日」が古いまま残る)。既定値の注入は
//! 各プラットフォームの薄いラッパ (iOS `JSTDay` / Android `JstDay`) が担う。

use chrono::{DateTime, FixedOffset};

/// JST は UTC+9 固定 (1951 年以降夏時間なし)。IANA tzdata に依存しない。
const JST_OFFSET_SECONDS: i32 = 9 * 3600;

/// JST での「今日」を公演日と同じ `"yyyy-MM-dd"` 表記で返す。
pub fn jst_today(now_epoch_seconds: i64) -> String {
    let jst = FixedOffset::east_opt(JST_OFFSET_SECONDS).expect("JST offset は常に有効");
    // 表現不能な epoch (紀元前後数億年) のみ None。公演日データでは到達しない。
    let utc = DateTime::from_timestamp(now_epoch_seconds, 0).unwrap_or(DateTime::UNIX_EPOCH);
    utc.with_timezone(&jst).format("%Y-%m-%d").to_string()
}

/// 公演日が「今日以降」か。当日は未来として扱う (開催日当日はまだ終わっていない)。
///
/// `date` は `"yyyy-MM-dd"` の公演日。空文字は未来ではない。
pub fn jst_is_today_or_later(date: String, now_epoch_seconds: i64) -> bool {
    !date.is_empty() && date.as_str() >= jst_today(now_epoch_seconds).as_str()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 2026-07-26 10:00 JST = 01:00 UTC。ハワイ (UTC-10) ではまだ 7/25。
    const JULY26_10AM_JST: i64 = 1785027600;

    #[test]
    fn today_is_jst_not_device_local() {
        assert_eq!(jst_today(JULY26_10AM_JST), "2026-07-26");
    }

    #[test]
    fn day_boundary_before_and_after_midnight_jst() {
        // 2026-07-25 23:59:59 JST = 14:59:59 UTC
        assert_eq!(jst_today(1784991599), "2026-07-25");
        // 2026-07-26 00:00:00 JST = 15:00:00 UTC (前日)
        assert_eq!(jst_today(1784991600), "2026-07-26");
    }

    #[test]
    fn same_day_counts_as_upcoming() {
        assert!(jst_is_today_or_later("2026-07-26".into(), JULY26_10AM_JST));
        assert!(jst_is_today_or_later("2026-07-27".into(), JULY26_10AM_JST));
        assert!(!jst_is_today_or_later("2026-07-25".into(), JULY26_10AM_JST));
    }

    #[test]
    fn empty_date_is_not_upcoming() {
        assert!(!jst_is_today_or_later("".into(), JULY26_10AM_JST));
    }
}
