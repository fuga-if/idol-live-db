//! 今年の P 活動報告の FFI 面。集計は [`crate::domain::year_report`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::event_list_queries::AttendanceMarkRecord;
use crate::domain::year_report::{self as domain, YearReport, YearReportInput};

#[uniffi::export]
impl SnapshotStore {
    /// 1 年分の報告 (めくるページと、まとめの 1 枚の中身)。
    pub fn year_report(&self, input: YearReportInput) -> Result<YearReport, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::year_report(&snap, &input))
    }

    /// 参加した公演のある年 (新しい順、今日より先は入れない)。
    pub fn year_report_years(
        &self,
        show_marks: Vec<AttendanceMarkRecord>,
        event_marks: Vec<AttendanceMarkRecord>,
        today: String,
    ) -> Result<Vec<u16>, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::year_report_years(
            &snap,
            &show_marks,
            &event_marks,
            &today,
        ))
    }
}

/// P名刺の画面とスケジュールに報告の入口を出す年 (12 月は今年・1 月は去年、ほかは無し)。
#[uniffi::export]
pub fn year_report_offer_year(today: String) -> Option<u16> {
    domain::year_report_offer_year(&today)
}
