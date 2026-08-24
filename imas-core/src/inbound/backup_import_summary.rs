//! バックアップ復元結果文面の FFI 面。ロジックは domain::backup_import_summary。
//!
//! 復元 1 回につき呼び出しも 1 回 (件数の集計は呼び出し側が済ませてから渡す)。

#[uniffi::export]
pub fn backup_import_summary(
    added_marks: i64,
    added_votes: i64,
    added_personal_tags: i64,
    skipped_marks: i64,
    device_id_restored: bool,
) -> String {
    crate::domain::backup_import_summary::backup_import_summary(
        added_marks,
        added_votes,
        added_personal_tags,
        skipped_marks,
        device_id_restored,
    )
}
