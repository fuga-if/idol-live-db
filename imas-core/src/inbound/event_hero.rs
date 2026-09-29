//! イベント詳細のヒーロー・参加予定 / 参加済みの札・日付の幅の FFI 面。
//! 規則は [`crate::domain::event_hero`] と [`crate::domain::date_display`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::date_display;
use crate::domain::event_hero::{self as domain, AttendanceStatusRecord, EventHeroRecord};

/// 参加公演の日付から札を決める (イベント詳細以外で札を出すとき用)。
/// `event_marked` が真で `attended_show_dates` が空なら `event_show_dates` で判定する。
#[uniffi::export]
pub fn attendance_status(
    attended_show_dates: Vec<String>,
    event_show_dates: Vec<String>,
    event_marked: bool,
    today: String,
) -> AttendanceStatusRecord {
    domain::attendance_status(&attended_show_dates, &event_show_dates, event_marked, &today)
}

/// 開催期間 (`2026-09-19 (土) 〜 2026-09-20 (日)`。1 日なら 1 つ)。イベント一覧の行など。
#[uniffi::export]
pub fn date_range_display(first: Option<String>, last: Option<String>) -> Option<String> {
    date_display::range_with_weekday(first.as_deref(), last.as_deref())
}

/// 年の幅 (`2019` / `2019 – 2021`)。
#[uniffi::export]
pub fn year_range_display(earliest: Option<String>, latest: Option<String>) -> Option<String> {
    date_display::year_range(earliest.as_deref(), latest.as_deref())
}

#[uniffi::export]
impl SnapshotStore {
    /// イベント詳細のヒーロー (開催期間・会場・今後か・参加の札)。未知の id は `None`。
    /// `attended_show_ids` は参加マークのある公演、`event_marked` は event 単位の参加マーク。
    pub fn event_hero(
        &self,
        event_id: String,
        attended_show_ids: Vec<String>,
        event_marked: bool,
        today: String,
    ) -> Result<Option<EventHeroRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::event_hero(&snap, &event_id, &attended_show_ids, event_marked, &today))
    }
}
