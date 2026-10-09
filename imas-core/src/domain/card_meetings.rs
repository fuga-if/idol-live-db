//! 受け取った P名刺の「どう受け取ったか」と「会った記録」。
//!
//! - 受け取り方 ([`CardReceiveVia`]): 近くの端末・カメラで QR を読んだ・名刺ファイル・リンク・紙の名刺。
//!   古い行 (足す前に受け取った名刺) は不明 (None)。
//! - 「会場で交換」の札 ([`card_meeting_badge`]): 近くの端末で受け取った、またはカメラで QR を読んで
//!   受け取った公演がある。名刺ファイル・リンク・紙の名刺は札なし (オンラインや後から入れたもの)。
//! - 同じ人 ([`card_receive_plan`]): 中身が同じ名刺、名刺 id (`ProducerCard::card_id`) が同じで名前も同じ名刺は
//!   黙って 1 枚にまとめる (中身は新しい方に)。名刺 id が同じで名前が違う名刺 (他人の id を名乗った名刺かもしれない)、
//!   id の無い名刺で名前と担当が同じで中身が違う名刺は、受け取る人に確かめる ([`card_same_person_confirm`]。
//!   既定は別の名刺として残す)。同じ人の名刺には会った記録を積む。
//!   同じ機会 (同じ公演、どちらかに公演が無ければ JST の同じ日) に同じ中身をもう一度読んだときは記録を足さず、
//!   会場で交換したなら最後の記録の受け取り方を上げる。中身が違えば同じ機会でも記録を積む (前の中身を残す)。
//! - 会った記録はそのときの名刺の中身を持ち、詳細から「この時の名刺に戻す」ができる ([`card_meeting_restorable`])。
//! - 会った記録の並び・何回目か ([`card_meeting_views`])・最後の記録 ([`card_latest_meeting`]) もここ。
//!
//! 端末は行の出し入れだけをする (受け取った名刺の行は最後に会った記録の公演・受け取り方・日時・中身を写して持つ)。
//!
//! 名刺 id を名刺に載せるかは `producer_card::PRODUCER_CARD_EMBEDS_CARD_ID` の 1 か所で開閉する
//! (公開中の 2.5.0 は id 入りの名刺を読めないので、今は載せない)。載せない間は「中身が同じ」
//! 「名前と担当が同じ (確かめる)」で同じ人を見分ける。

use std::collections::HashMap;

use crate::domain::producer_card::{
    card_link_view, card_qr_link_view, decode_producer_card, CardLinkView, ProducerCard,
};

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
    /// そのとき受け取った名刺の中身 (`#` の後ろ)。足す前の記録は None。
    #[uniffi(default = None)]
    pub payload: Option<String>,
}

/// 画面に出す会った記録 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardMeetingView {
    pub id: String,
    pub card_id: String,
    pub show_id: Option<String>,
    pub show_date: Option<String>,
    pub met_at: String,
    /// 半券に刷る日付 (`YYYY-MM-DD`)。公演があれば公演の日、無ければ受け取った日 (JST)。
    pub date: String,
    /// 受け取り方の言い方 (不明なら None)。
    pub via_label: Option<String>,
    /// 「会場で交換」の札 ([`card_meeting_badge`])。
    pub badge: Option<String>,
    /// その人と会った何回目か (1 から、古い順に数える)。
    pub ordinal: u32,
    /// 2 回目からの「2回目」(1 回目は None)。
    pub ordinal_label: Option<String>,
    /// そのとき受け取った名刺の中身 (足す前の記録は None)。
    pub payload: Option<String>,
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
                date: non_empty(&m.show_date)
                    .map(str::to_string)
                    .unwrap_or_else(|| jst_day(&m.met_at)),
                via_label: via.map(card_receive_via_label),
                badge: card_meeting_badge(via, non_empty(&m.show_id)),
                ordinal: *n,
                ordinal_label: (*n >= 2).then(|| format!("{n}回目")),
                payload: m.payload.clone(),
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

/// 同じ人かもしれない名刺を、受け取る人がどうしたか。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CardSamePersonChoice {
    /// まだ選んでいない。確かめる名刺は別の名刺として足す (黙って中身を差し替えない)。
    Undecided,
    /// 同じ人として今ある名刺を新しい方に替える。
    SamePerson,
    /// 別の名刺として残す。
    Separate,
}

/// 名刺を受け取ったときのしまい方。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardReceivePlan {
    /// まとめる名刺 (同じ人の名刺) の id。中身を新しい方に替え、会った記録を積む。None は新しく足す。
    pub existing_card_id: Option<String>,
    /// 会った記録を足すか (同じ機会にもう一度読んだときは足さない)。
    pub add_meeting: bool,
    /// 同じ人か受け取る人に確かめる名刺の id ([`CardSamePersonChoice::Undecided`] のときだけ)。
    /// 確認の画面は [`card_same_person_confirm`]。このまま書くと別の名刺として足す。
    pub confirm_card_id: Option<String>,
    /// 同じ機会にもう一度読んだとき、最後の会った記録をこの形に書き換える (中身を新しい方に、
    /// 会場で交換したなら受け取り方を上げる)。書き換えが要らなければ None。
    pub last_meeting_update: Option<CardMeetingRecord>,
}

/// 届いた名刺と今ある名刺がどのくらい同じ人らしいか。
enum SamePerson {
    /// 中身が同じ、または名刺 id と名前が同じ。黙ってまとめる。
    Certain(String),
    /// 名刺 id が同じで名前が違う、または id の無い名刺で名前と担当が同じ。確かめる。
    Ask(String),
}

fn same_identity(a: &ProducerCard, b: &ProducerCard) -> bool {
    a.name.trim() == b.name.trim() && a.oshi_idol_ids == b.oshi_idol_ids
}

/// 届いた名刺と同じ人の名刺を探す。
fn find_same_person(incoming_payload: &str, stored: &[CardStoredRef]) -> Option<SamePerson> {
    if let Some(found) = stored.iter().find(|s| s.payload == incoming_payload) {
        return Some(SamePerson::Certain(found.id.clone()));
    }
    let incoming = decode_producer_card(incoming_payload)?;
    let decoded: Vec<(&CardStoredRef, ProducerCard)> = stored
        .iter()
        .filter_map(|s| decode_producer_card(&s.payload).map(|c| (s, c)))
        .collect();
    if let Some(id) = incoming.card_id.as_deref() {
        let same_id: Vec<&(&CardStoredRef, ProducerCard)> = decoded
            .iter()
            .filter(|(_, c)| c.card_id.as_deref() == Some(id))
            .collect();
        // 同じ id の名刺を別の名刺として残していたら、名前が同じ方にまとめる。
        if let Some((s, _)) = same_id
            .iter()
            .find(|(_, c)| c.name.trim() == incoming.name.trim())
        {
            return Some(SamePerson::Certain(s.id.clone()));
        }
        if let Some((s, _)) = same_id.first() {
            return Some(SamePerson::Ask(s.id.clone()));
        }
    }
    // 名前と担当が同じ名刺 (どちらも id を持っていて違うなら別の人)。
    decoded
        .iter()
        .find(|(_, c)| {
            let ids_conflict = matches!((&c.card_id, &incoming.card_id), (Some(a), Some(b)) if a != b);
            !ids_conflict && same_identity(c, &incoming)
        })
        .map(|(s, _)| SamePerson::Ask(s.id.clone()))
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

/// 2 つの記録が同じ機会か。どちらにも公演があれば同じ公演、どちらかに公演が無ければ JST の同じ日
/// (会場で公演を選ばずに読み、後で公演を選んで読み直しても 1 回と数える)。
pub(crate) fn same_occasion(last: &CardMeetingRecord, show_id: Option<&str>, met_at: &str) -> bool {
    match (non_empty(&last.show_id), show_id.filter(|s| !s.is_empty())) {
        (Some(a), Some(b)) => a == b,
        _ => jst_day(&last.met_at) == jst_day(met_at),
    }
}

/// 名刺の会った記録のうち最後のもの (日時、同じ時刻は id の大きい方)。受け取った名刺の行はこれを写して持つ
/// (公演・受け取り方・日時・中身)。
pub fn card_latest_meeting(meetings: &[CardMeetingRecord], card_id: &str) -> Option<CardMeetingRecord> {
    meetings
        .iter()
        .filter(|m| m.card_id == card_id)
        .max_by(|a, b| a.met_at.cmp(&b.met_at).then_with(|| a.id.cmp(&b.id)))
        .cloned()
}

/// 同じ機会にもう一度読んだときの、最後の記録の書き換え。中身は新しい方に、新しい方が会場での交換に
/// 当たり最後の記録が当たらなければ受け取り方を上げる (公演が無ければ新しい方の公演も写す)。
fn refresh_last_meeting(
    last: &CardMeetingRecord,
    incoming_payload: &str,
    show_id: Option<&str>,
    show_date: Option<&str>,
    via: Option<CardReceiveVia>,
) -> Option<CardMeetingRecord> {
    let mut updated = last.clone();
    updated.payload = Some(incoming_payload.to_string());
    let last_via = last.via.as_deref().and_then(card_receive_via_from_key);
    let new_show = show_id.filter(|s| !s.is_empty());
    if card_met_in_person(via, new_show) && !card_met_in_person(last_via, non_empty(&last.show_id)) {
        updated.via = via.map(card_receive_via_key);
        if non_empty(&last.show_id).is_none() {
            updated.show_id = new_show.map(str::to_string);
            updated.show_date = show_date.filter(|s| !s.is_empty()).map(str::to_string);
        }
    }
    (updated != *last).then_some(updated)
}

/// 届いた名刺 1 枚の材料。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardIncoming {
    /// 名刺の中身 (`#` の後ろ)。
    pub payload: String,
    pub show_id: Option<String>,
    pub show_date: Option<String>,
    pub via: Option<CardReceiveVia>,
    /// 受け取った日時 (ISO 8601)。
    pub met_at: String,
}

/// 名刺を受け取ったときのしまい方を決める。`match_same_person` が false (QR の無い紙の名刺。名前だけで
/// 中身を作るので同じ名前の別人と重ねない) なら常に新しく足す。
pub fn card_receive_plan(
    incoming: &CardIncoming,
    stored: &[CardStoredRef],
    meetings: &[CardMeetingRecord],
    match_same_person: bool,
    choice: CardSamePersonChoice,
) -> CardReceivePlan {
    let fresh = CardReceivePlan {
        existing_card_id: None,
        add_meeting: true,
        confirm_card_id: None,
        last_meeting_update: None,
    };
    let found = match_same_person
        .then(|| find_same_person(&incoming.payload, stored))
        .flatten();
    let existing = match (found, choice) {
        (None, _) => return fresh,
        (Some(SamePerson::Certain(id)), _) => id,
        (Some(SamePerson::Ask(id)), CardSamePersonChoice::SamePerson) => id,
        (Some(SamePerson::Ask(_)), CardSamePersonChoice::Separate) => return fresh,
        (Some(SamePerson::Ask(id)), CardSamePersonChoice::Undecided) => {
            return CardReceivePlan {
                confirm_card_id: Some(id),
                ..fresh
            }
        }
    };
    let show_id = incoming.show_id.as_deref();
    let last = card_latest_meeting(meetings, &existing);
    // 同じ機会でも、最後の記録の中身と違う名刺なら記録を積む (前の中身を記録に残し、「この時の名刺に戻す」で戻せるように)。
    let (add_meeting, last_meeting_update) = match last {
        Some(l)
            if same_occasion(&l, show_id, &incoming.met_at)
                && l.payload.as_deref().is_none_or(|p| p == incoming.payload) =>
        (
            false,
            refresh_last_meeting(
                &l,
                &incoming.payload,
                show_id,
                incoming.show_date.as_deref(),
                incoming.via,
            ),
        ),
        _ => (true, None),
    };
    CardReceivePlan {
        existing_card_id: Some(existing),
        add_meeting,
        confirm_card_id: None,
        last_meeting_update,
    }
}

/// 同じ人か確かめる画面の片側 (今ある名刺・届いた名刺)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardSamePersonSide {
    /// 「今ある名刺」「届いた名刺」。
    pub label: String,
    pub name: String,
    /// リンク (自分の QR も 1 本として末尾に)。
    pub links: Vec<CardLinkView>,
}

/// 同じ人か確かめる画面 (受け取りの確認に出す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardSamePersonConfirm {
    /// 「すでにある ○○ さんの名刺と同じ人として受け取ろうとしています」。
    pub title: String,
    /// なぜ確かめるか (名刺 id が同じで名前が違う・名前と担当が同じで中身が違う)。
    pub reason: String,
    pub before: CardSamePersonSide,
    pub after: CardSamePersonSide,
    /// 選択肢の言葉。
    pub same_person_label: String,
    pub same_person_note: String,
    pub separate_label: String,
    pub separate_note: String,
}

fn confirm_side(label: &str, card: &ProducerCard) -> CardSamePersonSide {
    let mut links: Vec<CardLinkView> = card.links.iter().map(card_link_view).collect();
    if let Some(url) = &card.qr_url {
        links.push(card_qr_link_view(url));
    }
    CardSamePersonSide {
        label: label.to_string(),
        name: card.name.clone(),
        links,
    }
}

/// 同じ人か確かめる画面を組む。どちらかが読めなければ None。
pub fn card_same_person_confirm(
    existing_payload: &str,
    incoming_payload: &str,
) -> Option<CardSamePersonConfirm> {
    let before = decode_producer_card(existing_payload)?;
    let after = decode_producer_card(incoming_payload)?;
    let same_id = before.card_id.is_some() && before.card_id == after.card_id;
    let reason = if same_id {
        "名刺 id が同じで、名前が違います。名前を変えた同じ人か、ほかの人の名刺 id を名乗った名刺です。"
    } else {
        "名前と担当が同じで、中身が違います。名刺を作り直した同じ人か、同じ名前の別の人です。"
    };
    Some(CardSamePersonConfirm {
        title: format!(
            "すでにある {} さんの名刺と同じ人として受け取ろうとしています",
            before.name
        ),
        reason: reason.to_string(),
        before: confirm_side("今ある名刺", &before),
        after: confirm_side("届いた名刺", &after),
        same_person_label: "同じ人として更新".to_string(),
        same_person_note: "今ある名刺の中身と画像を届いた名刺に替え、会った記録を積みます。前の中身は会った記録から戻せます。"
            .to_string(),
        separate_label: "別の名刺として残す".to_string(),
        separate_note: "今ある名刺はそのままにして、届いた名刺を新しく名刺入れに入れます。".to_string(),
    })
}

/// 会った記録の名刺に戻せるか (そのときの中身があり、今の中身と違う)。
pub fn card_meeting_restorable(meeting_payload: Option<&str>, current_payload: &str) -> bool {
    meeting_payload.is_some_and(|p| !p.is_empty() && p != current_payload && decode_producer_card(p).is_some())
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
        encode_producer_card, producer_card_new_id, producer_card_payload, CardLink, CardLinkKind,
        ProducerCardInput,
    };
    use CardSamePersonChoice::*;

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
            payload: None,
        }
    }

    fn payload_with(name: &str, card_id: Option<&str>, oshi: &[&str], message: &str) -> String {
        let enc = encode_producer_card(&ProducerCardInput {
            name: name.into(),
            message: message.into(),
            since_year: None,
            oshi_idol_ids: oshi.iter().map(|s| s.to_string()).collect(),
            links: vec![CardLink { kind: CardLinkKind::X, value: format!("user{}", name.len()) }],
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

    fn incoming(payload: &str, show: Option<&str>, via: Option<CardReceiveVia>, at: &str) -> CardIncoming {
        CardIncoming {
            payload: payload.into(),
            show_id: show.map(str::to_string),
            show_date: show.map(|_| "2026-10-05".to_string()),
            via,
            met_at: at.into(),
        }
    }

    fn plan(
        inc: &CardIncoming,
        stored: &[CardStoredRef],
        meetings: &[CardMeetingRecord],
        choice: CardSamePersonChoice,
    ) -> CardReceivePlan {
        card_receive_plan(inc, stored, meetings, true, choice)
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
    fn same_person_by_payload_or_id_and_name_is_merged_silently() {
        let id = producer_card_new_id("0123456789abcdef0123456789abcdef");
        let old = payload_with("ふがP", Some(&id), &["i1"], "はじめまして");
        let edited = payload_with("ふがP", Some(&id), &["i2"], "リンクを変えた");
        let legacy = payload("あおいP", None);
        let stored = vec![
            CardStoredRef { id: "c1".into(), payload: old },
            CardStoredRef { id: "c3".into(), payload: legacy.clone() },
        ];
        let at = "2026-10-05T10:00:00Z";
        // 名刺 id と名前が同じなら、中身が違っても黙って更新。
        let p = plan(&incoming(&edited, None, None, at), &stored, &[], Undecided);
        assert_eq!(p.existing_card_id.as_deref(), Some("c1"));
        assert_eq!(p.confirm_card_id, None);
        // 中身が同じなら id が無くても同じ人。
        let p = plan(&incoming(&legacy, None, None, at), &stored, &[], Undecided);
        assert_eq!(p.existing_card_id.as_deref(), Some("c3"));
        // 名前も担当も違えば別の人。
        let p = plan(&incoming(&payload("あおいP2", None), None, None, at), &stored, &[], Undecided);
        assert_eq!(p, CardReceivePlan { existing_card_id: None, add_meeting: true, confirm_card_id: None, last_meeting_update: None });
    }

    /// 他人の名刺 id を名乗った名刺 (id が同じで名前が違う) は黙って差し替えない。確かめ、既定は別の名刺。
    #[test]
    fn spoofed_card_id_needs_confirmation_and_defaults_to_a_separate_card() {
        let id = producer_card_new_id("0123456789abcdef");
        let stored = vec![CardStoredRef { id: "c1".into(), payload: payload_with("ふがP", Some(&id), &["i1"], "") }];
        let spoof = payload_with("なりすましP", Some(&id), &["i1"], "");
        let inc = incoming(&spoof, Some("sh_1"), Some(CardReceiveVia::Nearby), "2026-10-05T10:00:00Z");

        let ask = plan(&inc, &stored, &[], Undecided);
        assert_eq!(ask.confirm_card_id.as_deref(), Some("c1"));
        assert_eq!(ask.existing_card_id, None, "選ばずに書いたら別の名刺として足す");
        assert!(ask.add_meeting);

        let same = plan(&inc, &stored, &[], SamePerson);
        assert_eq!((same.existing_card_id.as_deref(), same.confirm_card_id), (Some("c1"), None));
        let separate = plan(&inc, &stored, &[], Separate);
        assert_eq!((separate.existing_card_id, separate.confirm_card_id), (None, None));

        // 別の名刺として残した後は、同じ id でも名前が同じ方に黙ってまとめる。
        let both = vec![stored[0].clone(), CardStoredRef { id: "c2".into(), payload: spoof.clone() }];
        let again = payload_with("なりすましP", Some(&id), &["i1"], "2 枚目");
        let p = plan(&incoming(&again, None, None, "2026-12-01T10:00:00Z"), &both, &[], Undecided);
        assert_eq!((p.existing_card_id.as_deref(), p.confirm_card_id), (Some("c2"), None));

        let confirm = card_same_person_confirm(&stored[0].payload, &spoof).expect("読める");
        assert_eq!(confirm.title, "すでにある ふがP さんの名刺と同じ人として受け取ろうとしています");
        assert_eq!(confirm.before.name, "ふがP");
        assert_eq!(confirm.after.name, "なりすましP");
        assert_eq!(confirm.before.links[0].display, "@user7");
        assert_eq!(confirm.after.links[0].display, "@user16");
        assert!(confirm.reason.starts_with("名刺 id が同じ"));
        assert_eq!(confirm.same_person_label, "同じ人として更新");
        assert_eq!(confirm.separate_label, "別の名刺として残す");
    }

    /// 名刺 id を載せない間 (今) は、名前と担当が同じで中身が違う名刺を確かめる。
    #[test]
    fn without_card_id_same_name_and_oshi_needs_confirmation() {
        let stored = vec![CardStoredRef { id: "c1".into(), payload: payload_with("ふがP", None, &["i1", "i2"], "前") }];
        let edited = payload_with("ふがP", None, &["i1", "i2"], "後");
        let p = plan(&incoming(&edited, None, None, "2026-12-01T10:00:00Z"), &stored, &[], Undecided);
        assert_eq!((p.existing_card_id, p.confirm_card_id.as_deref()), (None, Some("c1")));
        let confirm = card_same_person_confirm(&stored[0].payload, &edited).unwrap();
        assert!(confirm.reason.starts_with("名前と担当が同じ"));
        // 担当が違えば別の人。
        let other = payload_with("ふがP", None, &["i3"], "後");
        assert_eq!(plan(&incoming(&other, None, None, "2026-12-01T10:00:00Z"), &stored, &[], Undecided).confirm_card_id, None);
        // どちらも id を持っていて違えば、名前と担当が同じでも別の人。
        let a = producer_card_new_id("aaaaaaaaaaaaaaaa");
        let b = producer_card_new_id("bbbbbbbbbbbbbbbb");
        let stored = vec![CardStoredRef { id: "c1".into(), payload: payload_with("ふがP", Some(&a), &["i1"], "") }];
        let inc = incoming(&payload_with("ふがP", Some(&b), &["i1"], ""), None, None, "2026-12-01T10:00:00Z");
        assert_eq!(plan(&inc, &stored, &[], Undecided), CardReceivePlan { existing_card_id: None, add_meeting: true, confirm_card_id: None, last_meeting_update: None });
        // QR の無い紙の名刺は同じ人を探さない。
        let paper = card_receive_plan(&incoming(&stored[0].payload, None, None, "2026-12-01T10:00:00Z"), &stored, &[], false, Undecided);
        assert_eq!(paper.existing_card_id, None);
    }

    #[test]
    fn plan_adds_a_meeting_unless_it_is_the_same_occasion() {
        let id = producer_card_new_id("0123456789abcdef");
        let stored = vec![CardStoredRef { id: "c1".into(), payload: payload("ふがP", Some(&id)) }];
        let again = payload("ふがP", Some(&id));
        let meetings = vec![meeting("m1", "c1", Some("sh_1"), Some("camera_qr"), "2026-10-05T10:00:00Z")];
        let qr = Some(CardReceiveVia::CameraQr);

        let same_show = plan(&incoming(&again, Some("sh_1"), qr, "2026-10-05T12:00:00Z"), &stored, &meetings, Undecided);
        assert_eq!(same_show.existing_card_id.as_deref(), Some("c1"));
        assert!(!same_show.add_meeting);

        let next_show = plan(&incoming(&again, Some("sh_2"), qr, "2026-12-01T12:00:00Z"), &stored, &meetings, Undecided);
        assert!(next_show.add_meeting);
        assert_eq!(next_show.last_meeting_update, None);

        // 公演が無ければ JST の同じ日だけ同じ機会 (UTC 15 時は JST の翌日)。
        let no_show = vec![meeting("m1", "c1", None, Some("link"), "2026-10-05T10:00:00Z")];
        let link = Some(CardReceiveVia::Link);
        assert!(!plan(&incoming(&again, None, link, "2026-10-05T14:00:00Z"), &stored, &no_show, Undecided).add_meeting);
        assert!(plan(&incoming(&again, None, link, "2026-10-05T15:30:00Z"), &stored, &no_show, Undecided).add_meeting);
    }

    /// 片方だけに公演があるときも、JST の同じ日なら同じ機会。
    #[test]
    fn one_sided_show_on_the_same_day_is_the_same_occasion() {
        let last = meeting("m1", "c1", None, Some("link"), "2026-10-05T10:00:00Z");
        assert!(same_occasion(&last, Some("sh_1"), "2026-10-05T14:59:00Z"));
        assert!(!same_occasion(&last, Some("sh_1"), "2026-10-05T15:00:00Z"), "JST の翌日");
        let with_show = meeting("m1", "c1", Some("sh_1"), Some("camera_qr"), "2026-10-05T10:00:00Z");
        assert!(same_occasion(&with_show, None, "2026-10-05T11:00:00Z"));
        assert!(!same_occasion(&with_show, Some("sh_2"), "2026-10-05T11:00:00Z"), "どちらにも公演があれば公演で");
    }

    /// 同じ機会でも中身の違う名刺 (同じ人として更新した名刺) は記録を積み、前の中身を記録に残す。
    #[test]
    fn same_occasion_with_different_payload_keeps_the_previous_payload() {
        let old = payload_with("ふがP", None, &["i1"], "前");
        let new = payload_with("ふがP", None, &["i1"], "後");
        let stored = vec![CardStoredRef { id: "c1".into(), payload: old.clone() }];
        let mut last = meeting("m1", "c1", Some("sh_1"), Some("camera_qr"), "2026-10-05T10:00:00Z");
        last.payload = Some(old.clone());
        let p = plan(&incoming(&new, Some("sh_1"), Some(CardReceiveVia::Nearby), "2026-10-05T11:00:00Z"), &stored, &[last], SamePerson);
        assert_eq!(p.existing_card_id.as_deref(), Some("c1"));
        assert!(p.add_meeting, "前の中身を残すため記録を積む");
        assert_eq!(p.last_meeting_update, None, "前の記録は書き換えない");
    }

    /// 同じ機会の 2 回目でも、新しい方が会場での交換なら最後の記録の受け取り方を上げ、中身を新しい方にする。
    #[test]
    fn same_occasion_upgrades_via_and_refreshes_payload() {
        let stored = vec![CardStoredRef { id: "c1".into(), payload: payload("ふがP", None) }];
        let mut last = meeting("m1", "c1", None, Some("link"), "2026-10-05T10:00:00Z");
        last.payload = Some(payload("ふがP", None));
        let p = plan(
            &incoming(&payload("ふがP", None), Some("sh_1"), Some(CardReceiveVia::CameraQr), "2026-10-05T11:00:00Z"),
            &stored,
            &[last.clone()],
            Undecided,
        );
        assert!(!p.add_meeting);
        let up = p.last_meeting_update.expect("上げる");
        assert_eq!(up.id, "m1");
        assert_eq!(up.via.as_deref(), Some("camera_qr"));
        assert_eq!(up.show_id.as_deref(), Some("sh_1"), "公演の無い記録には新しい方の公演を写す");
        assert_eq!(up.met_at, last.met_at, "日時は最初に会ったときのまま");
        assert_eq!(card_meeting_views(&[up])[0].badge.as_deref(), Some("会場で交換"));

        // 既に会場で交換していれば下げない。中身も同じなら書き換えない。
        let mut nearby = meeting("m1", "c1", Some("sh_1"), Some("nearby"), "2026-10-05T10:00:00Z");
        nearby.payload = Some(payload("ふがP", None));
        let p = plan(&incoming(&payload("ふがP", None), Some("sh_1"), Some(CardReceiveVia::Link), "2026-10-05T11:00:00Z"), &stored, &[nearby], Undecided);
        assert_eq!(p.last_meeting_update, None);
    }

    #[test]
    fn latest_meeting_and_restorable() {
        let a = meeting("a", "c1", None, None, "2026-10-05T10:00:00Z");
        let b = meeting("b", "c1", None, None, "2026-10-05T10:00:00Z");
        let other = meeting("z", "c2", None, None, "2026-12-05T10:00:00Z");
        assert_eq!(card_latest_meeting(&[b.clone(), a, other], "c1"), Some(b), "同じ時刻は id の大きい方");
        assert_eq!(card_latest_meeting(&[], "c1"), None);

        let old = payload("ふがP", None);
        let now = payload("ふがP2", None);
        assert!(card_meeting_restorable(Some(&old), &now));
        assert!(!card_meeting_restorable(Some(&now), &now));
        assert!(!card_meeting_restorable(None, &now));
        assert!(!card_meeting_restorable(Some("壊れた"), &now));
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
        assert_eq!(views[0].date, "2026-10-05", "公演があれば公演の日");
        assert_eq!(views[1].date, "2026-11-01", "無ければ受け取った日 (JST)");
    }
}
