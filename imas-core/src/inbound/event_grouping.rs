//! イベント年度グルーピングの FFI 面。ロジックは domain::event_grouping。
//!
//! エンティティ全体ではなく初回公演日の射影 (`first_dates`) を受け、
//! 「年ラベル + index 列」([`EventYearGroup`]) を返す (呼び出し側が自国の配列を
//! index で引き直す)。1 ユーザー操作 = 1 呼び出し。

use crate::domain::event_grouping::EventYearGroup;

/// 時系列フィルタ + 年度グルーピング。今後/開催済みの境界・並び順の規則は
/// domain 側のドキュメント参照。`today_key` には JST の今日 (`jst_today`) を渡す。
#[uniffi::export]
pub fn group_event_indices_by_year(
    first_dates: Vec<Option<String>>,
    upcoming: bool,
    today_key: String,
) -> Vec<EventYearGroup> {
    crate::domain::event_grouping::group_events_by_year(&first_dates, upcoming, &today_key)
}
