//! 通知の予定表の FFI 面。規則は [`crate::domain::notification_plan`]。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::notification_plan::{self as domain, NotificationPlanInput, PlannedNotificationRecord};

#[uniffi::export]
impl SnapshotStore {
    /// 通知の予定表 1 回ぶん (上限 60 件・カテゴリ間は round-robin)。OS は積んである通知を
    /// 全部消してから、返ってきたものを端末のその地の暦 (日付 + 時・分) で積む。
    pub fn notification_plan(
        &self,
        input: NotificationPlanInput,
    ) -> Result<Vec<PlannedNotificationRecord>, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::notification_plan(&snap, &input))
    }
}
