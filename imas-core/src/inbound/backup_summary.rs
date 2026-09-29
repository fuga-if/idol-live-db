//! バックアップの組み立て・整合判定の FFI 面。ロジックは domain::backup_summary。
//!
//! ファイル/iCloud KVS/SharedPreferences への書き込みと、CloudKit・HTTP といった
//! transport は各 OS に残る。ここを跨ぐのは文字列と射影だけ。
//!
//! 呼び出しは 1 操作 1 回:
//! - 書き出し: `build_backup_envelope` を 1 回 → 返った `envelope_json` を保存/送信
//! - 取り込み: `plan_backup_import` を 1 回 → 返った行だけを DB に入れて件数を
//!   `backup_import_summary` に渡す

use crate::domain::backup_summary as domain;

/// このコアが書き出す payload の schemaVersion。
#[uniffi::export]
pub fn backup_current_schema_version() -> i64 {
    domain::BACKUP_SCHEMA_VERSION
}

/// iCloud KVS のミラーに載せる行の添字 (入力順)。解除済みの行 (bool が false で文字も無い)
/// は復元しても何も変わらないので落とす。規則は [`domain::is_meaningful_mark`]。
#[uniffi::export]
pub fn backup_meaningful_mark_indices(marks: Vec<domain::BackupUserMarkRecord>) -> Vec<u32> {
    domain::meaningful_mark_indices(&marks)
}

/// payload JSON・checksum・envelope JSON を組み立てる。
#[uniffi::export]
pub fn build_backup_envelope(
    input: domain::BackupExportInput,
    dialect: domain::BackupKindDialect,
) -> domain::BackupEnvelopeDocument {
    domain::build_backup_envelope(&input, dialect)
}

/// envelope を検証し、ローカルの現状と突き合わせて「入れるべき行」を返す。
#[uniffi::export]
pub fn plan_backup_import(
    envelope_json: String,
    local: domain::BackupLocalState,
    restore_device_id: bool,
    dialect: domain::BackupKindDialect,
) -> Result<domain::BackupImportPlan, domain::BackupImportError> {
    domain::plan_backup_import(&envelope_json, &local, restore_device_id, dialect)
}
