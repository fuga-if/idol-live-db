//! 担当ブランド (アプリ全体の設定) の FFI 面。ロジックは domain::brand_role。

use crate::domain::brand_role::{
    BrandRole, BrandRoleRecord, BrandRoleRow, BrandRoleSettings, BrandRoleStep,
};

#[uniffi::export]
pub fn brand_role_steps() -> Vec<BrandRoleStep> {
    crate::domain::brand_role::brand_role_steps()
}

#[uniffi::export]
pub fn brand_role_step(role: BrandRole) -> BrandRoleStep {
    crate::domain::brand_role::brand_role_step(role)
}

#[uniffi::export]
pub fn brand_role_from_index(index: i64) -> BrandRole {
    crate::domain::brand_role::brand_role_from_index(index)
}

#[uniffi::export]
pub fn brand_role_settings(json: String, record: BrandRoleRecord) -> BrandRoleSettings {
    crate::domain::brand_role::brand_role_settings(&json, &record)
}

#[uniffi::export]
pub fn brand_roles_configured(json: String) -> bool {
    crate::domain::brand_role::brand_roles_configured(&json)
}

#[uniffi::export]
pub fn brand_role_set(
    rows: Vec<BrandRoleRow>,
    brand_id: String,
    role: BrandRole,
) -> Vec<BrandRoleRow> {
    crate::domain::brand_role::brand_role_set(&rows, &brand_id, role)
}

#[uniffi::export]
pub fn brand_roles_to_json(rows: Vec<BrandRoleRow>) -> String {
    crate::domain::brand_role::brand_roles_to_json(&rows)
}
