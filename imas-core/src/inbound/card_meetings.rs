//! 受け取った P名刺の受け取り方・会った記録の FFI 面。ロジックは domain::card_meetings。

use crate::domain::card_meetings::{
    CardIncoming, CardMeetingRecord, CardMeetingView, CardReceivePlan, CardReceiveVia,
    CardSamePersonChoice, CardSamePersonConfirm, CardStoredRef,
};

#[uniffi::export]
pub fn card_receive_via_key(via: CardReceiveVia) -> String {
    crate::domain::card_meetings::card_receive_via_key(via)
}

/// 保存のキーから受け取り方を読む (知らないキー・空は不明)。
#[uniffi::export]
pub fn card_receive_via_from_key(key: String) -> Option<CardReceiveVia> {
    crate::domain::card_meetings::card_receive_via_from_key(&key)
}

/// 会場で交換した名刺の札 (「会場で交換」。札が無ければ None)。
#[uniffi::export]
pub fn card_meeting_badge(via: Option<CardReceiveVia>, show_id: Option<String>) -> Option<String> {
    crate::domain::card_meetings::card_meeting_badge(via, show_id.as_deref())
}

/// 会った記録を画面に出す形 (新しい順、人ごとに何回目か)。
#[uniffi::export]
pub fn card_meeting_views(meetings: Vec<CardMeetingRecord>) -> Vec<CardMeetingView> {
    crate::domain::card_meetings::card_meeting_views(&meetings)
}

/// 名刺を受け取ったときのしまい方 (同じ人の名刺があるか・確かめるか・会った記録を足すか・最後の記録の書き換え)。
#[uniffi::export]
pub fn card_receive_plan(
    incoming: CardIncoming,
    stored: Vec<CardStoredRef>,
    meetings: Vec<CardMeetingRecord>,
    match_same_person: bool,
    choice: CardSamePersonChoice,
) -> CardReceivePlan {
    crate::domain::card_meetings::card_receive_plan(
        &incoming,
        &stored,
        &meetings,
        match_same_person,
        choice,
    )
}

/// 同じ人か確かめる画面 (今ある名刺と届いた名刺の名前・リンク、選択肢の言葉)。
#[uniffi::export]
pub fn card_same_person_confirm(
    existing_payload: String,
    incoming_payload: String,
) -> Option<CardSamePersonConfirm> {
    crate::domain::card_meetings::card_same_person_confirm(&existing_payload, &incoming_payload)
}

/// 名刺の会った記録のうち最後のもの (受け取った名刺の行はこれを写して持つ)。
#[uniffi::export]
pub fn card_latest_meeting(meetings: Vec<CardMeetingRecord>, card_id: String) -> Option<CardMeetingRecord> {
    crate::domain::card_meetings::card_latest_meeting(&meetings, &card_id)
}

/// 会った記録の名刺に戻せるか (詳細の「この時の名刺に戻す」)。
#[uniffi::export]
pub fn card_meeting_restorable(meeting_payload: Option<String>, current_payload: String) -> bool {
    crate::domain::card_meetings::card_meeting_restorable(meeting_payload.as_deref(), &current_payload)
}

/// 会った記録の無い名刺の 1 回目の記録の id (移行とバックアップで同じ id にする)。
#[uniffi::export]
pub fn card_first_meeting_id(card_id: String) -> String {
    crate::domain::card_meetings::card_first_meeting_id(&card_id)
}
