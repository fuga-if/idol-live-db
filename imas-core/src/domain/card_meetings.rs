//! 受け取った P名刺の「どう受け取ったか」と「会った記録」。
//!
//! - 受け取り方 ([`CardReceiveVia`]): 近くの端末・カメラで QR を読んだ・名刺ファイル・リンク・紙の名刺。
//!   古い行 (足す前に受け取った名刺) は不明 (None)。
//! - 「会場で交換」の札 ([`card_meeting_badge`]): 近くの端末で受け取った、またはカメラで QR を読んで
//!   受け取った公演がある。名刺ファイル・リンク・紙の名刺は札なし (オンラインや後から入れたもの)。
//! - 同じ人 ([`card_receive_plan`]): 名刺 id (`ProducerCard::card_id`) が同じ名刺。id の無い名刺は
//!   中身が同じときだけ。同じ人の名刺は 1 枚にまとめ (中身は新しい方に)、会った記録を積む。
//!   同じ機会 (同じ公演、公演が無ければ同じ日) にもう一度読んだときは記録を足さない。
//! - 会った記録の並び・何回目か ([`card_meeting_views`]) もここ。
//!
//! 端末は行の出し入れだけをする (受け取った名刺の行は最後に会った記録を写して持つ)。

use std::collections::HashMap;

use crate::domain::producer_card::decode_producer_card;

/// 受け取り方。保存は [`card_receive_via_key`] の英字キー。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CardReceiveVia {
    /// 近くの端末から (iPhone の近距離・Android の Nearby)。
    Nearby,
    /// カメラで相手の画面の QR を読んだ。
    CameraQr,
    /// 名刺ファイルを開いた (メッセージなどで届いたもの)。
    File,
    /// 名刺のリンクを開いた。
    Link,
    /// 紙の名刺を撮って取り込んだ (写真から QR を読んだものも含む)。
    Paper,
}

/// 会場で交換した名刺に付ける札の文言。
pub const CARD_MET_IN_PERSON_LABEL: &str = "会場で交換";

pub fn card_receive_via_key(via: CardReceiveVia) -> String {
    match via {
        CardReceiveVia::Nearby => "nearby",
        CardReceiveVia::CameraQr => "camera_qr",
        CardReceiveVia::File => "file",
        CardReceiveVia::Link => "link",
        CardReceiveVia::Paper => "paper",
    }
    .to_string()
}

/// 保存のキーから読む。知らないキー・空は不明 (None)。
pub fn card_receive_via_from_key(key: &str) -> Option<CardReceiveVia> {
    Some(match key {
        "nearby" => CardReceiveVia::Nearby,
        "camera_qr" => CardReceiveVia::CameraQr,
        "file" => CardReceiveVia::File,
        "link" => CardReceiveVia::Link,
        "paper" => CardReceiveVia::Paper,
        _ => return None,
    })
}

/// 受け取り方の短い言い方 (会った記録の行に添える)。
pub fn card_receive_via_label(via: CardReceiveVia) -> String {
    match via {
        CardReceiveVia::Nearby => "近くの端末で受け取り",
        CardReceiveVia::CameraQr => "QR を読んで受け取り",
        CardReceiveVia::File => "名刺ファイルで受け取り",
        CardReceiveVia::Link => "リンクで受け取り",
        CardReceiveVia::Paper => "紙の名刺を取り込み",
    }
    .to_string()
}

/// 会場で会って交換したか。近くの端末で受け取った、またはカメラで QR を読んで受け取った公演がある。
pub fn card_met_in_person(via: Option<CardReceiveVia>, show_id: Option<&str>) -> bool {
    let has_show = show_id.is_some_and(|s| !s.is_empty());
    match via {
        Some(CardReceiveVia::Nearby) => true,
        Some(CardReceiveVia::CameraQr) => has_show,
        _ => false,
    }
}

/// 会場で交換した名刺の札 (会場で交換していなければ None)。
pub fn card_meeting_badge(via: Option<CardReceiveVia>, show_id: Option<&str>) -> Option<String> {
    card_met_in_person(via, show_id).then(|| CARD_MET_IN_PERSON_LABEL.to_string())
}

/// 会った記録 1 つ (端末の `received_card_meetings` の行)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardMeetingRecord {
    pub id: String,
    /// 受け取った名刺の行の id。
    pub card_id: String,
    pub show_id: Option<String>,
    /// 公演の日付 (`YYYY-MM-DD`)。
    pub show_date: Option<String>,
    /// 受け取り方の保存のキー ([`card_receive_via_key`])。None は不明。
    pub via: Option<String>,
    /// 受け取った日時 (ISO 8601)。
    pub met_at: String,
}

/// 画面に出す会った記録 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardMeetingView {
    pub id: String,
    pub card_id: String,
    pub show_id: Option<String>,
    pub show_date: Option<String>,
    pub met_at: String,
    /// 受け取り方の言い方 (不明なら None)。
    pub via_label: Option<String>,
    /// 「会場で交換」の札 ([`card_meeting_badge`])。
    pub badge: Option<String>,
    /// その人と会った何回目か (1 から、古い順に数える)。
    pub ordinal: u32,
    /// 2 回目からの「2回目」(1 回目は None)。
    pub ordinal_label: Option<String>,
}

fn non_empty(s: &Option<String>) -> Option<&str> {
    s.as_deref().filter(|v| !v.is_empty())
}

/// 会った記録を画面に出す形にする。新しい順 (同じ時刻は id の順) に並べ、人ごとに古い順で何回目かを数える。
pub fn card_meeting_views(meetings: &[CardMeetingRecord]) -> Vec<CardMeetingView> {
    let mut chronological: Vec<&CardMeetingRecord> = meetings.iter().collect();
    chronological.sort_by(|a, b| a.met_at.cmp(&b.met_at).then_with(|| a.id.cmp(&b.id)));
    let mut counts: HashMap<&str, u32> = HashMap::new();
    let mut views: Vec<CardMeetingView> = chronological
        .into_iter()
        .map(|m| {
            let n = counts.entry(m.card_id.as_str()).or_insert(0);
            *n += 1;
            let via = m.via.as_deref().and_then(card_receive_via_from_key);
            CardMeetingView {
                id: m.id.clone(),
                card_id: m.card_id.clone(),
                show_id: non_empty(&m.show_id).map(str::to_string),
                show_date: non_empty(&m.show_date).map(str::to_string),
                met_at: m.met_at.clone(),
                via_label: via.map(card_receive_via_label),
                badge: card_meeting_badge(via, non_empty(&m.show_id)),
                ordinal: *n,
                ordinal_label: (*n >= 2).then(|| format!("{n}回目")),
            }
        })
        .collect();
    views.sort_by(|a, b| b.met_at.cmp(&a.met_at).then_with(|| a.id.cmp(&b.id)));
    views
}

/// 名刺入れにある名刺 1 枚 (同じ人を探す材料)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardStoredRef {
    pub id: String,
    /// 名刺の中身 (`#` の後ろ)。
    pub payload: String,
}

/// 名刺を受け取ったときのしまい方。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardReceivePlan {
    /// 同じ人の名刺が名刺入れにあればその id (中身を新しい方に替え、会った記録を積む)。None は新しく足す。
    pub existing_card_id: Option<String>,
    /// 会った記録を足すか (同じ機会にもう一度読んだときは足さない)。
    pub add_meeting: bool,
}

/// 届いた名刺と同じ人の名刺を探す。名刺 id があれば id で、無ければ中身が同じもの。
pub fn card_find_same_person(incoming_payload: &str, stored: &[CardStoredRef]) -> Option<String> {
    let incoming_id = decode_producer_card(incoming_payload).and_then(|c| c.card_id);
    if let Some(id) = incoming_id {
        if let Some(found) = stored.iter().find(|s| {
            decode_producer_card(&s.payload)
                .and_then(|c| c.card_id)
                .is_some_and(|other| other == id)
        }) {
            return Some(found.id.clone());
        }
    }
    stored
        .iter()
        .find(|s| s.payload == incoming_payload)
        .map(|s| s.id.clone())
}

/// ISO 8601 の日時の JST の日付 (`YYYY-MM-DD`)。読めなければ先頭 10 文字。
fn jst_day(at: &str) -> String {
    chrono::DateTime::parse_from_rfc3339(at)
        .map(|t| {
            (t.with_timezone(&chrono::Utc) + chrono::Duration::hours(9))
                .format("%Y-%m-%d")
                .to_string()
        })
        .unwrap_or_else(|_| at.chars().take(10).collect())
}

/// 2 つの記録が同じ機会か (同じ公演、公演がどちらにも無ければ同じ日)。
fn same_occasion(last: &CardMeetingRecord, show_id: Option<&str>, met_at: &str) -> bool {
    match (non_empty(&last.show_id), show_id.filter(|s| !s.is_empty())) {
        (Some(a), Some(b)) => a == b,
        (None, None) => jst_day(&last.met_at) == jst_day(met_at),
        _ => false,
    }
}

/// 名刺を受け取ったときのしまい方を決める。`match_same_person` が false (QR の無い紙の名刺。名前だけで
/// 中身を作るので同じ名前の別人と重ねない) なら常に新しく足す。
pub fn card_receive_plan(
    incoming_payload: &str,
    stored: &[CardStoredRef],
    meetings: &[CardMeetingRecord],
    show_id: Option<&str>,
    met_at: &str,
    match_same_person: bool,
) -> CardReceivePlan {
    let existing = match_same_person
        .then(|| card_find_same_person(incoming_payload, stored))
        .flatten();
    let Some(existing) = existing else {
        return CardReceivePlan {
            existing_card_id: None,
            add_meeting: true,
        };
    };
    let last = meetings
        .iter()
        .filter(|m| m.card_id == existing)
        .max_by(|a, b| a.met_at.cmp(&b.met_at).then_with(|| a.id.cmp(&b.id)));
    let add_meeting = !last.is_some_and(|l| same_occasion(l, show_id, met_at));
    CardReceivePlan {
        existing_card_id: Some(existing),
        add_meeting,
    }
}

/// 会った記録が 1 つも無い名刺 (足す前に受け取った名刺・古いバックアップ) の 1 回目の記録の id。
/// 端末の移行とバックアップの取り込みで同じ id にして、2 回入れても 1 つにする。
pub fn card_first_meeting_id(card_id: &str) -> String {
    format!("m_{card_id}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::producer_card::{
        encode_producer_card, producer_card_new_id, producer_card_payload, ProducerCardInput,
    };

    fn payload(name: &str, card_id: Option<&str>) -> String {
        let enc = encode_producer_card(&ProducerCardInput {
            name: name.into(),
            message: String::new(),
            since_year: None,
            oshi_idol_ids: vec![],
            links: vec![],
            show_count: None,
            song_count: None,
            next_show_id: None,
            attended: vec![],
            issued_on: "2026-10-09".into(),
            design: None,
            qr_url: None,
            show_brand_labels: false,
            card_id: card_id.map(str::to_string),
        });
        producer_card_payload(&enc.card)
    }

    fn meeting(id: &str, card: &str, show: Option<&str>, via: Option<&str>, at: &str) -> CardMeetingRecord {
        CardMeetingRecord {
            id: id.into(),
            card_id: card.into(),
            show_id: show.map(str::to_string),
            show_date: show.map(|_| "2026-10-05".to_string()),
            via: via.map(str::to_string),
            met_at: at.into(),
        }
    }

    #[test]
    fn via_keys_round_trip_and_unknown_is_none() {
        for via in [
            CardReceiveVia::Nearby,
            CardReceiveVia::CameraQr,
            CardReceiveVia::File,
            CardReceiveVia::Link,
            CardReceiveVia::Paper,
        ] {
            assert_eq!(card_receive_via_from_key(&card_receive_via_key(via)), Some(via));
        }
        assert_eq!(card_receive_via_from_key(""), None);
        assert_eq!(card_receive_via_from_key("bluetooth"), None);
    }

    #[test]
    fn in_person_is_nearby_or_camera_with_a_show() {
        use CardReceiveVia::*;
        assert!(card_met_in_person(Some(Nearby), None));
        assert!(card_met_in_person(Some(CameraQr), Some("sh_1")));
        assert!(!card_met_in_person(Some(CameraQr), None));
        assert!(!card_met_in_person(Some(CameraQr), Some("")));
        for online in [File, Link, Paper] {
            assert!(!card_met_in_person(Some(online), Some("sh_1")));
        }
        assert!(!card_met_in_person(None, Some("sh_1")), "古い行 (不明) は札なし");
        assert_eq!(card_meeting_badge(Some(Nearby), None).as_deref(), Some("会場で交換"));
    }

    #[test]
    fn same_person_is_found_by_card_id_then_by_identical_payload() {
        let id = producer_card_new_id("0123456789abcdef0123456789abcdef");
        let old = payload("ふがP", Some(&id));
        let renamed = payload("ふがP@現地", Some(&id));
        let other = payload("しろくまP", Some(&producer_card_new_id("ffffffffffffffff")));
        let legacy = payload("あおいP", None);
        let stored = vec![
            CardStoredRef { id: "c1".into(), payload: old },
            CardStoredRef { id: "c2".into(), payload: other },
            CardStoredRef { id: "c3".into(), payload: legacy.clone() },
        ];
        assert_eq!(card_find_same_person(&renamed, &stored).as_deref(), Some("c1"), "名前を変えても同じ id なら同じ人");
        assert_eq!(card_find_same_person(&legacy, &stored).as_deref(), Some("c3"), "id の無い名刺は中身が同じなら");
        assert_eq!(card_find_same_person(&payload("あおいP2", None), &stored), None);
    }

    #[test]
    fn plan_adds_a_meeting_unless_it_is_the_same_occasion() {
        let id = producer_card_new_id("0123456789abcdef");
        let stored = vec![CardStoredRef { id: "c1".into(), payload: payload("ふがP", Some(&id)) }];
        let again = payload("ふがP", Some(&id));
        let meetings = vec![meeting("m1", "c1", Some("sh_1"), Some("camera_qr"), "2026-10-05T10:00:00Z")];

        let new_card = card_receive_plan(&payload("別人", None), &stored, &meetings, Some("sh_1"), "2026-10-05T11:00:00Z", true);
        assert_eq!(new_card, CardReceivePlan { existing_card_id: None, add_meeting: true });

        let same_show = card_receive_plan(&again, &stored, &meetings, Some("sh_1"), "2026-10-05T12:00:00Z", true);
        assert_eq!(same_show, CardReceivePlan { existing_card_id: Some("c1".into()), add_meeting: false });

        let next_show = card_receive_plan(&again, &stored, &meetings, Some("sh_2"), "2026-12-01T12:00:00Z", true);
        assert_eq!(next_show, CardReceivePlan { existing_card_id: Some("c1".into()), add_meeting: true });

        // 公演が無ければ JST の同じ日だけ同じ機会 (UTC 15 時は JST の翌日)。
        let no_show = vec![meeting("m1", "c1", None, Some("link"), "2026-10-05T10:00:00Z")];
        assert!(!card_receive_plan(&again, &stored, &no_show, None, "2026-10-05T14:00:00Z", true).add_meeting);
        assert!(card_receive_plan(&again, &stored, &no_show, None, "2026-10-05T15:30:00Z", true).add_meeting);

        // QR の無い紙の名刺は同じ人を探さない。
        let paper = card_receive_plan(&again, &stored, &meetings, Some("sh_1"), "2026-10-05T12:00:00Z", false);
        assert_eq!(paper.existing_card_id, None);
    }

    #[test]
    fn meeting_views_are_newest_first_and_count_per_person() {
        let views = card_meeting_views(&[
            meeting("a2", "A", Some("sh_2"), Some("nearby"), "2026-12-01T10:00:00Z"),
            meeting("a1", "A", Some("sh_1"), Some("camera_qr"), "2026-10-05T10:00:00Z"),
            meeting("b1", "B", None, Some("link"), "2026-11-01T10:00:00Z"),
            meeting("a0", "A", None, None, "2026-09-01T10:00:00Z"),
        ]);
        let ids: Vec<&str> = views.iter().map(|v| v.id.as_str()).collect();
        assert_eq!(ids, vec!["a2", "b1", "a1", "a0"]);
        assert_eq!(views[0].ordinal, 3);
        assert_eq!(views[0].ordinal_label.as_deref(), Some("3回目"));
        assert_eq!(views[0].badge.as_deref(), Some("会場で交換"));
        assert_eq!(views[1].ordinal_label, None);
        assert_eq!(views[1].badge, None, "リンクは札なし");
        assert_eq!(views[1].via_label.as_deref(), Some("リンクで受け取り"));
        assert_eq!(views[3].via_label, None, "古い行は受け取り方が不明");
        assert_eq!(views[3].badge, None);
    }
}
