//! カレンダーの週表示の置き方と、相対時刻の言い方の FFI 面。
//! 規則は [`crate::domain::week_layout`] と [`crate::domain::relative_time`]。

use crate::domain::week_layout::{
    self as domain, PeriodBandPlacement, PeriodSpanInput, TimedBlockInput, TimedLayout,
};

/// `HH:MM` → 0:00 からの経過分。壊れた値・範囲外は `None`。
#[uniffi::export]
pub fn parse_time_minutes(time: String) -> Option<u32> {
    domain::parse_time_minutes(&time)
}

/// 公演の (開始分, 終了分)。開始時刻が無ければ `None` (終日の欄へ)。終了は 2 時間後。
#[uniffi::export]
pub fn show_time_block(start_time: Option<String>) -> Option<TimedBlockInput> {
    domain::show_minutes(start_time.as_deref())
}

/// 1 日ぶんの時刻のある予定を、最大 2 列 + 開始分ごとの `+n` に置く (日ごとに 1 回)。
#[uniffi::export]
pub fn week_timed_layout(blocks: Vec<TimedBlockInput>) -> TimedLayout {
    domain::timed_layout(&blocks)
}

/// 週にかかる受付期間の帯の列と段 (週ごとに 1 回)。
#[uniffi::export]
pub fn week_period_bands(week_start: String, periods: Vec<PeriodSpanInput>) -> Vec<PeriodBandPlacement> {
    domain::period_bands(&week_start, &periods)
}

/// 投稿・編集の相対時刻 (`たった今` / `3分前` / `2時間前` / `5日前` / `2026/9/3`)。
/// 一覧では行ぶんを `relative_times` で 1 回に。
#[uniffi::export]
pub fn relative_time(epoch_ms: i64, now_ms: i64) -> String {
    crate::domain::relative_time::relative_time(epoch_ms, now_ms)
}

/// 行ぶんの相対時刻を 1 回で (入力と同じ並び)。
#[uniffi::export]
pub fn relative_times(epoch_ms: Vec<i64>, now_ms: i64) -> Vec<String> {
    epoch_ms.into_iter().map(|t| crate::domain::relative_time::relative_time(t, now_ms)).collect()
}
