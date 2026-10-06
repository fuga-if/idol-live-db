//! プロフィール帳の FFI 面。ロジックは domain::profile_sheet。

use super::snapshot_store::{SnapshotError, SnapshotStore};
use crate::domain::profile_sheet::{
    ProfileAutoField, ProfileAutoFieldInfo, ProfileAutoFieldRow, ProfileBrandCheck,
    ProfileLiveRecord, ProfileSheet, ProfileSheetLayout, ProfileSheetRecord, ProfileSheetSize,
    ProfileSheetSizeInfo, ProfileSheetStyleInfo,
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
pub fn profile_sheet_styles() -> Vec<ProfileSheetStyleInfo> {
    crate::domain::profile_sheet::profile_sheet_styles()
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
pub fn profile_brand_marks(
    sheet: ProfileSheet,
    record: ProfileSheetRecord,
) -> Vec<ProfileBrandCheck> {
    crate::domain::profile_sheet::profile_brand_marks(&sheet, &record)
}

#[uniffi::export]
pub fn profile_toggle_brand(
    sheet: ProfileSheet,
    record: ProfileSheetRecord,
    brand_id: String,
) -> ProfileSheet {
    crate::domain::profile_sheet::profile_toggle_brand(&sheet, &record, &brand_id)
}

#[uniffi::export]
impl SnapshotStore {
    /// プロフィール帳の、参加した公演のセトリ・会場から数えた記録
    /// (いちばん聴いた曲・担当の歌唱・いちばん通った会場・都道府県の数)。
    /// `attended_show_ids` は参加を付けた公演 (予定も混ざってよい)、`today` は JST の今日。
    pub fn profile_live_record(
        &self,
        attended_show_ids: Vec<String>,
        oshi_idol_ids: Vec<String>,
        today: String,
    ) -> Result<ProfileLiveRecord, SnapshotError> {
        let snap = self.current()?;
        Ok(crate::domain::profile_sheet::profile_live_record(
            &snap,
            &attended_show_ids,
            &oshi_idol_ids,
            &today,
        ))
    }
}
