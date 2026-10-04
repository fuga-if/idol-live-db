//! 「今日は何の日？」(FFI 面・impl 分割)。domain::on_this_day への委譲だけ。
//!
//! 1 ユーザー操作 (= 日を開く・送る) = 1 呼び出し。記念日・誕生日・過去のライブ・
//! リリースと共有文を 1 本で返す。日付は JST の `YYYY-MM-DD`。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::on_this_day::{self as domain, OnThisDay};

#[uniffi::export]
impl SnapshotStore {
    /// `day` (JST `YYYY-MM-DD`) と同じ月日の、過去の記念日・ライブ・リリースと誕生日。
    pub fn on_this_day(&self, day: String) -> Result<OnThisDay, SnapshotError> {
        let snap = self.current()?;
        Ok(domain::on_this_day(&snap, &day))
    }
}

#[cfg(test)]
mod tests {
    use crate::test_support::bundle_store;

    #[test]
    fn ffi_surface_smoke() {
        let day = bundle_store().on_this_day("2026-10-04".into()).unwrap();
        assert!(!day.anniversaries.is_empty());
    }
}
