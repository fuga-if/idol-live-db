//! スキーマ適用の FFI 口。
//!
//! iOS (GRDB) / Android (Room) のどちらからでも、DB のパスを渡すだけで
//! マスタスキーマをあるべき形へ寄せられる。**追加しかしない**ので、
//! ユーザーの担当・お気に入り (user_marks) には触れない。

use crate::outbound::schema_apply::{ensure_master_schema as apply, SchemaApplyResult};

/// マスタスキーマを最新へ寄せる (追加のみ・冪等)。
///
/// 各 OS の移行 (GRDB migration / Room Migration) の**前**に呼ぶ想定。
/// 既にその OS の移行が作った表・列があれば黙って素通りする。
#[uniffi::export]
pub fn ensure_master_schema(db_path: String) -> Result<SchemaApplyResult, SchemaApplyError> {
    apply(&db_path).map_err(SchemaApplyError::Failed)
}

/// 適用に失敗した理由。
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum SchemaApplyError {
    #[error("スキーマを適用できませんでした: {0}")]
    Failed(String),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn missing_file_is_a_typed_error_not_a_panic() {
        // 開けないパスでも panic せず、型のあるエラーで返る
        let r = ensure_master_schema("/存在しない/場所/db.sqlite".to_string());
        assert!(matches!(r, Err(SchemaApplyError::Failed(_))), "{r:?}");
    }

    #[test]
    fn applies_to_a_fresh_file() {
        let dir = std::env::temp_dir().join(format!("imas_ffi_schema_{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let p = dir.join("new.sqlite");
        let _ = std::fs::remove_file(&p);
        let r = ensure_master_schema(p.to_str().unwrap().to_string()).unwrap();
        assert!(r.applied > 20, "{r:?}");
        let _ = std::fs::remove_file(&p);
    }
}
