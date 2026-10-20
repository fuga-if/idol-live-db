//! すれちがいモードの FFI 面。ロジックは domain::streetpass。

use crate::domain::card_meetings::CardMeetingRecord;
use crate::domain::producer_card::CardShowRef;
use crate::domain::streetpass::{
    StreetpassFrames, StreetpassHeader, StreetpassRadio, StreetpassSeen, StreetpassStatus,
    StreetpassTuning, StreetpassUuids,
};

/// GATT のサービス・特性の UUID。
#[uniffi::export]
pub fn streetpass_uuids() -> StreetpassUuids {
    crate::domain::streetpass::streetpass_uuids()
}

/// 名刺の中身の指紋。
#[uniffi::export]
pub fn streetpass_fingerprint(payload: String) -> String {
    crate::domain::streetpass::streetpass_fingerprint(&payload)
}

/// 名刺の中身を特性に置く値にする (名乗れない中身は None)。
#[uniffi::export]
pub fn streetpass_frames(payload: String) -> Option<StreetpassFrames> {
    crate::domain::streetpass::streetpass_frames(&payload)
}

/// 見出しの特性の値を読む (読めなければ None)。
#[uniffi::export]
pub fn streetpass_header_decode(bytes: Vec<u8>) -> Option<StreetpassHeader> {
    crate::domain::streetpass::streetpass_header_decode(&bytes)
}

/// 読んだ欠片を名刺の中身に戻す (崩れていれば None)。
#[uniffi::export]
pub fn streetpass_join(header: StreetpassHeader, chunks: Vec<Vec<u8>>) -> Option<String> {
    crate::domain::streetpass::streetpass_join(&header, &chunks)
}

/// この指紋の名刺を読むか (自分の名刺・最近読んだ名刺は読まない)。
#[uniffi::export]
pub fn streetpass_should_read(
    fingerprint: String,
    own_fingerprint: Option<String>,
    recent: Vec<StreetpassSeen>,
    now: String,
) -> bool {
    crate::domain::streetpass::streetpass_should_read(&fingerprint, own_fingerprint.as_deref(), &recent, &now)
}

/// 読み直さない間を過ぎた「最近読んだ名刺」を落とす。
#[uniffi::export]
pub fn streetpass_prune_seen(recent: Vec<StreetpassSeen>, now: String) -> Vec<StreetpassSeen> {
    crate::domain::streetpass::streetpass_prune_seen(&recent, &now)
}

/// 今日 (JST) すれちがいで会った人数。
#[uniffi::export]
pub fn streetpass_today_count(meetings: Vec<CardMeetingRecord>, now: String) -> u32 {
    crate::domain::streetpass::streetpass_today_count(&meetings, &now)
}

/// オンのままか (オンにしてから決まった時間で自動でオフ)。
#[uniffi::export]
pub fn streetpass_is_active(started_at: Option<String>, now: String) -> bool {
    crate::domain::streetpass::streetpass_is_active(started_at.as_deref(), &now)
}

/// 今日の上限に届く前か。
#[uniffi::export]
pub fn streetpass_accepts(today_count: u32) -> bool {
    crate::domain::streetpass::streetpass_accepts(today_count)
}

/// 名刺入れの行に出す様子。
#[uniffi::export]
pub fn streetpass_status(
    active: bool,
    has_card: bool,
    today_count: u32,
    radio: StreetpassRadio,
) -> StreetpassStatus {
    crate::domain::streetpass::streetpass_status(active, has_card, today_count, radio)
}

/// すれちがいで受け取ったときの知らせの文言。
#[uniffi::export]
pub fn streetpass_notice_text(name: String) -> String {
    crate::domain::streetpass::streetpass_notice_text(&name)
}

/// 通信の段取りの数字 (繋ぎ直さない間・待ち行列・待ち時間)。
#[uniffi::export]
pub fn streetpass_tuning() -> StreetpassTuning {
    crate::domain::streetpass::streetpass_tuning()
}

/// しまった後に端末の知らせを出すか (今日はじめての人のときだけ)。
#[uniffi::export]
pub fn streetpass_should_notice(before: u32, after: u32) -> bool {
    crate::domain::streetpass::streetpass_should_notice(before, after)
}

/// すれちがいで受け取った名刺を紐づける公演 (今日の参加公演だけ)。`today` は JST の `YYYY-MM-DD`。
#[uniffi::export]
pub fn streetpass_show_candidate(today: String, my_attended: Vec<CardShowRef>) -> Option<String> {
    crate::domain::streetpass::streetpass_show_candidate(&today, &my_attended)
}
