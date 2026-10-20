//! すれちがいモード: すれちがいをオンにした端末どうしが、近くに来たら Bluetooth Low Energy で
//! P名刺を自動で交換する (iPhone ⇄ Android でも届く。サーバは使わない)。
//!
//! 端末は BLE の出し入れ (名乗る・探す・繋いで読む) だけをし、何をどう載せて読むかはここ 1 か所に置く。
//!
//! - **載せ方** ([`streetpass_frames`]): 名刺の中身 (`#` の後ろ) を、見出し 1 つと決まった数の欠片に分けて
//!   GATT の特性 (読み取り専用) に置く。1 つの特性は 512 バイトまでなので欠片は [`STREETPASS_CHUNK_BYTES`]。
//!   見出しは版・長さ・欠片の数・指紋 (FNV-1a 64bit)。名刺の中身の上限 (1400 字) は欠片 3 つに収まる。
//! - **読み方**: 見出しを読み ([`streetpass_header_decode`])、最近読んだ指紋なら欠片を読まずに切る
//!   ([`streetpass_should_read`])。読むなら欠片をつなぎ、長さと指紋と名刺として読めるかを確かめる ([`streetpass_join`])。
//! - **お互いにオンのときだけ**: 名乗るのも探すのもオンの端末だけ。オフの人の名刺は集められない
//!   (QR を見せた相手にだけ渡す近距離の交換とは別の、本人が選んだ公開)。
//! - **しまい方**: 受け取り方は `CardReceiveVia::StreetPass` (札「すれちがい」)。同じ人の見分け・同じ日に 2 度会った
//!   ときの記録の積み方は近距離の交換と同じ (`card_meetings::card_receive_plan`)。同じ人か確かめる名刺は
//!   確かめずに別の名刺として足す (後から聞く画面が無いので、黙って中身を差し替えない側に倒す)。
//! - **上限**: 1 日 [`STREETPASS_DAILY_LIMIT`] 人まで (人の多い会場で名刺入れが溢れないように・
//!   作った名刺を大量に撒かれても入れすぎないように)。オンにしてから [`STREETPASS_ACTIVE_HOURS`] 時間で自動でオフ
//!   (付けっぱなしで電池を減らさない)。

use crate::domain::card_meetings::{
    card_receive_via_from_key, jst_day, CardMeetingRecord, CardReceiveVia,
};
use crate::domain::producer_card::decode_producer_card;

/// GATT のサービス (広告にも載せる。これで探す)。
pub const STREETPASS_SERVICE_UUID: &str = "6F3C2A10-5B7E-4D21-9A8C-1E4F7B2D9C01";
/// 見出しの特性。
pub const STREETPASS_HEADER_UUID: &str = "6F3C2A11-5B7E-4D21-9A8C-1E4F7B2D9C01";
/// 欠片の特性 (この順に 0, 1, 2 番)。
pub const STREETPASS_CHUNK_UUIDS: [&str; 3] = [
    "6F3C2A12-5B7E-4D21-9A8C-1E4F7B2D9C01",
    "6F3C2A13-5B7E-4D21-9A8C-1E4F7B2D9C01",
    "6F3C2A14-5B7E-4D21-9A8C-1E4F7B2D9C01",
];
/// 欠片 1 つのバイト数 (特性の値の上限 512 に余裕を持たせる)。
pub const STREETPASS_CHUNK_BYTES: usize = 480;
/// 見出しの形の版。
pub const STREETPASS_FORMAT_VERSION: u8 = 1;
const HEADER_LEN: usize = 12;
/// 1 日に受け取る人数の上限。
pub const STREETPASS_DAILY_LIMIT: u32 = 100;
/// オンにしてから自動でオフにするまでの時間。
pub const STREETPASS_ACTIVE_HOURS: i64 = 12;
/// 同じ指紋の名刺を読み直さない間 (分)。同じ人とずっと近くにいても繋ぎ続けない。
pub const STREETPASS_REREAD_MINUTES: i64 = 60;

/// BLE の識別子 (端末が GATT を組むのに使う)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StreetpassUuids {
    pub service: String,
    pub header: String,
    /// 欠片の特性。並びが欠片の番号。
    pub chunks: Vec<String>,
}

pub fn streetpass_uuids() -> StreetpassUuids {
    StreetpassUuids {
        service: STREETPASS_SERVICE_UUID.to_string(),
        header: STREETPASS_HEADER_UUID.to_string(),
        chunks: STREETPASS_CHUNK_UUIDS.iter().map(|s| s.to_string()).collect(),
    }
}

/// 特性に置く値。`chunks` は常に [`STREETPASS_CHUNK_UUIDS`] と同じ数 (使わない欠片は空)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StreetpassFrames {
    pub header: Vec<u8>,
    pub chunks: Vec<Vec<u8>>,
}

/// 読んだ見出し。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StreetpassHeader {
    /// 中身のバイト数。
    pub length: u32,
    /// 読む欠片の数 (先頭からこの数だけ読む)。
    pub chunk_count: u32,
    /// 指紋 (16 桁の 16 進)。最近読んだかの見分けに使う。
    pub fingerprint: String,
}

/// 最近読んだ名刺 1 つ (端末がその間だけ覚えておく。保存はしない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StreetpassSeen {
    pub fingerprint: String,
    /// 読んだ日時 (ISO 8601)。
    pub at: String,
}

/// 端末の Bluetooth の様子 (端末が読んで渡す)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum StreetpassRadio {
    /// 使える。
    Ready,
    /// Bluetooth が切れている。
    PoweredOff,
    /// このアプリに Bluetooth の許可が無い。
    Unauthorized,
    /// この端末では使えない (BLE の広告ができない等)。
    Unsupported,
    /// まだ分からない (起動直後)。
    Unknown,
}

/// すれちがいの今の様子 (名刺入れの行に出す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct StreetpassStatus {
    /// 「すれちがい中」「すれちがいはオフ」。
    pub title: String,
    /// 説明の 1 行。
    pub detail: String,
    /// 今日すれちがった人数。
    pub today_count: u32,
    /// 今日の上限に届いた (受け取りを止めている)。
    pub limit_reached: bool,
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut h: u64 = 0xcbf2_9ce4_8422_2325;
    for b in bytes {
        h ^= u64::from(*b);
        h = h.wrapping_mul(0x0000_0100_0000_01b3);
    }
    h
}

fn fingerprint_hex(bytes: &[u8]) -> String {
    format!("{:016x}", fnv1a64(bytes))
}

/// 名刺の中身の指紋 (16 桁の 16 進)。
pub fn streetpass_fingerprint(payload: &str) -> String {
    fingerprint_hex(payload.as_bytes())
}

/// 名刺の中身を特性に置く値にする。名刺として読めない・欠片に収まらない中身は None (名乗らない)。
pub fn streetpass_frames(payload: &str) -> Option<StreetpassFrames> {
    let bytes = payload.as_bytes();
    let max = STREETPASS_CHUNK_BYTES * STREETPASS_CHUNK_UUIDS.len();
    if bytes.is_empty() || bytes.len() > max || decode_producer_card(payload).is_none() {
        return None;
    }
    let mut chunks: Vec<Vec<u8>> = bytes.chunks(STREETPASS_CHUNK_BYTES).map(<[u8]>::to_vec).collect();
    let count = chunks.len();
    chunks.resize(STREETPASS_CHUNK_UUIDS.len(), Vec::new());
    let mut header = Vec::with_capacity(HEADER_LEN);
    header.push(STREETPASS_FORMAT_VERSION);
    header.extend_from_slice(&(bytes.len() as u16).to_be_bytes());
    header.push(count as u8);
    header.extend_from_slice(&fnv1a64(bytes).to_be_bytes());
    Some(StreetpassFrames { header, chunks })
}

/// 見出しを読む。版が違う・形が崩れている・数が合わないものは None (その相手は読まない)。
pub fn streetpass_header_decode(bytes: &[u8]) -> Option<StreetpassHeader> {
    if bytes.len() != HEADER_LEN || bytes[0] != STREETPASS_FORMAT_VERSION {
        return None;
    }
    let length = u32::from(u16::from_be_bytes([bytes[1], bytes[2]]));
    let chunk_count = u32::from(bytes[3]);
    let max_chunks = STREETPASS_CHUNK_UUIDS.len() as u32;
    let expected = (length as usize).div_ceil(STREETPASS_CHUNK_BYTES) as u32;
    if length == 0 || chunk_count == 0 || chunk_count > max_chunks || chunk_count != expected {
        return None;
    }
    let mut fp = [0u8; 8];
    fp.copy_from_slice(&bytes[4..12]);
    Some(StreetpassHeader {
        length,
        chunk_count,
        fingerprint: format!("{:016x}", u64::from_be_bytes(fp)),
    })
}

/// 読んだ欠片 (先頭から `chunk_count` 個) をつないで名刺の中身に戻す。長さ・指紋が合わない、
/// 名刺として読めないものは None (途中で切れた・別の端末の値が混ざった)。
pub fn streetpass_join(header: &StreetpassHeader, chunks: &[Vec<u8>]) -> Option<String> {
    if chunks.len() < header.chunk_count as usize {
        return None;
    }
    let bytes: Vec<u8> = chunks[..header.chunk_count as usize].concat();
    if bytes.len() != header.length as usize || fingerprint_hex(&bytes) != header.fingerprint {
        return None;
    }
    let payload = String::from_utf8(bytes).ok()?;
    decode_producer_card(&payload).is_some().then_some(payload)
}

fn parse(at: &str) -> Option<chrono::DateTime<chrono::Utc>> {
    chrono::DateTime::parse_from_rfc3339(at).ok().map(|t| t.with_timezone(&chrono::Utc))
}

/// この指紋の名刺を (欠片まで) 読むか。自分の名刺・最近 [`STREETPASS_REREAD_MINUTES`] 分以内に読んだ名刺は読まない。
pub fn streetpass_should_read(fingerprint: &str, own_fingerprint: Option<&str>, recent: &[StreetpassSeen], now: &str) -> bool {
    if own_fingerprint == Some(fingerprint) {
        return false;
    }
    let Some(now) = parse(now) else { return true };
    !recent.iter().any(|s| {
        s.fingerprint == fingerprint
            && parse(&s.at).is_some_and(|at| now - at < chrono::Duration::minutes(STREETPASS_REREAD_MINUTES))
    })
}

/// 覚えておく「最近読んだ名刺」を、読み直さない間を過ぎたものを落として返す。
pub fn streetpass_prune_seen(recent: &[StreetpassSeen], now: &str) -> Vec<StreetpassSeen> {
    let Some(now) = parse(now) else { return recent.to_vec() };
    recent
        .iter()
        .filter(|s| parse(&s.at).is_some_and(|at| now - at < chrono::Duration::minutes(STREETPASS_REREAD_MINUTES)))
        .cloned()
        .collect()
}

/// 今日 (JST) すれちがいで会った人数 (会った記録のうち、受け取り方がすれちがいのものを名刺ごとに数える)。
pub fn streetpass_today_count(meetings: &[CardMeetingRecord], now: &str) -> u32 {
    let today = jst_day(now);
    let mut cards: Vec<&str> = meetings
        .iter()
        .filter(|m| {
            m.via.as_deref().and_then(card_receive_via_from_key) == Some(CardReceiveVia::StreetPass)
                && jst_day(&m.met_at) == today
        })
        .map(|m| m.card_id.as_str())
        .collect();
    cards.sort_unstable();
    cards.dedup();
    cards.len() as u32
}

/// オンのままか。`started_at` (オンにした日時) から [`STREETPASS_ACTIVE_HOURS`] 時間を過ぎたらオフ。
/// オンにしていない (None)・読めない日時はオフ。
pub fn streetpass_is_active(started_at: Option<&str>, now: &str) -> bool {
    match (started_at.and_then(parse), parse(now)) {
        (Some(start), Some(now)) => now >= start && now - start < chrono::Duration::hours(STREETPASS_ACTIVE_HOURS),
        _ => false,
    }
}

/// 今日の上限に届く前か (届いたら名乗りは続けるが受け取らない)。
pub fn streetpass_accepts(today_count: u32) -> bool {
    today_count < STREETPASS_DAILY_LIMIT
}

/// 名刺入れの行に出す様子。`has_card` は自分の名刺を作ってあるか (無いとオンにできない)。
/// `radio` はオンのときだけ見る (オフの間は Bluetooth の様子を問わない)。
pub fn streetpass_status(active: bool, has_card: bool, today_count: u32, radio: StreetpassRadio) -> StreetpassStatus {
    let limit_reached = !streetpass_accepts(today_count);
    let (title, detail) = if !has_card {
        ("すれちがい", "自分の名刺を作ると、すれちがいをオンにできます".to_string())
    } else if active && radio == StreetpassRadio::PoweredOff {
        ("すれちがい中 (止まっています)", "Bluetooth をオンにすると、すれちがいが動きます".to_string())
    } else if active && radio == StreetpassRadio::Unauthorized {
        ("すれちがい中 (止まっています)", "設定でこのアプリに Bluetooth を許可すると、すれちがいが動きます".to_string())
    } else if active && radio == StreetpassRadio::Unsupported {
        ("すれちがい中 (止まっています)", "この端末では、すれちがいが使えません".to_string())
    } else if !active {
        (
            "すれちがいはオフ",
            format!("オンにすると、近くでオンにしている P と名刺を自動で交換します ({STREETPASS_ACTIVE_HOURS} 時間で自動でオフ)"),
        )
    } else if limit_reached {
        ("すれちがい中", format!("今日は {STREETPASS_DAILY_LIMIT} 人に届いたので、受け取りを止めています"))
    } else if today_count == 0 {
        ("すれちがい中", "近くでオンにしている P を探しています".to_string())
    } else {
        ("すれちがい中", format!("今日すれちがった P: {today_count} 人"))
    };
    StreetpassStatus { title: title.to_string(), detail, today_count, limit_reached }
}

/// すれちがいで受け取ったときの知らせの文言 (アプリが裏にいるとき)。名前が無ければ「P」。
pub fn streetpass_notice_text(name: &str) -> String {
    let name = name.trim();
    if name.is_empty() {
        "P とすれちがいました。名刺入れに入れました".to_string()
    } else {
        format!("{name} さんとすれちがいました。名刺入れに入れました")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::producer_card::{encode_producer_card, ProducerCardInput};

    fn payload(name: &str, message: &str) -> String {
        let input = ProducerCardInput {
            name: name.into(),
            message: message.into(),
            since_year: None,
            oshi_idol_ids: vec![],
            links: vec![],
            show_count: None,
            song_count: None,
            next_show_id: None,
            attended: vec![],
            issued_on: "2026-10-21".into(),
            design: None,
            qr_url: None,
            show_brand_labels: false,
            card_id: None,
        };
        let url = encode_producer_card(&input).url;
        url.split_once('#').map(|(_, p)| p.to_string()).unwrap()
    }

    #[test]
    fn frames_round_trip() {
        let p = payload("天海P", "よろしくお願いします");
        let f = streetpass_frames(&p).unwrap();
        assert_eq!(f.chunks.len(), STREETPASS_CHUNK_UUIDS.len());
        let h = streetpass_header_decode(&f.header).unwrap();
        assert_eq!(h.length as usize, p.len());
        assert_eq!(h.fingerprint, streetpass_fingerprint(&p));
        assert_eq!(streetpass_join(&h, &f.chunks).as_deref(), Some(p.as_str()));
    }

    #[test]
    fn long_payload_splits_into_chunks() {
        let long = "あ".repeat(60);
        let p = payload(&"P".repeat(24), &long);
        let f = streetpass_frames(&p).unwrap();
        let h = streetpass_header_decode(&f.header).unwrap();
        assert_eq!(h.chunk_count as usize, p.len().div_ceil(STREETPASS_CHUNK_BYTES));
        // 読んだ欠片だけ渡しても戻る (使わない欠片は読まなくてよい)。
        let read: Vec<Vec<u8>> = f.chunks[..h.chunk_count as usize].to_vec();
        assert_eq!(streetpass_join(&h, &read).as_deref(), Some(p.as_str()));
    }

    #[test]
    fn rejects_broken_frames() {
        let p = payload("天海P", "");
        let f = streetpass_frames(&p).unwrap();
        let h = streetpass_header_decode(&f.header).unwrap();
        let mut bad = f.chunks.clone();
        bad[0][0] ^= 1;
        assert_eq!(streetpass_join(&h, &bad), None, "指紋が合わない");
        assert_eq!(streetpass_join(&h, &[]), None, "欠片が足りない");
        let mut header = f.header.clone();
        header[0] = 9;
        assert_eq!(streetpass_header_decode(&header), None, "版が違う");
        assert_eq!(streetpass_header_decode(&f.header[..5]), None, "短い");
        let mut wrong_count = f.header.clone();
        wrong_count[3] = 3;
        assert_eq!(streetpass_header_decode(&wrong_count), None, "長さと欠片の数が合わない");
    }

    #[test]
    fn does_not_advertise_non_cards() {
        assert_eq!(streetpass_frames(""), None);
        assert_eq!(streetpass_frames("not-a-card"), None);
        assert_eq!(streetpass_frames(&"A".repeat(2000)), None);
    }

    #[test]
    fn reread_window() {
        let seen = vec![StreetpassSeen { fingerprint: "aa".into(), at: "2026-10-21T10:00:00Z".into() }];
        assert!(!streetpass_should_read("aa", None, &seen, "2026-10-21T10:30:00Z"));
        assert!(streetpass_should_read("aa", None, &seen, "2026-10-21T11:00:00Z"));
        assert!(streetpass_should_read("bb", None, &seen, "2026-10-21T10:30:00Z"));
        assert!(!streetpass_should_read("cc", Some("cc"), &[], "2026-10-21T10:30:00Z"), "自分の名刺");
        assert_eq!(streetpass_prune_seen(&seen, "2026-10-21T11:00:00Z"), vec![]);
        assert_eq!(streetpass_prune_seen(&seen, "2026-10-21T10:10:00Z"), seen);
    }

    fn meeting(card: &str, via: &str, at: &str) -> CardMeetingRecord {
        CardMeetingRecord {
            id: format!("{card}-{at}"),
            card_id: card.into(),
            show_id: None,
            show_date: None,
            via: Some(via.into()),
            met_at: at.into(),
            payload: None,
        }
    }

    #[test]
    fn counts_today_in_jst_per_person() {
        let ms = vec![
            meeting("a", "streetpass", "2026-10-21T01:00:00Z"),
            meeting("a", "streetpass", "2026-10-21T02:00:00Z"),
            meeting("b", "streetpass", "2026-10-20T15:30:00Z"), // JST 10-21 00:30
            meeting("c", "nearby", "2026-10-21T01:00:00Z"),
            meeting("d", "streetpass", "2026-10-20T14:00:00Z"), // JST 10-20
        ];
        assert_eq!(streetpass_today_count(&ms, "2026-10-21T03:00:00Z"), 2);
    }

    #[test]
    fn auto_off_after_hours() {
        let start = Some("2026-10-21T00:00:00Z");
        assert!(streetpass_is_active(start, "2026-10-21T11:59:00Z"));
        assert!(!streetpass_is_active(start, "2026-10-21T12:00:00Z"));
        assert!(!streetpass_is_active(None, "2026-10-21T01:00:00Z"));
        assert!(!streetpass_is_active(Some("bad"), "2026-10-21T01:00:00Z"));
    }

    #[test]
    fn status_lines() {
        let ready = StreetpassRadio::Ready;
        assert_eq!(streetpass_status(true, false, 0, ready).title, "すれちがい");
        assert_eq!(streetpass_status(false, true, 0, StreetpassRadio::PoweredOff).title, "すれちがいはオフ");
        assert_eq!(streetpass_status(true, true, 3, ready).detail, "今日すれちがった P: 3 人");
        assert!(streetpass_status(true, true, STREETPASS_DAILY_LIMIT, ready).limit_reached);
        assert_eq!(
            streetpass_status(true, true, 0, StreetpassRadio::Unauthorized).detail,
            "設定でこのアプリに Bluetooth を許可すると、すれちがいが動きます"
        );
        assert!(!streetpass_accepts(STREETPASS_DAILY_LIMIT));
    }

    #[test]
    fn notice_text() {
        assert_eq!(streetpass_notice_text(" 天海P "), "天海P さんとすれちがいました。名刺入れに入れました");
        assert_eq!(streetpass_notice_text(""), "P とすれちがいました。名刺入れに入れました");
    }

    #[test]
    fn via_and_badge() {
        use crate::domain::card_meetings::{card_meeting_badge, card_met_in_person, card_receive_via_key};
        assert_eq!(card_receive_via_key(CardReceiveVia::StreetPass), "streetpass");
        assert_eq!(card_receive_via_from_key("streetpass"), Some(CardReceiveVia::StreetPass));
        assert!(card_met_in_person(Some(CardReceiveVia::StreetPass), None));
        assert_eq!(card_meeting_badge(Some(CardReceiveVia::StreetPass), Some("sh")).as_deref(), Some("すれちがい"));
    }
}
