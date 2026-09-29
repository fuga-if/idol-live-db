//! 公演の呼び名の FFI 面。ロジックは domain::show_naming。

use super::snapshot_store::{SnapshotError, SnapshotStore};

#[uniffi::export]
pub fn show_display_title(event_name: String, show_name: String, date: String) -> String {
    crate::domain::show_naming::show_identity(&event_name, &show_name, &date).title()
}

#[uniffi::export]
impl SnapshotStore {
    /// 公演の正式な呼び名 (「ライブ名 見分け」)。端末のカレンダーに足す予定のタイトルなど。
    pub fn show_title(&self, show_id: String) -> Result<Option<String>, SnapshotError> {
        let snap = self.current()?;
        Ok(crate::domain::show_naming::show_title(&snap, &show_id))
    }

    /// 編集履歴の 1 行が指すもの (行に出す名前と、セトリ系なら行き先の公演)。
    pub fn edit_record_target(
        &self,
        record_type: String,
        record_name: String,
    ) -> Result<crate::domain::show_naming::EditRecordTarget, SnapshotError> {
        let snap = self.current()?;
        Ok(crate::domain::show_naming::edit_record_target(&snap, &record_type, &record_name))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// FFI 関数が domain へ委譲していること。
    #[test]
    fn delegates_to_domain() {
        let expected = crate::domain::show_naming::show_identity(
            "THE IDOLM@STER LIVE", "THE IDOLM@STER LIVE DAY1", "2026-09-19")
            .title();
        assert_eq!(
            show_display_title("THE IDOLM@STER LIVE".into(),
                               "THE IDOLM@STER LIVE DAY1".into(),
                               "2026-09-19".into()),
            expected
        );
    }
}
