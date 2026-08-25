//! バックアップの組み立て・整合判定の FFI 面。ロジックは domain::backup_summary。
//!
//! ファイル/iCloud KVS/SharedPreferences への書き込みと、CloudKit・HTTP といった
//! transport は各 OS に残る。ここを跨ぐのは文字列と射影だけ。
//!
//! 呼び出しは 1 操作 1 回:
//! - 書き出し: `build_backup_envelope` を 1 回 → 返った `envelope_json` を保存/送信
//! - 下見:     `inspect_backup_envelope` を 1 回 (取り込み前に中身を見せたいとき)
//! - 取り込み: `plan_backup_import` を 1 回 → 返った行だけを DB に入れて件数を
//!   `backup_import_summary` に渡す

use crate::domain::backup_summary as domain;

/// このコアが書き出す payload の schemaVersion。
#[uniffi::export]
pub fn backup_current_schema_version() -> i64 {
    domain::BACKUP_SCHEMA_VERSION
}

/// canonical (iOS 表記) の kind → Android の `user_marks.kind`。
#[uniffi::export]
pub fn backup_kind_to_android(canonical: String) -> String {
    domain::backup_kind_to_android(&canonical)
}

/// Android の `user_marks.kind` → canonical (iOS 表記)。
#[uniffi::export]
pub fn backup_kind_to_canonical(android: String) -> String {
    domain::backup_kind_to_canonical(&android)
}

/// payload JSON・checksum・envelope JSON を組み立てる。
#[uniffi::export]
pub fn build_backup_envelope(
    input: domain::BackupExportInput,
    dialect: domain::BackupKindDialect,
) -> domain::BackupEnvelopeDocument {
    domain::build_backup_envelope(&input, dialect)
}

/// envelope を検証し、メタ情報と件数だけを返す (取り込み前の確認画面用)。
#[uniffi::export]
pub fn inspect_backup_envelope(
    envelope_json: String,
) -> Result<domain::BackupEnvelopeInfo, domain::BackupImportError> {
    domain::inspect_backup_envelope(&envelope_json)
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
