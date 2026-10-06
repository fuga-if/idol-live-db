//! P名刺の FFI 面。ロジックは domain::producer_card。

use crate::domain::producer_card::{
    CardCaseEntry, CardCaseSection, CardCommon, CardDesign, CardDesignInfo, CardFace,
    CardFileContents, CardFileImage, CardFileTypeInfo, CardLink, CardLinkKind, CardLinkKindInfo,
    CardLinkView, CardNameFont, CardNameFontInfo, CardRecordSummary, CardShowRef,
    EncodedProducerCard, ProducerCard, ProducerCardInput, ProducerCardInputError,
    ProducerCardLimits, ScannedCode,
};
use crate::domain::producer_card_avatar::XAvatarLookup;

#[uniffi::export]
pub fn producer_card_limits() -> ProducerCardLimits {
    crate::domain::producer_card::producer_card_limits()
}

#[uniffi::export]
pub fn validate_producer_card(input: ProducerCardInput) -> Option<ProducerCardInputError> {
    crate::domain::producer_card::validate_producer_card(&input)
}

#[uniffi::export]
pub fn producer_card_input_error_message(error: ProducerCardInputError) -> String {
    crate::domain::producer_card::producer_card_input_error_message(error)
}

#[uniffi::export]
pub fn encode_producer_card(input: ProducerCardInput) -> EncodedProducerCard {
    crate::domain::producer_card::encode_producer_card(&input)
}

#[uniffi::export]
pub fn decode_producer_card(text: String) -> Option<ProducerCard> {
    crate::domain::producer_card::decode_producer_card(&text)
}

#[uniffi::export]
pub fn classify_scanned_code(text: String) -> ScannedCode {
    crate::domain::producer_card::classify_scanned_code(&text)
}

#[uniffi::export]
pub fn producer_card_url_from_payload(payload: String) -> String {
    crate::domain::producer_card::producer_card_url_from_payload(&payload)
}

#[uniffi::export]
pub fn producer_card_payload(card: ProducerCard) -> String {
    crate::domain::producer_card::producer_card_payload(&card)
}

#[uniffi::export]
pub fn producer_card_common(
    card: ProducerCard,
    my_oshi_ids: Vec<String>,
    my_attended: Vec<CardShowRef>,
) -> CardCommon {
    crate::domain::producer_card::producer_card_common(&card, &my_oshi_ids, &my_attended)
}

#[uniffi::export]
pub fn card_exchange_show_candidates(today: String, my_attended: Vec<CardShowRef>) -> Vec<String> {
    crate::domain::producer_card::card_exchange_show_candidates(&today, &my_attended)
}

#[uniffi::export]
pub fn card_case_sections(entries: Vec<CardCaseEntry>) -> Vec<CardCaseSection> {
    crate::domain::producer_card::card_case_sections(&entries)
}

#[uniffi::export]
pub fn card_link_kinds() -> Vec<CardLinkKindInfo> {
    crate::domain::producer_card::card_link_kinds()
}

#[uniffi::export]
pub fn normalize_card_link(link: CardLink) -> Option<CardLink> {
    crate::domain::producer_card::normalize_link(&link)
}

#[uniffi::export]
pub fn card_link_view(link: CardLink) -> CardLinkView {
    crate::domain::producer_card::card_link_view(&link)
}

#[uniffi::export]
pub fn card_link_from_url(url: String) -> Option<CardLink> {
    crate::domain::producer_card::card_link_from_url(&url)
}

#[uniffi::export]
pub fn producer_card_record_summary(
    today: String,
    attended: Vec<CardShowRef>,
) -> CardRecordSummary {
    crate::domain::producer_card::producer_card_record_summary(&today, &attended)
}

#[uniffi::export]
pub fn card_issued_label(issued_on: String) -> String {
    crate::domain::producer_card::card_issued_label(&issued_on)
}

/// 名刺の表 (91:55) の組み。`drawable_idol_ids` は端末が描ける担当の id。
#[uniffi::export]
pub fn producer_card_face(card: ProducerCard, drawable_idol_ids: Vec<String>) -> CardFace {
    crate::domain::producer_card::producer_card_face(&card, &drawable_idol_ids)
}

#[uniffi::export]
pub fn card_link_kind_key(kind: CardLinkKind) -> String {
    crate::domain::producer_card::card_link_kind_key(kind)
}

#[uniffi::export]
pub fn card_link_kind_from_key(key: String) -> Option<CardLinkKind> {
    crate::domain::producer_card::card_link_kind_from_key(&key)
}

#[uniffi::export]
pub fn card_links_to_json(links: Vec<CardLink>) -> String {
    crate::domain::producer_card::card_links_to_json(&links)
}

#[uniffi::export]
pub fn card_links_from_json(json: String) -> Vec<CardLink> {
    crate::domain::producer_card::card_links_from_json(&json)
}

#[uniffi::export]
pub fn card_file_type_info() -> CardFileTypeInfo {
    crate::domain::producer_card::card_file_type_info()
}

#[uniffi::export]
pub fn card_file_name(card: ProducerCard) -> String {
    crate::domain::producer_card::card_file_name(&card)
}

#[uniffi::export]
pub fn encode_card_file(payload: String, images: Vec<CardFileImage>) -> Option<Vec<u8>> {
    crate::domain::producer_card::encode_card_file(&payload, &images)
}

#[uniffi::export]
pub fn decode_card_file(bytes: Vec<u8>) -> Option<CardFileContents> {
    crate::domain::producer_card::decode_card_file(&bytes)
}

#[uniffi::export]
pub fn card_peer_tag(payload: String) -> String {
    crate::domain::producer_card::card_peer_tag(&payload)
}

#[uniffi::export]
pub fn card_invite_proof(payload: String) -> String {
    crate::domain::producer_card::card_invite_proof(&payload)
}

#[uniffi::export]
pub fn normalize_card_qr_url(raw: String) -> Option<String> {
    crate::domain::producer_card::normalize_card_qr_url(&raw)
}

#[uniffi::export]
pub fn card_qr_link_view(url: String) -> CardLinkView {
    crate::domain::producer_card::card_qr_link_view(&url)
}

#[uniffi::export]
pub fn card_name_fonts() -> Vec<CardNameFontInfo> {
    crate::domain::producer_card::card_name_fonts()
}

#[uniffi::export]
pub fn card_name_font_info(font: CardNameFont) -> CardNameFontInfo {
    crate::domain::producer_card::card_name_font_info(font)
}

#[uniffi::export]
pub fn card_designs() -> Vec<CardDesignInfo> {
    crate::domain::producer_card::card_designs()
}

#[uniffi::export]
pub fn card_design_info(design: CardDesign) -> CardDesignInfo {
    crate::domain::producer_card::card_design_info(design)
}

#[uniffi::export]
pub fn producer_card_display_design(card: ProducerCard, has_face_image: bool) -> CardDesignInfo {
    crate::domain::producer_card::producer_card_display_design(&card, has_face_image)
}

#[uniffi::export]
pub fn card_design_key(design: CardDesign) -> String {
    crate::domain::producer_card::card_design_key(design)
}

#[uniffi::export]
pub fn card_design_from_key(key: String) -> Option<CardDesign> {
    crate::domain::producer_card::card_design_from_key(&key)
}

#[uniffi::export]
pub fn card_x_avatar_handle(links: Vec<CardLink>) -> Option<String> {
    crate::domain::producer_card_avatar::card_x_avatar_handle(&links)
}

#[uniffi::export]
pub fn x_profile_api_url(handle: String) -> Option<String> {
    crate::domain::producer_card_avatar::x_profile_api_url(&handle)
}

#[uniffi::export]
pub fn x_avatar_lookup(handle: String, status: u16, body: String) -> XAvatarLookup {
    crate::domain::producer_card_avatar::x_avatar_lookup(&handle, status, &body)
}

#[uniffi::export]
pub fn x_avatar_lookup_message(lookup: XAvatarLookup, handle: String) -> Option<String> {
    crate::domain::producer_card_avatar::x_avatar_lookup_message(&lookup, &handle)
}
