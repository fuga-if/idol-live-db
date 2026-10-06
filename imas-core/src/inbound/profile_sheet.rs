//! P名刺の画像の FFI 面。ロジックは domain::profile_sheet。

use crate::domain::profile_sheet::{
    ProfileAutoField, ProfileAutoFieldInfo, ProfileAutoFieldRow, ProfileBrandCheck, ProfileSheet,
    ProfileSheetLayout, ProfileSheetRecord, ProfileSheetSize, ProfileSheetSizeInfo,
};

#[uniffi::export]
pub fn profile_sheet_default() -> ProfileSheet {
    crate::domain::profile_sheet::profile_sheet_default()
}

#[uniffi::export]
pub fn profile_auto_fields() -> Vec<ProfileAutoFieldInfo> {
    crate::domain::profile_sheet::profile_auto_fields()
}

#[uniffi::export]
pub fn profile_auto_field_info(field: ProfileAutoField) -> ProfileAutoFieldInfo {
    crate::domain::profile_sheet::profile_auto_field_info(field)
}

#[uniffi::export]
pub fn profile_auto_field_rows(
    sheet: ProfileSheet,
    record: ProfileSheetRecord,
) -> Vec<ProfileAutoFieldRow> {
    crate::domain::profile_sheet::profile_auto_field_rows(&sheet, &record)
}

#[uniffi::export]
pub fn profile_toggle_field(sheet: ProfileSheet, field: ProfileAutoField) -> ProfileSheet {
    crate::domain::profile_sheet::profile_toggle_field(&sheet, field)
}

#[uniffi::export]
pub fn profile_sheet_sizes() -> Vec<ProfileSheetSizeInfo> {
    crate::domain::profile_sheet::profile_sheet_sizes()
}

#[uniffi::export]
pub fn profile_sheet_size_info(size: ProfileSheetSize) -> ProfileSheetSizeInfo {
    crate::domain::profile_sheet::profile_sheet_size_info(size)
}

#[uniffi::export]
pub fn profile_sheet_to_json(sheet: ProfileSheet) -> String {
    crate::domain::profile_sheet::profile_sheet_to_json(&sheet)
}

#[uniffi::export]
pub fn profile_sheet_from_json(json: String) -> ProfileSheet {
    crate::domain::profile_sheet::profile_sheet_from_json(&json)
}

#[uniffi::export]
pub fn profile_sheet_layout(sheet: ProfileSheet, record: ProfileSheetRecord) -> ProfileSheetLayout {
    crate::domain::profile_sheet::profile_sheet_layout(&sheet, &record)
}

#[uniffi::export]
pub fn profile_brand_marks(record: ProfileSheetRecord) -> Vec<ProfileBrandCheck> {
    crate::domain::profile_sheet::profile_brand_marks(&record)
}
