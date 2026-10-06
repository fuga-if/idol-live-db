//! プロフィール帳の FFI 面。ロジックは domain::profile_sheet。

use crate::domain::profile_sheet::{
    ProfileAutoField, ProfileAutoFieldInfo, ProfileBrandCheck, ProfileQuestion,
    ProfileQuestionInfo, ProfileSheet, ProfileSheetError, ProfileSheetLayout, ProfileSheetLimits,
    ProfileSheetRecord, ProfileSheetSize, ProfileSheetSizeInfo, ProfileSheetStyle,
    ProfileSheetStyleInfo, ProfileSlot,
};

#[uniffi::export]
pub fn profile_sheet_limits() -> ProfileSheetLimits {
    crate::domain::profile_sheet::profile_sheet_limits()
}

#[uniffi::export]
pub fn profile_sheet_default() -> ProfileSheet {
    crate::domain::profile_sheet::profile_sheet_default()
}

#[uniffi::export]
pub fn profile_questions() -> Vec<ProfileQuestionInfo> {
    crate::domain::profile_sheet::profile_questions()
}

#[uniffi::export]
pub fn profile_question_info(question: ProfileQuestion) -> ProfileQuestionInfo {
    crate::domain::profile_sheet::profile_question_info(question)
}

#[uniffi::export]
pub fn profile_addable_questions(sheet: ProfileSheet) -> Vec<ProfileQuestionInfo> {
    crate::domain::profile_sheet::profile_addable_questions(&sheet)
}

#[uniffi::export]
pub fn profile_question_slot(style: ProfileSheetStyle, question: ProfileQuestion) -> ProfileSlot {
    crate::domain::profile_sheet::profile_question_slot(style, question)
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
pub fn validate_profile_sheet(sheet: ProfileSheet) -> Option<ProfileSheetError> {
    crate::domain::profile_sheet::validate_profile_sheet(&sheet)
}

#[uniffi::export]
pub fn profile_sheet_error_message(error: ProfileSheetError) -> String {
    crate::domain::profile_sheet::profile_sheet_error_message(error)
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
