//! 受け取った P名刺の受け取り方・会った記録の FFI 面。ロジックは domain::card_meetings。

use crate::domain::card_meetings::{
    CardMeetingRecord, CardMeetingView, CardReceivePlan, CardReceiveVia, CardStoredRef,
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

/// 名刺を受け取ったときのしまい方 (同じ人の名刺があるか・会った記録を足すか)。
#[uniffi::export]
pub fn card_receive_plan(
    incoming_payload: String,
    stored: Vec<CardStoredRef>,
    meetings: Vec<CardMeetingRecord>,
    show_id: Option<String>,
    met_at: String,
    match_same_person: bool,
) -> CardReceivePlan {
    crate::domain::card_meetings::card_receive_plan(
        &incoming_payload,
        &stored,
        &meetings,
        show_id.as_deref(),
        &met_at,
        match_same_person,
    )
}

/// 会った記録の無い名刺の 1 回目の記録の id (移行とバックアップで同じ id にする)。
#[uniffi::export]
pub fn card_first_meeting_id(card_id: String) -> String {
    crate::domain::card_meetings::card_first_meeting_id(&card_id)
}
