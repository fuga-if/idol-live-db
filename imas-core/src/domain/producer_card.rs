//! P名刺 (プロデューサーの名刺) の組み立て・QR の中身・読み取り・共通点・名刺入れの束ね方。
//!
//! 名刺の中身は **URL の `#` の後ろに全部入れる** (サーバに何も置かない)。
//! `https://idollivedb.fugaapp.site/p/#<base64url>`。アプリが読めばそのまま名刺入れへ、
//! アプリの無い人がカメラで読めば Web の名刺ページが同じ中身を描く。
//! 圏外の会場でも交換できること、ランニングコストがゼロのままであることが理由。
//!
//! 参加した公演は id (UUID で 40 バイト近い) をそのまま入れると QR に収まらないので、
//! **公演の日付 + id の 16 bit の指紋** (`CardShowStamp`) に縮める。受け取った側は自分の
//! 参加公演を同じ形に縮めて突き合わせる。同じ日に指紋まで一致する別公演は事実上ない。
//!
//! 名刺はその時点の紙と同じで、後から自分の名刺を直しても相手の手元のものは変わらない
//! (`issued_on` を刷っておく)。

use chrono::NaiveDate;

use crate::domain::share_text::WEB_ORIGIN;

/// 名刺ページのパス。Web (`web/src/pages/p/`) と Universal Link の受け口がこれを見る。
pub const CARD_PATH: &str = "/p/";

/// 中身の版。読み解けない版の名刺は `None` を返す (古いアプリが新しい名刺を誤読しない)。
const FORMAT_VERSION: u8 = 1;

/// QR に入れる URL の長さの上限 (文字)。これを超える分は古い参加公演から落とす。
/// QR は 1,500 文字前後までなら端末の画面どうしで安定して読める (version 30 前後・誤り訂正 L)。
const MAX_URL_LEN: usize = 1400;

const MAX_NAME_CHARS: u32 = 24;
const MAX_MESSAGE_CHARS: u32 = 60;
const MAX_OSHI: u32 = 5;
const MAX_LINKS: u32 = 4;
const MAX_LINK_VALUE_CHARS: usize = 200;
/// アイドル・公演の id の長さの上限 (バイト)。実際の id は 50 バイト前後。
const MAX_ID_BYTES: usize = 128;

/// 日付を数える起点。アイマスのライブはこれより前に無い。
fn epoch() -> NaiveDate {
    NaiveDate::from_ymd_opt(2000, 1, 1).expect("valid date")
}

// ---------------------------------------------------------------------------
// 型
// ---------------------------------------------------------------------------

/// 名刺に載せられるリンクの種類。並び順は編集画面の選択肢の順。
///
/// `serde::Serialize` は Web 出面 (wasm) が読み解いた名刺を JSON で返すために要る
/// (TS に形式の読み解きを書かないため、wasm が `card_link_view` まで通した結果を渡す)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CardLinkKind {
    X,
    Bluesky,
    Misskey,
    YouTube,
    Instagram,
    TikTok,
    Web,
}

/// 名刺のリンク 1 本。`value` は X 等ならハンドル (`@` 無し)、Misskey は `user@host`、
/// Web は URL。保存も QR もこの形。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardLink {
    pub kind: CardLinkKind,
    pub value: String,
}

/// 画面に出すリンク。`label` は種類の名前、`display` は右に添える値、`url` は開く先。
///
/// `serde::Serialize` は Web 出面 (wasm) が名刺ページ用の JSON にそのまま載せるため。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardLinkView {
    pub kind: CardLinkKind,
    pub label: String,
    pub display: String,
    pub url: String,
}

/// 編集画面のリンクの選択肢。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardLinkKindInfo {
    pub kind: CardLinkKind,
    pub label: String,
    /// 入力欄の見本 (例: `@idollivedb`)。
    pub placeholder: String,
}

/// 参加した公演の縮めた形。`day` は 2000-01-01 からの日数、`tag` は公演 id の指紋。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct CardShowStamp {
    pub day: u32,
    pub tag: u16,
}

/// 公演 id と開催日 (`YYYY-MM-DD`)。自分の参加公演を渡すときの形。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardShowRef {
    pub show_id: String,
    pub date: String,
}

/// 名刺の中身。QR から読んだものもこの形。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProducerCard {
    pub name: String,
    pub message: String,
    /// P 歴の始まり (西暦)。無ければ載せない。
    pub since_year: Option<u16>,
    pub oshi_idol_ids: Vec<String>,
    pub links: Vec<CardLink>,
    pub show_count: Option<u32>,
    pub song_count: Option<u32>,
    pub next_show_id: Option<String>,
    /// 参加した公演 (日付の昇順)。載せないなら空。
    pub attended: Vec<CardShowStamp>,
    /// QR に収めるため古い公演を落としたら true。`show_count` は落とす前の数のまま。
    pub attended_truncated: bool,
    /// 名刺を作った日 (`YYYY-MM-DD`)。
    pub issued_on: String,
    /// 名刺のデザイン。None は既定のデザイン (`CardDesign::Pass`)。既定は中身に書かない
    /// (デザインを選んでいない名刺は古い版のアプリでも読める)。描くときは
    /// `producer_card_display_design` (自作の画像が手元に無ければ入場証で描く)。
    #[uniffi(default = None)]
    pub design: Option<CardDesign>,
    /// 自分の QR (リットリンク・X のプロフィール・自分のサイトなど、好きな URL)。
    /// 受け取った側では「QR」というリンクの 1 本として出す (`card_qr_link_view`)。
    #[uniffi(default = None)]
    pub qr_url: Option<String>,
}

/// 自分の名刺を作るときの材料。数や公演はアプリの記録から、名前などは編集画面から。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProducerCardInput {
    pub name: String,
    pub message: String,
    pub since_year: Option<u16>,
    pub oshi_idol_ids: Vec<String>,
    pub links: Vec<CardLink>,
    pub show_count: Option<u32>,
    pub song_count: Option<u32>,
    pub next_show_id: Option<String>,
    pub attended: Vec<CardShowRef>,
    pub issued_on: String,
    #[uniffi(default = None)]
    pub design: Option<CardDesign>,
    /// 自分の QR の URL。入力のまま渡してよい (組み立てで `normalize_card_qr_url` を通す)。
    #[uniffi(default = None)]
    pub qr_url: Option<String>,
}

/// 組み上がった名刺と QR に入れる URL。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct EncodedProducerCard {
    pub card: ProducerCard,
    pub url: String,
    /// QR に収めるために落とした参加公演の数。
    pub dropped_shows: u32,
}

/// 名刺の入力の誤り。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProducerCardInputError {
    NameEmpty,
    NameTooLong,
    MessageTooLong,
    TooManyOshi,
    TooManyLinks,
    LinkInvalid,
    /// 自分の QR の URL の形が合わない (http(s) の URL でない・名刺の URL を入れた・長すぎる)。
    QrUrlInvalid,
    /// 公演を外しても QR に収まらない (リンクや自分の QR が長すぎる)。
    TooLong,
}

/// 入力の上限。編集画面の文字数の表示と入力の打ち切りに使う。
#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProducerCardLimits {
    pub max_name_chars: u32,
    pub max_message_chars: u32,
    pub max_oshi: u32,
    pub max_links: u32,
}

/// カメラで読んだコードの中身。
#[derive(uniffi::Enum, Clone, Debug, PartialEq, Eq)]
pub enum ScannedCode {
    /// アプリの名刺。`payload` は `#` の後ろ (保存はこれ)。
    Card {
        card: ProducerCard,
        payload: String,
    },
    /// 名刺ではないリンク (紙の名刺の QR など)。種類が分かれば `link` に入る。
    Link {
        url: String,
        link: Option<CardLink>,
    },
    Text {
        text: String,
    },
}

/// 受け取った名刺とあなたの共通点。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardCommon {
    /// 同じ担当 (相手の名刺の並び順)。
    pub shared_oshi_ids: Vec<String>,
    /// 同じ公演にいた (あなたの公演 id、日付の昇順)。先頭が「はじめて同じ会場」。
    pub shared_show_ids: Vec<String>,
}

/// 名刺入れの 1 枚。並べ替えと束ねに要るものだけ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardCaseEntry {
    pub id: String,
    /// 受け取った公演。無ければ受け取った日で束ねる。
    pub show_id: Option<String>,
    /// 受け取った公演の日付 (`YYYY-MM-DD`)。`show_id` があるときだけ。
    pub show_date: Option<String>,
    /// 受け取った日時 (ISO 8601。先頭 10 文字が日付)。
    pub received_at: String,
}

/// 名刺入れの束 1 つ (公演 1 つ、または公演に紐づかない 1 日)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardCaseSection {
    pub show_id: Option<String>,
    /// 束の日付 (`YYYY-MM-DD`)。公演があれば公演の日、無ければ受け取った日。
    pub date: String,
    /// 新しく受け取った順。
    pub entry_ids: Vec<String>,
}

// ---------------------------------------------------------------------------
// 入力
// ---------------------------------------------------------------------------

pub fn producer_card_limits() -> ProducerCardLimits {
    ProducerCardLimits {
        max_name_chars: MAX_NAME_CHARS,
        max_message_chars: MAX_MESSAGE_CHARS,
        max_oshi: MAX_OSHI,
        max_links: MAX_LINKS,
    }
}

pub fn validate_producer_card(input: &ProducerCardInput) -> Option<ProducerCardInputError> {
    let name = input.name.trim();
    if name.is_empty() {
        return Some(ProducerCardInputError::NameEmpty);
    }
    if char_len(name) > MAX_NAME_CHARS as usize {
        return Some(ProducerCardInputError::NameTooLong);
    }
    if char_len(input.message.trim()) > MAX_MESSAGE_CHARS as usize {
        return Some(ProducerCardInputError::MessageTooLong);
    }
    if input.oshi_idol_ids.len() > MAX_OSHI as usize {
        return Some(ProducerCardInputError::TooManyOshi);
    }
    if input.links.len() > MAX_LINKS as usize {
        return Some(ProducerCardInputError::TooManyLinks);
    }
    if input.links.iter().any(|l| normalize_link(l).is_none()) {
        return Some(ProducerCardInputError::LinkInvalid);
    }
    if let Some(url) = input.qr_url.as_deref().filter(|u| !u.trim().is_empty()) {
        if normalize_card_qr_url(url).is_none() {
            return Some(ProducerCardInputError::QrUrlInvalid);
        }
    }
    // 公演は組み立てで落とせるので、公演を除いても収まるかを見る (収まらない名刺は相手が読めない)。
    let without_shows = ProducerCardInput {
        attended: Vec::new(),
        ..input.clone()
    };
    if encode_producer_card(&without_shows).url.len() > MAX_URL_LEN {
        return Some(ProducerCardInputError::TooLong);
    }
    None
}

pub fn producer_card_input_error_message(error: ProducerCardInputError) -> String {
    match error {
        ProducerCardInputError::NameEmpty => "名前を入れてください".into(),
        ProducerCardInputError::NameTooLong => format!("名前は{MAX_NAME_CHARS}文字までです"),
        ProducerCardInputError::MessageTooLong => {
            format!("ひとことは{MAX_MESSAGE_CHARS}文字までです")
        }
        ProducerCardInputError::TooManyOshi => format!("担当は{MAX_OSHI}人まで載せられます"),
        ProducerCardInputError::TooManyLinks => format!("リンクは{MAX_LINKS}本までです"),
        ProducerCardInputError::LinkInvalid => "リンクの書き方を確かめてください".into(),
        ProducerCardInputError::QrUrlInvalid => {
            "QR にする URL は http:// か https:// から始まるページの URL にしてください".into()
        }
        ProducerCardInputError::TooLong => {
            "名刺が長すぎて QR に収まりません。リンクか自分の QR を短くしてください".into()
        }
    }
}

/// 名刺を組み立てて QR に入れる URL にする。入力は検査済みである前提で、念のため上限で切る。
/// URL が長すぎるときは古い参加公演から落とす。
pub fn encode_producer_card(input: &ProducerCardInput) -> EncodedProducerCard {
    let mut attended: Vec<CardShowStamp> = input
        .attended
        .iter()
        .filter_map(|r| show_stamp(&r.show_id, &r.date))
        .collect();
    attended.sort();
    attended.dedup();

    let mut card = ProducerCard {
        name: truncate_chars(input.name.trim(), MAX_NAME_CHARS as usize),
        message: truncate_chars(input.message.trim(), MAX_MESSAGE_CHARS as usize),
        since_year: input.since_year,
        oshi_idol_ids: input
            .oshi_idol_ids
            .iter()
            .take(MAX_OSHI as usize)
            .cloned()
            .collect(),
        links: input
            .links
            .iter()
            .filter_map(normalize_link)
            .take(MAX_LINKS as usize)
            .collect(),
        show_count: input.show_count,
        song_count: input.song_count,
        next_show_id: input.next_show_id.clone().filter(|s| !s.is_empty()),
        attended,
        attended_truncated: false,
        issued_on: input.issued_on.clone(),
        design: input.design.filter(|d| *d != CardDesign::default()),
        qr_url: input
            .qr_url
            .as_deref()
            .filter(|u| !u.trim().is_empty())
            .and_then(normalize_card_qr_url),
    };

    let total = card.attended.len();
    let mut url = card_url(&card);
    if url.len() > MAX_URL_LEN && !card.attended.is_empty() {
        // 1 公演はおよそ 4 文字。超えた分をまとめて落としてから 1 件ずつ詰める。
        let over = (url.len() - MAX_URL_LEN).div_ceil(4);
        let drop = over.min(card.attended.len());
        card.attended.drain(..drop);
        card.attended_truncated = true;
        url = card_url(&card);
        while url.len() > MAX_URL_LEN && !card.attended.is_empty() {
            card.attended.remove(0);
            url = card_url(&card);
        }
    }
    let dropped = (total - card.attended.len()) as u32;
    EncodedProducerCard {
        card,
        url,
        dropped_shows: dropped,
    }
}

fn card_url(card: &ProducerCard) -> String {
    format!(
        "{WEB_ORIGIN}{CARD_PATH}#{}",
        base64url_encode(&write_card(card))
    )
}

// ---------------------------------------------------------------------------
// 読み取り
// ---------------------------------------------------------------------------

/// 名刺の URL (または `#` の後ろだけ) を読み解く。名刺でなければ None。
pub fn decode_producer_card(text: &str) -> Option<ProducerCard> {
    let payload = card_payload(text)?;
    if payload.len() > MAX_URL_LEN {
        return None;
    }
    read_card(&base64url_decode(payload)?)
}

/// 名刺の URL から `#` の後ろを取り出す。名刺の URL でなければ None。
/// `#` の後ろだけ (保存してある形) を渡されたらそのまま返す。
fn card_payload(text: &str) -> Option<&str> {
    let text = text.trim();
    if let Some((head, frag)) = text.split_once('#') {
        let head = head.trim_end_matches('/');
        let expected = format!("{WEB_ORIGIN}{}", CARD_PATH.trim_end_matches('/'));
        let is_card_url =
            head.eq_ignore_ascii_case(&expected) || head.eq_ignore_ascii_case("imaslivedb://p");
        return is_card_url.then_some(frag).filter(|f| !f.is_empty());
    }
    let is_payload = !text.is_empty()
        && text
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_');
    is_payload.then_some(text)
}

/// カメラで読んだ文字列を名刺・リンク・ただの文字に分ける。
pub fn classify_scanned_code(text: &str) -> ScannedCode {
    let trimmed = text.trim();
    // `#` の無い文字列は名刺として扱わない (ただの英数字を名刺と誤読しない)。
    if trimmed.contains('#') {
        if let Some(payload) = card_payload(trimmed) {
            if let Some(card) = base64url_decode(payload).as_deref().and_then(read_card) {
                return ScannedCode::Card {
                    card,
                    payload: payload.to_string(),
                };
            }
        }
    }
    if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
        return ScannedCode::Link {
            url: trimmed.to_string(),
            link: card_link_from_url(trimmed),
        };
    }
    ScannedCode::Text {
        text: trimmed.to_string(),
    }
}

/// 保存してある `#` の後ろから共有用の URL を作り直す。
pub fn producer_card_url_from_payload(payload: &str) -> String {
    format!("{WEB_ORIGIN}{CARD_PATH}#{payload}")
}

/// 保存してある名刺から `#` の後ろを作る (紙の名刺を名刺の形で保存するときに使う)。
pub fn producer_card_payload(card: &ProducerCard) -> String {
    base64url_encode(&write_card(card))
}

// ---------------------------------------------------------------------------
// 共通点・名刺入れ
// ---------------------------------------------------------------------------

/// 受け取った名刺とあなたの記録の共通点。
pub fn producer_card_common(
    card: &ProducerCard,
    my_oshi_ids: &[String],
    my_attended: &[CardShowRef],
) -> CardCommon {
    let shared_oshi_ids = card
        .oshi_idol_ids
        .iter()
        .filter(|id| my_oshi_ids.contains(id))
        .cloned()
        .collect();

    let theirs: std::collections::HashSet<CardShowStamp> = card.attended.iter().copied().collect();
    let mut shared: Vec<(CardShowStamp, &String)> = my_attended
        .iter()
        .filter_map(|r| show_stamp(&r.show_id, &r.date).map(|s| (s, &r.show_id)))
        .filter(|(s, _)| theirs.contains(s))
        .collect();
    shared.sort();
    shared.dedup_by(|a, b| a.1 == b.1);

    CardCommon {
        shared_oshi_ids,
        shared_show_ids: shared.into_iter().map(|(_, id)| id.clone()).collect(),
    }
}

/// 交換した公演の候補。今日 (JST) の参加公演、無ければ昨日 (終演後の打ち上げ) の参加公演。
/// 同じ日に複数あれば id の順 (画面は先頭を既定にし、変えられるようにする)。
pub fn card_exchange_show_candidates(today: &str, my_attended: &[CardShowRef]) -> Vec<String> {
    let Some(today_date) = parse_date(today) else {
        return Vec::new();
    };
    for offset in [0i64, 1] {
        let day = today_date - chrono::Duration::days(offset);
        let mut ids: Vec<String> = my_attended
            .iter()
            .filter(|r| parse_date(&r.date) == Some(day))
            .map(|r| r.show_id.clone())
            .collect();
        if !ids.is_empty() {
            ids.sort();
            ids.dedup();
            return ids;
        }
    }
    Vec::new()
}

/// 名刺入れを公演ごと (公演が無いものは受け取った日ごと) に束ね、新しい束から並べる。
pub fn card_case_sections(entries: &[CardCaseEntry]) -> Vec<CardCaseSection> {
    use std::collections::BTreeMap;
    // (日付, 公演 id or "") → 束
    let mut groups: BTreeMap<(String, String), Vec<&CardCaseEntry>> = BTreeMap::new();
    for e in entries {
        let received_day = jst_day_of(&e.received_at);
        let (date, key) = match (&e.show_id, &e.show_date) {
            (Some(id), Some(d)) if !id.is_empty() && !d.is_empty() => (d.clone(), id.clone()),
            (Some(id), _) if !id.is_empty() => (received_day, id.clone()),
            _ => (received_day, String::new()),
        };
        groups.entry((date, key)).or_default().push(e);
    }
    let mut sections: Vec<(String, CardCaseSection)> = groups
        .into_iter()
        .map(|((date, key), mut items)| {
            items.sort_by(|a, b| b.received_at.cmp(&a.received_at).then(a.id.cmp(&b.id)));
            let latest = items
                .first()
                .map(|e| e.received_at.clone())
                .unwrap_or_default();
            let section = CardCaseSection {
                show_id: (!key.is_empty()).then_some(key),
                date,
                entry_ids: items.into_iter().map(|e| e.id.clone()).collect(),
            };
            (latest, section)
        })
        .collect();
    // 新しい日付が上。同じ日なら最後に受け取った名刺のある束が上。
    sections.sort_by(|(la, a), (lb, b)| b.date.cmp(&a.date).then_with(|| lb.cmp(la)));
    sections.into_iter().map(|(_, s)| s).collect()
}

// ---------------------------------------------------------------------------
// リンク
// ---------------------------------------------------------------------------

pub fn card_link_kinds() -> Vec<CardLinkKindInfo> {
    use CardLinkKind::*;
    [X, Bluesky, Misskey, YouTube, Instagram, TikTok, Web]
        .into_iter()
        .map(|kind| CardLinkKindInfo {
            kind,
            label: link_label(kind).into(),
            placeholder: match kind {
                X | Instagram | TikTok => "@idollivedb",
                Bluesky => "idollivedb.bsky.social",
                Misskey => "@idollivedb@misskey.io",
                YouTube => "@idollivedb",
                Web => "https://",
            }
            .into(),
        })
        .collect()
}

fn link_label(kind: CardLinkKind) -> &'static str {
    match kind {
        CardLinkKind::X => "X",
        CardLinkKind::Bluesky => "Bluesky",
        CardLinkKind::Misskey => "Misskey",
        CardLinkKind::YouTube => "YouTube",
        CardLinkKind::Instagram => "Instagram",
        CardLinkKind::TikTok => "TikTok",
        CardLinkKind::Web => "Web",
    }
}

/// 入力されたリンクを保存の形に揃える。URL を貼られても、`@` 付きで書かれても同じ形になる。
/// 形が合わなければ None。
pub fn normalize_link(link: &CardLink) -> Option<CardLink> {
    let raw = link.value.trim();
    if raw.is_empty() || char_len(raw) > MAX_LINK_VALUE_CHARS {
        return None;
    }
    // URL を貼られたら、種類が合っていればハンドルに直す。
    if raw.starts_with("http://") || raw.starts_with("https://") {
        if link.kind == CardLinkKind::Web {
            return Some(CardLink {
                kind: CardLinkKind::Web,
                value: raw.to_string(),
            });
        }
        let parsed = card_link_from_url(raw)?;
        return (parsed.kind == link.kind).then_some(parsed);
    }
    let handle = raw.trim_start_matches('@');
    let value = match link.kind {
        CardLinkKind::X | CardLinkKind::Instagram | CardLinkKind::TikTok => {
            is_simple_handle(handle).then(|| handle.to_string())?
        }
        CardLinkKind::YouTube => is_simple_handle(handle).then(|| handle.to_string())?,
        CardLinkKind::Bluesky => is_host_like(handle).then(|| handle.to_lowercase())?,
        CardLinkKind::Misskey => {
            let (user, host) = handle.split_once('@')?;
            (is_simple_handle(user) && is_host_like(host))
                .then(|| format!("{user}@{}", host.to_lowercase()))?
        }
        CardLinkKind::Web => {
            is_host_like(raw.split('/').next().unwrap_or("")).then(|| format!("https://{raw}"))?
        }
    };
    Some(CardLink {
        kind: link.kind,
        value,
    })
}

pub fn card_link_view(link: &CardLink) -> CardLinkView {
    let v = &link.value;
    let (display, url) = match link.kind {
        CardLinkKind::X => (format!("@{v}"), format!("https://x.com/{v}")),
        CardLinkKind::Instagram => (format!("@{v}"), format!("https://www.instagram.com/{v}")),
        CardLinkKind::TikTok => (format!("@{v}"), format!("https://www.tiktok.com/@{v}")),
        CardLinkKind::YouTube => (format!("@{v}"), format!("https://www.youtube.com/@{v}")),
        CardLinkKind::Bluesky => (v.clone(), format!("https://bsky.app/profile/{v}")),
        CardLinkKind::Misskey => {
            let (user, host) = v.split_once('@').unwrap_or((v, "misskey.io"));
            (format!("@{v}"), format!("https://{host}/@{user}"))
        }
        CardLinkKind::Web => {
            let shown = v
                .trim_start_matches("https://")
                .trim_start_matches("http://");
            (shown.trim_end_matches('/').to_string(), v.clone())
        }
    };
    CardLinkView {
        kind: link.kind,
        label: link_label(link.kind).into(),
        display,
        url,
    }
}

/// URL から SNS のリンクを読み取る。知っている SNS でなければ Web のリンク。
pub fn card_link_from_url(url: &str) -> Option<CardLink> {
    let url = url.trim();
    let rest = url
        .strip_prefix("https://")
        .or_else(|| url.strip_prefix("http://"))?;
    let (host, path) = rest.split_once('/').unwrap_or((rest, ""));
    let host = host.to_lowercase();
    let host = host
        .trim_start_matches("www.")
        .trim_start_matches("mobile.");
    let path = path.split(['?', '#']).next().unwrap_or("");
    let first = path.split('/').find(|s| !s.is_empty()).unwrap_or("");
    let handle = |s: &str| {
        let h = s.trim_start_matches('@');
        is_simple_handle(h).then(|| h.to_string())
    };
    let sns = match host {
        "x.com" | "twitter.com" => handle(first).map(|v| (CardLinkKind::X, v)),
        "instagram.com" => handle(first).map(|v| (CardLinkKind::Instagram, v)),
        "tiktok.com" if first.starts_with('@') => handle(first).map(|v| (CardLinkKind::TikTok, v)),
        "youtube.com" if first.starts_with('@') => {
            handle(first).map(|v| (CardLinkKind::YouTube, v))
        }
        "bsky.app" => {
            let mut parts = path.split('/').filter(|s| !s.is_empty());
            match (parts.next(), parts.next()) {
                (Some("profile"), Some(h)) if is_host_like(h) => {
                    Some((CardLinkKind::Bluesky, h.to_lowercase()))
                }
                _ => None,
            }
        }
        "misskey.io" => first
            .strip_prefix('@')
            .filter(|u| is_simple_handle(u) && !u.contains('@'))
            .map(|u| (CardLinkKind::Misskey, format!("{u}@misskey.io"))),
        _ => None,
    };
    let reserved = matches!(
        first,
        "home" | "i" | "intent" | "share" | "search" | "explore"
    );
    match sns {
        Some((kind, value)) if !(kind == CardLinkKind::X && reserved) => {
            Some(CardLink { kind, value })
        }
        _ if is_host_like(host) => Some(CardLink {
            kind: CardLinkKind::Web,
            value: url.into(),
        }),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// 自分の QR
// ---------------------------------------------------------------------------

/// 自分の QR にする URL を保存の形に揃える。`https://` の無い `lit.link/fuga` は補う。
/// http(s) の URL でない・長すぎる・アプリの名刺の URL (交換用の QR と同じもの) なら None。
pub fn normalize_card_qr_url(raw: &str) -> Option<String> {
    let link = normalize_link(&CardLink {
        kind: CardLinkKind::Web,
        value: raw.trim().to_string(),
    })?;
    let is_card = card_payload(&link.value).is_some() && link.value.contains('#');
    (!is_card).then_some(link.value)
}

/// 自分の QR を名刺のリンクの 1 本として出す形 (題は「QR」、押せば開く)。
pub fn card_qr_link_view(url: &str) -> CardLinkView {
    let web = card_link_view(&CardLink {
        kind: CardLinkKind::Web,
        value: url.to_string(),
    });
    CardLinkView {
        label: "QR".into(),
        ..web
    }
}

// ---------------------------------------------------------------------------
// 名刺のデザイン
//
// 書体と並びをひとまとめにした 3 つのデザイン (入場証・かしこまった名刺・ポップ) と、
// 自分で作った画像をそのまま名刺の顔にする「自作の画像」から選ぶ。細かい見た目は選ばせない。
// 名刺の中身にはデザインの番号だけを入れる。自作の画像そのものは QR に入らないので、
// 画像が手元に無い (QR だけで受け取った・Web で開いた) ときは入場証で描く。
//
// 書体のファイルは iOS / Android / Web で同じものを同梱する (`fonts/card-name/`、
// 作り方は `tools/build_card_name_fonts.py`)。
// ---------------------------------------------------------------------------

/// 名刺のデザイン。並び順は編集画面の選択肢の順。番号 (`design_code`) と保存のキーは変えない。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CardDesign {
    /// 入場証 (既定)。担当色の帯・ストラップの穴・太いゴシック。
    #[default]
    Pass,
    /// かしこまった名刺。明朝・白い紙に端正な組み。担当色は細い罫と判子だけ。
    Formal,
    /// ポップ。丸い太字・太い線・担当色をはっきり。
    Pop,
    /// 自作の画像。自分で作った名刺の画像 (表・任意で裏) がそのまま名刺の顔になる。
    Custom,
}

/// 同梱する名前の書体。デザインが書体を決める (書体だけを選ぶことはしない)。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum CardNameFont {
    /// 太いゴシック (入場証・自作の画像)。
    #[default]
    Gothic,
    /// 明朝 (かしこまった名刺)。
    Mincho,
    /// ポップ体 (ポップ・プロフィール帳の題)。
    Pop,
}

/// 書体 1 つの名乗り。端末はファイルの名前と PostScript 名で書体を引き、Web は `key` で引く。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardNameFontInfo {
    pub font: CardNameFont,
    /// 英字のキー (Web の書体の名前 `IMAS Card <key>` に使う)。
    pub key: String,
    /// 書体の名前 (「明朝」)。
    pub label: String,
    /// 同梱するファイルの名前 (拡張子なし)。Android の res/font にも置ける形 (英小文字と `_`)。
    pub file_stem: String,
    /// 端末が書体を引く PostScript 名。
    pub postscript_name: String,
    /// 元の書体の名前 (「このアプリについて」のクレジットに出す)。
    pub family_name: String,
    /// 書体の使用許諾 (「SIL Open Font License 1.1」)。
    pub license: String,
    /// 書体の配布元 (クレジットから開く)。
    pub source_url: String,
}

/// デザイン 1 つの名乗り。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardDesignInfo {
    pub design: CardDesign,
    /// 保存・Web の `data-design` に使う英字のキー。
    pub key: String,
    /// 編集画面に出す名前 (「かしこまった名刺」)。
    pub label: String,
    /// 名前に使う書体 (プロフィール帳もこの書体)。
    pub font: CardNameFontInfo,
    /// 自作の画像を名刺の顔にするデザイン (表の画像が要る)。
    pub uses_face_image: bool,
}

const ALL_NAME_FONTS: [CardNameFont; 3] = [
    CardNameFont::Gothic,
    CardNameFont::Mincho,
    CardNameFont::Pop,
];

const ALL_DESIGNS: [CardDesign; 4] = [
    CardDesign::Pass,
    CardDesign::Formal,
    CardDesign::Pop,
    CardDesign::Custom,
];

/// 同梱する書体の一覧 (「このアプリについて」のクレジット・同梱の検査に使う)。
pub fn card_name_fonts() -> Vec<CardNameFontInfo> {
    ALL_NAME_FONTS
        .into_iter()
        .map(card_name_font_info)
        .collect()
}

pub fn card_name_font_info(font: CardNameFont) -> CardNameFontInfo {
    let (key, label, postscript, family) = match font {
        CardNameFont::Gothic => (
            "gothic",
            "ゴシック",
            "ZenKakuGothicNew-Black",
            "Zen Kaku Gothic New",
        ),
        CardNameFont::Mincho => ("mincho", "明朝", "ZenOldMincho-Black", "Zen Old Mincho"),
        CardNameFont::Pop => ("pop", "ポップ", "MochiyPopOne-Regular", "Mochiy Pop One"),
    };
    CardNameFontInfo {
        font,
        key: key.into(),
        label: label.into(),
        file_stem: format!("card_name_{key}"),
        postscript_name: postscript.into(),
        family_name: family.into(),
        license: "SIL Open Font License 1.1".into(),
        source_url: format!(
            "https://fonts.google.com/specimen/{}",
            family.replace(' ', "+")
        ),
    }
}

/// 編集画面のデザインの選択肢 (先頭が既定)。
pub fn card_designs() -> Vec<CardDesignInfo> {
    ALL_DESIGNS.into_iter().map(card_design_info).collect()
}

pub fn card_design_info(design: CardDesign) -> CardDesignInfo {
    let (key, label, font) = match design {
        CardDesign::Pass => ("pass", "入場証", CardNameFont::Gothic),
        CardDesign::Formal => ("formal", "かしこまった名刺", CardNameFont::Mincho),
        CardDesign::Pop => ("pop", "ポップ", CardNameFont::Pop),
        CardDesign::Custom => ("custom", "自作の画像", CardNameFont::Gothic),
    };
    CardDesignInfo {
        design,
        key: key.into(),
        label: label.into(),
        font: card_name_font_info(font),
        uses_face_image: design == CardDesign::Custom,
    }
}

/// 名刺を描くデザイン。自作の画像の名刺でも、画像が手元に無ければ (QR だけで受け取った・
/// Web で開いた・自分の画像を消した) 入場証で描く。
pub fn producer_card_display_design(card: &ProducerCard, has_face_image: bool) -> CardDesignInfo {
    let design = card.design.unwrap_or_default();
    if design == CardDesign::Custom && !has_face_image {
        return card_design_info(CardDesign::Pass);
    }
    card_design_info(design)
}

pub fn card_design_key(design: CardDesign) -> String {
    card_design_info(design).key
}

/// 保存のキーからデザインを戻す。空・知らないキーは None (既定のデザインで出す)。
/// 書体を選んでいた頃のキー (`gothic` / `mincho` / `maru` / `pop` / `hand`) も近いデザインに読み替える。
pub fn card_design_from_key(key: &str) -> Option<CardDesign> {
    if let Some(found) = ALL_DESIGNS
        .into_iter()
        .find(|d| card_design_info(*d).key == key)
    {
        return Some(found);
    }
    match key {
        "gothic" => Some(CardDesign::Pass),
        "mincho" => Some(CardDesign::Formal),
        "maru" | "hand" => Some(CardDesign::Pop),
        _ => None,
    }
}

/// 中身に書くデザインの番号。書体を選んでいた頃の番号 (0 ゴシック・1 明朝・2 丸ゴシック・
/// 3 ポップ・4 手書き) と同じ場所に入れるので、明朝とポップは同じ番号のまま
/// (書体の版のアプリでも、かしこまった名刺は明朝・ポップはポップ体で出る)。
fn design_code(design: CardDesign) -> u8 {
    match design {
        CardDesign::Pass => 0,
        CardDesign::Formal => 1,
        CardDesign::Pop => 3,
        CardDesign::Custom => 5,
    }
}

/// 番号からデザインを戻す。書体の頃の丸ゴシック・手書きはポップに読み替える。
/// 知らない番号 (新しい版のアプリが足したデザイン) は既定のデザインで読む
/// (デザインが分からないだけで名刺を読めなくはしない)。
fn design_from_code(code: u8) -> Option<CardDesign> {
    let design = match code {
        1 => CardDesign::Formal,
        2..=4 => CardDesign::Pop,
        5 => CardDesign::Custom,
        _ => CardDesign::Pass,
    };
    (design != CardDesign::default()).then_some(design)
}

fn is_simple_handle(s: &str) -> bool {
    !s.is_empty()
        && s.len() <= 64
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'.' || b == b'-')
}

fn is_host_like(s: &str) -> bool {
    s.contains('.')
        && !s.starts_with('.')
        && !s.ends_with('.')
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'-')
}

// ---------------------------------------------------------------------------
// 公演の縮め方
// ---------------------------------------------------------------------------

/// 受け取った日時 (ISO 8601) を JST の日付にする。端末は UTC で保存するので、
/// 先頭 10 文字をそのまま使うと深夜 0〜9 時に受け取った名刺が前の日に入る。
fn jst_day_of(received_at: &str) -> String {
    chrono::DateTime::parse_from_rfc3339(received_at)
        .map(|t| {
            t.with_timezone(&crate::domain::jst_day::jst())
                .format("%Y-%m-%d")
                .to_string()
        })
        .unwrap_or_else(|_| received_at.chars().take(10).collect())
}

fn parse_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d").ok()
}

fn show_stamp(show_id: &str, date: &str) -> Option<CardShowStamp> {
    let day = (parse_date(date)? - epoch()).num_days();
    let day = u32::try_from(day).ok()?;
    Some(CardShowStamp {
        day,
        tag: fingerprint(show_id),
    })
}

/// FNV-1a 32 bit を 16 bit に畳む。端末・Web で同じ値になるよう、ここ以外で計算しない。
fn fingerprint(id: &str) -> u16 {
    let mut h: u32 = 0x811c_9dc5;
    for b in id.as_bytes() {
        h ^= u32::from(*b);
        h = h.wrapping_mul(0x0100_0193);
    }
    ((h >> 16) ^ (h & 0xffff)) as u16
}

fn day_to_date(day: u32) -> String {
    (epoch() + chrono::Duration::days(i64::from(day)))
        .format("%Y-%m-%d")
        .to_string()
}

// ---------------------------------------------------------------------------
// 中身の書き方 (版 1)
//
//   u8  版
//   u8  旗 (bit0 since_year / bit1 show_count / bit2 song_count / bit3 next_show / bit4 truncated
//          / bit5 design / bit6 qr_url)
//   str 名前, str ひとこと
//   [varint since_year] [varint show_count] [varint song_count] [str next_show_id]
//   varint issued_on (日数)
//   varint 担当の数, str × n
//   varint リンクの数, (u8 種類, str) × n
//   varint 公演の数, (varint 前の公演からの日数, u16 指紋) × n   (先頭は起点からの日数)
//   [u8 デザインの番号] [str 自分の QR の URL]                    (旗が立っているときだけ)
//
//   str = varint バイト数 + UTF-8
//
// デザインと自分の QR は**後から足した任意の項目**なので、版は 1 のまま旗のビットで持つ
// (デザインの番号は、書体を選んでいた頃の書体の番号と同じ場所・同じ番号の振り方)。
// 既定のデザインで自分の QR も無い名刺は、足す前と 1 バイトも変わらない (古いアプリでも読める)。
// 項目がある名刺を古いアプリが読むと、末尾に余りがあるので「読めない名刺」になる
// (誤読はしない)。版を上げると、項目の無い名刺まで古いアプリで読めなくなるので上げない。
// ---------------------------------------------------------------------------

const FLAG_DESIGN: u8 = 1 << 5;
const FLAG_QR_URL: u8 = 1 << 6;

fn write_card(card: &ProducerCard) -> Vec<u8> {
    let mut w = Vec::with_capacity(256);
    w.push(FORMAT_VERSION);
    let mut flags = 0u8;
    if card.since_year.is_some() {
        flags |= 1;
    }
    if card.show_count.is_some() {
        flags |= 1 << 1;
    }
    if card.song_count.is_some() {
        flags |= 1 << 2;
    }
    if card.next_show_id.is_some() {
        flags |= 1 << 3;
    }
    if card.attended_truncated {
        flags |= 1 << 4;
    }
    let design = card.design.filter(|d| *d != CardDesign::default());
    if design.is_some() {
        flags |= FLAG_DESIGN;
    }
    if card.qr_url.is_some() {
        flags |= FLAG_QR_URL;
    }
    w.push(flags);
    put_str(&mut w, &card.name);
    put_str(&mut w, &card.message);
    if let Some(y) = card.since_year {
        put_varint(&mut w, u64::from(y));
    }
    if let Some(n) = card.show_count {
        put_varint(&mut w, u64::from(n));
    }
    if let Some(n) = card.song_count {
        put_varint(&mut w, u64::from(n));
    }
    if let Some(id) = &card.next_show_id {
        put_str(&mut w, id);
    }
    let issued = show_stamp("", &card.issued_on).map(|s| s.day).unwrap_or(0);
    put_varint(&mut w, u64::from(issued));
    put_varint(&mut w, card.oshi_idol_ids.len() as u64);
    for id in &card.oshi_idol_ids {
        put_str(&mut w, id);
    }
    put_varint(&mut w, card.links.len() as u64);
    for l in &card.links {
        w.push(link_kind_code(l.kind));
        put_str(&mut w, &l.value);
    }
    put_varint(&mut w, card.attended.len() as u64);
    let mut prev = 0u32;
    for s in &card.attended {
        put_varint(&mut w, u64::from(s.day - prev));
        w.extend_from_slice(&s.tag.to_le_bytes());
        prev = s.day;
    }
    if let Some(design) = design {
        w.push(design_code(design));
    }
    if let Some(url) = &card.qr_url {
        put_str(&mut w, url);
    }
    w
}

fn read_card(bytes: &[u8]) -> Option<ProducerCard> {
    let mut r = Reader { bytes, pos: 0 };
    if r.u8()? != FORMAT_VERSION {
        return None;
    }
    let flags = r.u8()?;
    let name = r.str()?;
    let message = r.str()?;
    let since_year = if flags & 1 != 0 {
        Some(u16::try_from(r.varint()?).ok()?)
    } else {
        None
    };
    let show_count = if flags & (1 << 1) != 0 {
        Some(u32::try_from(r.varint()?).ok()?)
    } else {
        None
    };
    let song_count = if flags & (1 << 2) != 0 {
        Some(u32::try_from(r.varint()?).ok()?)
    } else {
        None
    };
    let next_show_id = if flags & (1 << 3) != 0 {
        Some(r.str()?)
    } else {
        None
    };
    let issued_on = day_to_date(u32::try_from(r.varint()?).ok()?);
    let oshi_n = r.count(MAX_OSHI as usize)?;
    let mut oshi_idol_ids = Vec::with_capacity(oshi_n);
    for _ in 0..oshi_n {
        oshi_idol_ids.push(r.str()?);
    }
    let link_n = r.count(MAX_LINKS as usize)?;
    let mut links = Vec::with_capacity(link_n);
    for _ in 0..link_n {
        let kind = link_kind_from_code(r.u8()?)?;
        links.push(CardLink {
            kind,
            value: r.str()?,
        });
    }
    let show_n = r.count(bytes.len())?;
    let mut attended = Vec::with_capacity(show_n);
    let mut day = 0u32;
    for _ in 0..show_n {
        day = day.checked_add(u32::try_from(r.varint()?).ok()?)?;
        let tag = u16::from_le_bytes([r.u8()?, r.u8()?]);
        attended.push(CardShowStamp { day, tag });
    }
    let design = if flags & FLAG_DESIGN != 0 {
        design_from_code(r.u8()?)
    } else {
        None
    };
    let qr_url = if flags & FLAG_QR_URL != 0 {
        Some(r.str()?)
    } else {
        None
    };
    // 知らない旗 (bit7) が立っている名刺は、知らない項目が続いているはずなので読まない。
    if flags & (1 << 7) != 0 || r.pos != bytes.len() || name.trim().is_empty() {
        return None;
    }
    // 手で組んだ名刺 (QR・名刺ファイル・近くの端末から届くもの) が、アプリの作る名刺より
    // 大きいことはない。上限を超えるものは読まない (名前が何万字の名刺を名刺入れに入れない)。
    let too_long = char_len(&name) > MAX_NAME_CHARS as usize
        || char_len(&message) > MAX_MESSAGE_CHARS as usize
        || oshi_idol_ids.iter().any(|id| id.len() > MAX_ID_BYTES)
        || links
            .iter()
            .any(|l| char_len(&l.value) > MAX_LINK_VALUE_CHARS)
        || next_show_id
            .as_ref()
            .is_some_and(|id| id.len() > MAX_ID_BYTES);
    if too_long {
        return None;
    }
    // リンクと自分の QR は、アプリが作るときと同じ形 (正規化済み) のものだけを残す。
    // 手で組んだ名刺に `javascript:` などの URL を入れて、押した人に開かせないため
    // (名刺ごと捨てると、前の版で入れた紙の名刺が読めなくなることがあるので、その 1 本だけ落とす)。
    let links: Vec<CardLink> = links
        .into_iter()
        .filter(|l| normalize_link(l).as_ref() == Some(l))
        .collect();
    let qr_url = qr_url.filter(|u| normalize_card_qr_url(u).as_deref() == Some(u.as_str()));
    Some(ProducerCard {
        name,
        message,
        since_year,
        oshi_idol_ids,
        links,
        show_count,
        song_count,
        next_show_id,
        attended,
        attended_truncated: flags & (1 << 4) != 0,
        issued_on,
        design,
        qr_url,
    })
}

fn link_kind_code(kind: CardLinkKind) -> u8 {
    match kind {
        CardLinkKind::X => 0,
        CardLinkKind::Bluesky => 1,
        CardLinkKind::Misskey => 2,
        CardLinkKind::YouTube => 3,
        CardLinkKind::Instagram => 4,
        CardLinkKind::TikTok => 5,
        CardLinkKind::Web => 6,
    }
}

fn link_kind_from_code(code: u8) -> Option<CardLinkKind> {
    Some(match code {
        0 => CardLinkKind::X,
        1 => CardLinkKind::Bluesky,
        2 => CardLinkKind::Misskey,
        3 => CardLinkKind::YouTube,
        4 => CardLinkKind::Instagram,
        5 => CardLinkKind::TikTok,
        6 => CardLinkKind::Web,
        _ => return None,
    })
}

fn put_varint(w: &mut Vec<u8>, mut v: u64) {
    loop {
        let b = (v & 0x7f) as u8;
        v >>= 7;
        if v == 0 {
            w.push(b);
            return;
        }
        w.push(b | 0x80);
    }
}

fn put_str(w: &mut Vec<u8>, s: &str) {
    put_varint(w, s.len() as u64);
    w.extend_from_slice(s.as_bytes());
}

struct Reader<'a> {
    bytes: &'a [u8],
    pos: usize,
}

impl Reader<'_> {
    fn u8(&mut self) -> Option<u8> {
        let b = *self.bytes.get(self.pos)?;
        self.pos += 1;
        Some(b)
    }
    fn varint(&mut self) -> Option<u64> {
        let mut v = 0u64;
        for shift in (0..64).step_by(7) {
            let b = self.u8()?;
            v |= u64::from(b & 0x7f) << shift;
            if b & 0x80 == 0 {
                return Some(v);
            }
        }
        None
    }
    fn count(&mut self, max: usize) -> Option<usize> {
        let n = usize::try_from(self.varint()?).ok()?;
        (n <= max).then_some(n)
    }
    fn str(&mut self) -> Option<String> {
        let n = usize::try_from(self.varint()?).ok()?;
        let end = self.pos.checked_add(n)?;
        let s = std::str::from_utf8(self.bytes.get(self.pos..end)?)
            .ok()?
            .to_string();
        self.pos = end;
        Some(s)
    }
}

// ---------------------------------------------------------------------------
// base64url (パディング無し)。依存を増やさないため自前。
// ---------------------------------------------------------------------------

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

fn base64url_encode(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let n = (u32::from(chunk[0]) << 16)
            | (u32::from(*chunk.get(1).unwrap_or(&0)) << 8)
            | u32::from(*chunk.get(2).unwrap_or(&0));
        let chars = chunk.len() + 1;
        for i in 0..chars {
            out.push(B64[((n >> (18 - 6 * i)) & 63) as usize] as char);
        }
    }
    out
}

fn base64url_decode(s: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(s.len() * 3 / 4);
    let mut buf = 0u32;
    let mut bits = 0u32;
    for c in s.bytes() {
        let v = B64.iter().position(|&b| b == c)? as u32;
        buf = (buf << 6) | v;
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buf >> bits) as u8);
            buf &= (1 << bits) - 1;
        }
    }
    Some(out)
}

// ---------------------------------------------------------------------------

fn char_len(s: &str) -> usize {
    s.chars().count()
}

fn truncate_chars(s: &str, max: usize) -> String {
    s.chars().take(max).collect()
}

// ---------------------------------------------------------------------------
// 自分の名刺の材料 (アプリの記録から)
// ---------------------------------------------------------------------------

/// 自分の名刺に載せる記録。参加を付けた公演を「行った公演」と「次の現場」に分ける。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardRecordSummary {
    /// 今日までに行った公演 (日付の昇順)。共通点に使う。
    pub attended_past: Vec<CardShowRef>,
    /// 行った公演の数。
    pub show_count: u32,
    /// 今日以降でいちばん早い参加予定の公演。
    pub next_show_id: Option<String>,
}

/// 参加を付けた公演 (今後の参加予定も混ざる) を、名刺に載せる形に分ける。
/// 今日の公演は「行った公演」に数え、次の現場には明日以降を出す (会場で交換する日の公演が
/// 次の現場に出ると、その日のうちに古くなる)。日付の読めない公演はどちらにも入れない。
pub fn producer_card_record_summary(today: &str, attended: &[CardShowRef]) -> CardRecordSummary {
    let Some(today) = parse_date(today) else {
        return CardRecordSummary {
            attended_past: Vec::new(),
            show_count: 0,
            next_show_id: None,
        };
    };
    let mut past: Vec<(NaiveDate, &CardShowRef)> = Vec::new();
    let mut next: Option<(NaiveDate, &CardShowRef)> = None;
    let mut seen = std::collections::HashSet::new();
    for r in attended {
        if !seen.insert(r.show_id.as_str()) {
            continue;
        }
        let Some(day) = parse_date(&r.date) else {
            continue;
        };
        if day <= today {
            past.push((day, r));
        } else if next.is_none_or(|(d, n)| (day, &r.show_id) < (d, &n.show_id)) {
            next = Some((day, r));
        }
    }
    past.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.show_id.cmp(&b.1.show_id)));
    CardRecordSummary {
        show_count: past.len() as u32,
        attended_past: past.into_iter().map(|(_, r)| r.clone()).collect(),
        next_show_id: next.map(|(_, r)| r.show_id.clone()),
    }
}

/// 紙に刷る名刺の日付 (`2026.10.06 時点`)。記録の数がその日のものだと分かるように刷る。
pub fn card_issued_label(issued_on: &str) -> String {
    match parse_date(issued_on) {
        Some(d) => format!("{} 時点", d.format("%Y.%m.%d")),
        None => String::new(),
    }
}

// ---------------------------------------------------------------------------
// 名刺の表 (91:55) の組み
//
// 名刺そのものは日本の名刺の比 (91:55) の横長の 1 枚。表に載せるのは名前・P 歴・名刺の写真・
// 担当 (判子かアイコンを小さく並べる)・ハンドル 1 つだけで、担当の一覧・リンクの一覧・記録・
// ひとことは名刺の外 (下) に出す。画面の名刺・紙に刷る画像・Web の名刺で同じ組みにする。
//
// 担当はブランドごとにまとめて並べる。枠が足りないときも、まずブランドごとに 1 人 (そのブランドで
// 並びが先の担当) を載せ、残りの枠に 2 人目以降を並び順で入れる (担当の多い人でもブランドが抜け
// 落ちないように)。名刺に載せる担当そのもの (アプリの担当から `MAX_OSHI` 人) も同じ規則で選ぶ。
// ---------------------------------------------------------------------------

/// 名刺の表に担当を並べる枠の数 (名刺に載る担当の上限と同じ。名刺に載る担当は全員表に出る)。
/// これより多い担当が来たときだけ、最後の枠を「+N」にして数で畳む。
pub const CARD_FACE_OSHI_SLOTS: u32 = MAX_OSHI;

/// 担当の名前を表の 1 行に並べる上限の文字数 (「 担当」まで含めて)。名刺の写真の横の幅に
/// 紙の上で読める大きさで収まる長さ。超えるときは「765AS 5人 担当」と数で言う。
const CARD_FACE_CAPTION_MAX_CHARS: usize = 18;

/// 担当 1 人の名前とブランド。ブランドごとに並べる・選ぶのに使う
/// (端末はマスタから、Web は台帳 `p/catalog.json` の `oshiEntries` から渡す)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CardOshiEntry {
    pub idol_id: String,
    /// 判子の下に刷る名前。
    pub name: String,
    /// ブランドの id。分からなければ空 (空どうしは同じブランドとして扱わない)。
    pub brand_id: String,
    /// 表に刷るブランドの略称 (「765AS」「学マス」)。分からなければ空。
    pub brand_label: String,
}

/// 名刺の表で 1 つのブランドにまとめて並べる担当。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardFaceOshiGroup {
    /// 判子の並びの下に刷るブランドの略称 (`CardFace.oshi_caption` が無いときだけ刷る。空なら刷らない)。
    pub brand_label: String,
    /// このブランドの担当 (名刺の並び順)。
    pub idol_ids: Vec<String>,
}

/// 名刺の表に載せるもの。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CardFace {
    /// 表に並べる担当 (`oshi_groups` を順に平らにしたもの。描けない担当は除いてから数える)。
    pub oshi_idol_ids: Vec<String>,
    /// 表に並べる担当のブランドごとのまとまり (ブランドは名刺の並びで先に出た順、中は名刺の並び順)。
    pub oshi_groups: Vec<CardFaceOshiGroup>,
    /// 判子の下に刷る 1 行 (「星井美希 担当」「765AS 5人 担当」)。ブランドが 2 つ以上なら None で、
    /// そのときは名前の代わりにまとまりごとにブランドの略称を判子の下に刷る。
    pub oshi_caption: Option<String>,
    /// 表に並べきれず数で畳んだ担当の人数 (「+2」)。0 なら畳まない。
    pub more_oshi: u32,
    /// 表に刷るハンドル 1 つ (X があれば X、無ければ先頭のリンク)。自分の QR は裏に刷るので選ばない。
    pub handle: Option<CardLinkView>,
    /// 帯・印字の P 歴 (「SINCE 2014」)。
    pub since_imprint: Option<String>,
    /// 裏に刷る日付 (「2026.10.06 時点」)。記録の数がその日のものだと分かるように。
    pub issued_label: String,
}

/// 並びのまま渡された担当から `slots` 人を選ぶ (選んだ位置を並びの順で返す)。
/// まずブランドごとに並びが先の 1 人、残りの枠に 2 人目以降を並び順で。ブランドが枠より多ければ
/// 並びで先に出たブランドから。
fn pick_oshi_by_brand(oshi: &[&CardOshiEntry], slots: usize) -> Vec<usize> {
    let mut picked = vec![false; oshi.len()];
    let mut count = 0;
    let mut brands: Vec<&str> = Vec::new();
    for (i, o) in oshi.iter().enumerate() {
        if count == slots {
            break;
        }
        let known = !o.brand_id.is_empty();
        if known && brands.contains(&o.brand_id.as_str()) {
            continue;
        }
        if known {
            brands.push(&o.brand_id);
        }
        picked[i] = true;
        count += 1;
    }
    for p in picked.iter_mut() {
        if count == slots {
            break;
        }
        if !*p {
            *p = true;
            count += 1;
        }
    }
    picked.iter().enumerate().filter(|(_, p)| **p).map(|(i, _)| i).collect()
}

/// 名刺に載せる担当 (アプリの担当の並びから `MAX_OSHI` 人)。ブランドごとに 1 人を先に確保し、
/// 残りを並び順で埋める。返す並びはアプリの並びのまま。同じ id は 1 度だけ数える。
pub fn producer_card_pick_oshi(oshi: &[CardOshiEntry]) -> Vec<String> {
    let mut seen: Vec<&str> = Vec::new();
    let unique: Vec<&CardOshiEntry> = oshi
        .iter()
        .filter(|o| {
            if seen.contains(&o.idol_id.as_str()) {
                false
            } else {
                seen.push(&o.idol_id);
                true
            }
        })
        .collect();
    pick_oshi_by_brand(&unique, MAX_OSHI as usize)
        .into_iter()
        .map(|i| unique[i].idol_id.clone())
        .collect()
}

/// 判子の下の 1 行。ブランドが 1 つのときだけ名前を (長ければ数で)。
fn card_face_caption(groups: &[CardFaceOshiGroup], names: &[&str]) -> Option<String> {
    let [group] = groups else { return None };
    let caption = format!("{} 担当", names.join("・"));
    if caption.chars().count() <= CARD_FACE_CAPTION_MAX_CHARS {
        return Some(caption);
    }
    let count = group.idol_ids.len();
    Some(if group.brand_label.is_empty() {
        format!("{count}人 担当")
    } else {
        format!("{} {count}人 担当", group.brand_label)
    })
}

/// 名刺の表の組み。`drawable` は端末 (Web は台帳) が描ける担当とそのブランド
/// (相手の方が新しいデータを持っていて手元に無いアイドルは出さない。その分は畳む数にも数えない)。
pub fn producer_card_face(card: &ProducerCard, drawable: &[CardOshiEntry]) -> CardFace {
    let oshi: Vec<&CardOshiEntry> = card
        .oshi_idol_ids
        .iter()
        .filter_map(|id| drawable.iter().find(|d| &d.idol_id == id))
        .collect();
    let slots = CARD_FACE_OSHI_SLOTS as usize;
    let (picked, more) = if oshi.len() <= slots {
        ((0..oshi.len()).collect::<Vec<_>>(), 0)
    } else {
        let picked = pick_oshi_by_brand(&oshi, slots - 1);
        let more = (oshi.len() - picked.len()) as u32;
        (picked, more)
    };
    // ブランドごとにまとめる (ブランドは並びで先に出た順)。
    let mut grouped: Vec<(&str, Vec<&CardOshiEntry>)> = Vec::new();
    for o in picked.iter().map(|&i| oshi[i]) {
        match grouped.iter_mut().find(|(b, _)| !b.is_empty() && *b == o.brand_id) {
            Some((_, members)) => members.push(o),
            None => grouped.push((&o.brand_id, vec![o])),
        }
    }
    let names: Vec<&str> = grouped.iter().flat_map(|(_, m)| m.iter().map(|o| o.name.as_str())).collect();
    let groups: Vec<CardFaceOshiGroup> = grouped
        .iter()
        .map(|(_, members)| CardFaceOshiGroup {
            brand_label: members[0].brand_label.clone(),
            idol_ids: members.iter().map(|o| o.idol_id.clone()).collect(),
        })
        .collect();
    let shown: Vec<String> = groups.iter().flat_map(|g| g.idol_ids.iter().cloned()).collect();
    let caption = card_face_caption(&groups, &names);
    let handle = card
        .links
        .iter()
        .find(|l| l.kind == CardLinkKind::X)
        .or_else(|| card.links.first())
        .map(card_link_view);
    CardFace {
        oshi_idol_ids: shown,
        oshi_groups: groups,
        oshi_caption: caption,
        more_oshi: more,
        handle,
        since_imprint: card.since_year.map(|y| format!("SINCE {y}")),
        issued_label: card_issued_label(&card.issued_on),
    }
}

// ---------------------------------------------------------------------------
// リンクの保存の形 (端末の表に入れる)
// ---------------------------------------------------------------------------

/// 保存に使うリンクの種類の英字キー。ラベルを変えても保存したリンクが迷子にならない。
pub fn card_link_kind_key(kind: CardLinkKind) -> String {
    match kind {
        CardLinkKind::X => "x",
        CardLinkKind::Bluesky => "bluesky",
        CardLinkKind::Misskey => "misskey",
        CardLinkKind::YouTube => "youtube",
        CardLinkKind::Instagram => "instagram",
        CardLinkKind::TikTok => "tiktok",
        CardLinkKind::Web => "web",
    }
    .into()
}

pub fn card_link_kind_from_key(key: &str) -> Option<CardLinkKind> {
    Some(match key {
        "x" => CardLinkKind::X,
        "bluesky" => CardLinkKind::Bluesky,
        "misskey" => CardLinkKind::Misskey,
        "youtube" => CardLinkKind::YouTube,
        "instagram" => CardLinkKind::Instagram,
        "tiktok" => CardLinkKind::TikTok,
        "web" => CardLinkKind::Web,
        _ => return None,
    })
}

/// リンクの並びを保存用の JSON (`[{"kind":"x","value":"…"}]`) にする。
pub fn card_links_to_json(links: &[CardLink]) -> String {
    let items: Vec<serde_json::Value> = links
        .iter()
        .map(|l| serde_json::json!({ "kind": card_link_kind_key(l.kind), "value": l.value }))
        .collect();
    serde_json::Value::Array(items).to_string()
}

/// 保存用の JSON からリンクの並びを戻す。知らない種類・壊れた要素は落とす (残りは読む)。
pub fn card_links_from_json(json: &str) -> Vec<CardLink> {
    let Ok(serde_json::Value::Array(items)) = serde_json::from_str::<serde_json::Value>(json)
    else {
        return Vec::new();
    };
    items
        .iter()
        .filter_map(|v| {
            let kind = card_link_kind_from_key(v.get("kind")?.as_str()?)?;
            let value = v.get("value")?.as_str()?.to_string();
            Some(CardLink { kind, value })
        })
        .collect()
}

// ---------------------------------------------------------------------------
// 名刺ファイル (`.imascard`)
//
// 名刺と担当の画像を 1 つのファイルにまとめる。OS の共有 (AirDrop / Quick Share) で
// iPhone と Android の間でも画像を元の画質のまま渡せるようにするため。
// 近距離の直接の受け渡し (iPhone 同士) も同じ中身を流す。
//
//   8 byte  "IMASCARD"
//   u8      版 (1)
//   str     名刺の中身 (`#` の後ろ)
//   varint  担当の画像の数 (担当の数まで)
//   (str 担当の id, varint バイト数, JPEG) × n
//   [varint 追加の区画の数, (u8 種類, varint バイト数, 中身) × m]   (あるときだけ)
//
// 追加の区画は後から足したもの (種類 1 = 名刺の写真、2 = 自作の名刺の画像の表、3 = 同じく裏。
// どれも JPEG)。古い版のアプリは担当の画像の後ろを読まないので、写真の入ったファイルも
// そのまま開ける (写真だけが出ない)。知らない種類の区画は飛ばす (表・裏を足す前の版のアプリは
// 写真だけを読む)。区画が無いファイル (足す前のもの) は今まで通り読む。
// ---------------------------------------------------------------------------

const CARD_FILE_MAGIC: &[u8; 8] = b"IMASCARD";
const CARD_FILE_VERSION: u8 = 1;
/// 画像 1 枚の上限。長辺 1600px 程度の JPEG なら 1MB 前後なので十分に余裕がある。
const MAX_CARD_FILE_IMAGE_BYTES: usize = 12 * 1024 * 1024;
/// 追加の区画の数の上限 (今は写真・表・裏・写真の出どころの 4 つ。知らない種類を飛ばす余地を残す)。
const MAX_CARD_FILE_SECTIONS: usize = 8;
const SECTION_PHOTO: u8 = 1;
const SECTION_FACE_FRONT: u8 = 2;
const SECTION_FACE_BACK: u8 = 3;
/// 名刺の写真の出どころ (中身は 1 バイトの `photo_source_code`)。写真から選んだ写真では書かない。
/// 足す前のアプリは知らない区画として飛ばし、写真は写真のまま (正方形で) 出す。
const SECTION_PHOTO_SOURCE: u8 = 4;

/// 名刺の写真の出どころ。端末に写真と一緒に残し、名刺ファイル・近くの端末で相手にも渡す
/// (切り方は `card_photo_shape`)。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum CardPhotoSource {
    /// 写真から選んだ写真 (自分で切り抜いた正方形)。
    #[default]
    Picked,
    /// X のアイコン (名刺のリンクの X の ID から取ったもの)。
    XIcon,
}

/// 名刺の写真の切り方。枠はどちらも正方形で、丸はその枠に内接する円で切る。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum CardPhotoShape {
    /// 正方形 (角を小さく丸める)。
    Square,
    /// 丸 (X のアイコンは X と同じ見え方で出す)。
    Round,
}

/// 名刺の写真の切り方 (X のアイコンは丸、写真から選んだ写真は正方形)。名刺の表・紙に刷る画像・
/// 名刺入れの行・編集画面の枠、プロフィール帳の証明写真の欄 (枠は 3:4 のまま、丸は枠の中に置く) で同じ。
pub fn card_photo_shape(source: CardPhotoSource) -> CardPhotoShape {
    match source {
        CardPhotoSource::Picked => CardPhotoShape::Square,
        CardPhotoSource::XIcon => CardPhotoShape::Round,
    }
}

/// 写真の出どころを端末に残すときの英字キー。
pub fn card_photo_source_key(source: CardPhotoSource) -> String {
    match source {
        CardPhotoSource::Picked => "picked",
        CardPhotoSource::XIcon => "x_icon",
    }
    .to_string()
}

/// 端末に残したキーから写真の出どころを読む。知らないキー (無いときも) は写真から選んだ写真。
pub fn card_photo_source_from_key(key: &str) -> CardPhotoSource {
    match key.trim() {
        "x_icon" => CardPhotoSource::XIcon,
        _ => CardPhotoSource::Picked,
    }
}

fn photo_source_code(source: CardPhotoSource) -> u8 {
    match source {
        CardPhotoSource::Picked => 0,
        CardPhotoSource::XIcon => 1,
    }
}

fn photo_source_from_code(code: u8) -> Option<CardPhotoSource> {
    match code {
        0 => Some(CardPhotoSource::Picked),
        1 => Some(CardPhotoSource::XIcon),
        _ => None,
    }
}

/// 名刺ファイルの種類の名乗り。OS に登録する拡張子・MIME・UTI はここ 1 か所。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardFileTypeInfo {
    pub extension: String,
    pub mime_type: String,
    pub uniform_type_identifier: String,
}

/// 名刺ファイルの画像の種類。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum CardFileImageKind {
    /// 担当の画像 (`idol_id` の人の画像)。
    #[default]
    Oshi,
    /// 名刺の写真 (自分で選んだ写真。1 枚だけ。`idol_id` は空)。
    Photo,
    /// 自作の名刺の画像の表 (デザインが自作の画像の名刺だけ。1 枚だけ。`idol_id` は空)。
    FaceFront,
    /// 自作の名刺の画像の裏 (任意。表がある名刺だけ。`idol_id` は空)。
    FaceBack,
}

impl CardFileImageKind {
    fn section(self) -> Option<u8> {
        match self {
            CardFileImageKind::Oshi => None,
            CardFileImageKind::Photo => Some(SECTION_PHOTO),
            CardFileImageKind::FaceFront => Some(SECTION_FACE_FRONT),
            CardFileImageKind::FaceBack => Some(SECTION_FACE_BACK),
        }
    }

    fn from_section(section: u8) -> Option<CardFileImageKind> {
        [
            CardFileImageKind::Photo,
            CardFileImageKind::FaceFront,
            CardFileImageKind::FaceBack,
        ]
        .into_iter()
        .find(|k| k.section() == Some(section))
    }
}

/// 名刺ファイルに入れる画像 1 枚 (担当の画像か名刺の写真)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardFileImage {
    pub idol_id: String,
    pub jpeg: Vec<u8>,
    pub kind: CardFileImageKind,
    /// 名刺の写真 (`Photo`) の出どころ。None は写真から選んだ写真 (足す前のファイルも)。写真のほかは None。
    #[uniffi(default = None)]
    pub photo_source: Option<CardPhotoSource>,
}

/// 名刺ファイルを開いた中身。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct CardFileContents {
    pub payload: String,
    pub card: ProducerCard,
    /// 名刺の担当に載っている人の画像 (名刺の担当の順) と、名刺の写真・自作の名刺の画像の表・裏
    /// (あればこの順に 1 枚ずつ)。
    pub images: Vec<CardFileImage>,
}

pub fn card_file_type_info() -> CardFileTypeInfo {
    CardFileTypeInfo {
        extension: "imascard".into(),
        mime_type: "application/vnd.imaslivedb.card".into(),
        uniform_type_identifier: "com.fugaif.imaslivedb.card".into(),
    }
}

/// 名刺ファイルの名前 (`ふがPのP名刺.imascard`)。ファイル名に使えない文字は落とす。
pub fn card_file_name(card: &ProducerCard) -> String {
    let name: String = card
        .name
        .trim()
        .chars()
        .filter(|c| {
            !matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|') && !c.is_control()
        })
        .collect();
    let ext = card_file_type_info().extension;
    if name.is_empty() {
        format!("P名刺.{ext}")
    } else {
        format!("{name}のP名刺.{ext}")
    }
}

/// 名刺ファイルを組み立てる。名刺の中身が読めなければ None。
/// 名刺の担当に載っていない人の画像・空の画像・大きすぎる画像は入れない。
pub fn encode_card_file(payload: &str, images: &[CardFileImage]) -> Option<Vec<u8>> {
    let card = decode_producer_card(payload)?;
    let payload = card_payload(payload)?;
    let images = card_file_images(&card, images.to_vec());
    let mut w = Vec::with_capacity(
        32 + payload.len() + images.iter().map(|i| i.jpeg.len() + 48).sum::<usize>(),
    );
    w.extend_from_slice(CARD_FILE_MAGIC);
    w.push(CARD_FILE_VERSION);
    put_str(&mut w, payload);
    let (oshi, sections): (Vec<&CardFileImage>, Vec<&CardFileImage>) = images
        .iter()
        .partition(|i| i.kind == CardFileImageKind::Oshi);
    put_varint(&mut w, oshi.len() as u64);
    for image in &oshi {
        put_str(&mut w, &image.idol_id);
        put_varint(&mut w, image.jpeg.len() as u64);
        w.extend_from_slice(&image.jpeg);
    }
    // 写真の出どころ (X のアイコンのときだけ。写真から選んだ写真は足す前のファイルと同じ形のまま)。
    let photo_source = sections
        .iter()
        .find(|i| i.kind == CardFileImageKind::Photo)
        .and_then(|i| i.photo_source)
        .filter(|s| *s != CardPhotoSource::Picked);
    // 写真も自作の画像も無ければ区画ごと書かない (足す前のファイルと同じ形のまま)。
    if !sections.is_empty() {
        put_varint(&mut w, (sections.len() + usize::from(photo_source.is_some())) as u64);
        for image in &sections {
            w.push(image.kind.section()?);
            put_varint(&mut w, image.jpeg.len() as u64);
            w.extend_from_slice(&image.jpeg);
        }
        if let Some(source) = photo_source {
            w.push(SECTION_PHOTO_SOURCE);
            put_varint(&mut w, 1);
            w.push(photo_source_code(source));
        }
    }
    Some(w)
}

/// 名刺ファイルを開く。名刺ファイルでなければ None。
pub fn decode_card_file(bytes: &[u8]) -> Option<CardFileContents> {
    let body = bytes.strip_prefix(CARD_FILE_MAGIC.as_slice())?;
    let mut r = Reader {
        bytes: body,
        pos: 0,
    };
    if r.u8()? != CARD_FILE_VERSION {
        return None;
    }
    let raw = r.str()?;
    let card = decode_producer_card(&raw)?;
    // URL の形で入っていても `#` の後ろに揃える (保存・重複の判定はこの形)。
    let payload = card_payload(&raw)?.to_string();
    let count = r.count(MAX_OSHI as usize)?;
    let mut images = Vec::with_capacity(count);
    for _ in 0..count {
        let idol_id = r.str()?;
        let len = r.count(MAX_CARD_FILE_IMAGE_BYTES)?;
        let end = r.pos.checked_add(len)?;
        let jpeg = r.bytes.get(r.pos..end)?.to_vec();
        r.pos = end;
        images.push(CardFileImage {
            idol_id,
            jpeg,
            kind: CardFileImageKind::Oshi,
            photo_source: None,
        });
    }
    // 追加の区画 (足す前のファイルには無い)。あるなら最後まで読み切れること。
    let mut photo_source = None;
    if r.pos < r.bytes.len() {
        let sections = r.count(MAX_CARD_FILE_SECTIONS)?;
        for _ in 0..sections {
            let kind = r.u8()?;
            let len = r.count(MAX_CARD_FILE_IMAGE_BYTES)?;
            let end = r.pos.checked_add(len)?;
            let body = r.bytes.get(r.pos..end)?;
            r.pos = end;
            if kind == SECTION_PHOTO_SOURCE {
                // 知らない出どころは写真から選んだ写真として読む (写真そのものは出す)。
                photo_source = photo_source.or(match body {
                    [code] => photo_source_from_code(*code),
                    _ => None,
                });
                continue;
            }
            let known = CardFileImageKind::from_section(kind);
            if let Some(kind) = known.filter(|k| !images.iter().any(|i| i.kind == *k)) {
                images.push(CardFileImage {
                    idol_id: String::new(),
                    jpeg: body.to_vec(),
                    kind,
                    photo_source: None,
                });
            }
        }
        if r.pos != r.bytes.len() {
            return None;
        }
    }
    if let Some(photo) = images.iter_mut().find(|i| i.kind == CardFileImageKind::Photo) {
        photo.photo_source = photo_source;
    }
    let images = card_file_images(&card, images);
    Some(CardFileContents {
        payload,
        card,
        images,
    })
}

/// 名刺の担当に載っている人の画像だけを、名刺の担当の順に 1 人 1 枚で残し、
/// 名刺の写真・自作の名刺の画像の表・裏があれば、この順に 1 枚ずつ足す。
/// 自作の画像はデザインが自作の画像の名刺のときだけ、裏は表があるときだけ残す。
fn card_file_images(card: &ProducerCard, images: Vec<CardFileImage>) -> Vec<CardFileImage> {
    // JPEG だけを通す (画像を開く側に任意の形式を渡さない)。
    let usable = |i: &&CardFileImage| {
        i.jpeg.starts_with(&[0xFF, 0xD8, 0xFF]) && i.jpeg.len() <= MAX_CARD_FILE_IMAGE_BYTES
    };
    let mut out: Vec<CardFileImage> = Vec::new();
    for id in &card.oshi_idol_ids {
        let found = images
            .iter()
            .find(|i| i.kind == CardFileImageKind::Oshi && &i.idol_id == id);
        if let Some(image) = found.filter(usable) {
            out.push(CardFileImage {
                photo_source: None,
                ..image.clone()
            });
        }
    }
    let custom = card.design == Some(CardDesign::Custom);
    let mut has_front = false;
    for kind in [
        CardFileImageKind::Photo,
        CardFileImageKind::FaceFront,
        CardFileImageKind::FaceBack,
    ] {
        let allowed = match kind {
            CardFileImageKind::FaceFront => custom,
            CardFileImageKind::FaceBack => custom && has_front,
            _ => true,
        };
        let found = images.iter().find(|i| i.kind == kind).filter(usable);
        if let Some(image) = found.filter(|_| allowed) {
            has_front |= kind == CardFileImageKind::FaceFront;
            // 出どころは写真にだけ持たせる (写真から選んだ写真は None にそろえる)。
            let photo_source = image
                .photo_source
                .filter(|s| kind == CardFileImageKind::Photo && *s != CardPhotoSource::Picked);
            out.push(CardFileImage {
                idol_id: String::new(),
                photo_source,
                ..image.clone()
            });
        }
    }
    out
}

/// 近くの端末に繋ぐときの合言葉。QR を読んだ人にしか作れない値 (名乗りに出す札とは別の値)。
/// 見せている側は、自分の名刺から同じ値を作って一致した相手の招待だけを受ける
/// (QR を読まずに近くで名刺を集めたり、勝手に名刺を入れたりできないように)。
pub fn card_invite_proof(payload: &str) -> String {
    let payload = card_payload(payload).unwrap_or(payload);
    crate::domain::sha256::sha256_hex(&format!("imascard-invite|{payload}"))
}

/// 近くの端末どうしで相手を見分ける札 (名刺の中身の SHA-256 の先頭 16 桁)。
/// 見せている側が近くに名乗り、読んだ側は読み取った名刺から同じ札を作って探す。
pub fn card_peer_tag(payload: &str) -> String {
    let payload = card_payload(payload).unwrap_or(payload);
    crate::domain::sha256::sha256_hex(payload)
        .chars()
        .take(16)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, name: &str, brand: &str, label: &str) -> CardOshiEntry {
        CardOshiEntry { idol_id: id.into(), name: name.into(), brand_id: brand.into(), brand_label: label.into() }
    }

    /// 担当 5 人・4 ブランド (765AS 美希 / 876 宇宙 / 学マス 手毬・美鈴 / ミリオン 桃子)。
    fn five_in_four_brands() -> Vec<CardOshiEntry> {
        vec![
            entry("miki", "星井美希", "765as", "765AS"),
            entry("temari", "月村手毬", "gakuen", "学マス"),
            entry("sora", "上水流宇宙", "876", "876"),
            entry("misuzu", "秦谷美鈴", "gakuen", "学マス"),
            entry("momoko", "周防桃子", "ml", "ミリオン"),
        ]
    }

    #[test]
    fn card_face_shows_all_card_oshi_grouped_by_brand() {
        let mut card = encode_producer_card(&input()).card;
        let all = five_in_four_brands();
        card.oshi_idol_ids = all.iter().map(|o| o.idol_id.clone()).collect();
        let face = producer_card_face(&card, &all);
        // 名刺に載る 5 人は全員表に出る。ブランドは並びで先に出た順、中は名刺の並び順。
        assert_eq!(face.more_oshi, 0);
        let groups: Vec<(&str, Vec<&str>)> = face
            .oshi_groups
            .iter()
            .map(|g| (g.brand_label.as_str(), g.idol_ids.iter().map(String::as_str).collect()))
            .collect();
        assert_eq!(
            groups,
            vec![
                ("765AS", vec!["miki"]),
                ("学マス", vec!["temari", "misuzu"]),
                ("876", vec!["sora"]),
                ("ミリオン", vec!["momoko"]),
            ]
        );
        assert_eq!(face.oshi_idol_ids, vec!["miki", "temari", "misuzu", "sora", "momoko"]);
        // ブランドが 2 つ以上なら名前の行は刷らず、まとまりごとにブランドの略称を刷る。
        assert_eq!(face.oshi_caption, None);
    }

    #[test]
    fn card_face_caption_names_one_brand_and_counts_when_long() {
        let mut card = encode_producer_card(&input()).card;
        let one = vec![entry("miki", "星井美希", "765as", "765AS")];
        card.oshi_idol_ids = vec!["miki".into()];
        let face = producer_card_face(&card, &one);
        assert_eq!(face.oshi_caption.as_deref(), Some("星井美希 担当"));
        assert_eq!(face.oshi_groups.len(), 1);
        let many: Vec<CardOshiEntry> = ["天海春香", "如月千早", "星井美希", "萩原雪歩", "高槻やよい"]
            .iter()
            .enumerate()
            .map(|(i, n)| entry(&format!("i{i}"), n, "765as", "765AS"))
            .collect();
        card.oshi_idol_ids = many.iter().map(|o| o.idol_id.clone()).collect();
        let face = producer_card_face(&card, &many);
        assert_eq!(face.oshi_caption.as_deref(), Some("765AS 5人 担当"));
        card.oshi_idol_ids.truncate(2);
        let face = producer_card_face(&card, &many);
        assert_eq!(face.oshi_caption.as_deref(), Some("天海春香・如月千早 担当"));
        // 担当がいなければ何も刷らない。
        let face = producer_card_face(&card, &[]);
        assert!(face.oshi_idol_ids.is_empty() && face.oshi_groups.is_empty());
        assert_eq!(face.oshi_caption, None);
    }

    #[test]
    fn card_face_skips_undrawable_oshi() {
        let mut card = encode_producer_card(&input()).card;
        let all = five_in_four_brands();
        card.oshi_idol_ids = all.iter().map(|o| o.idol_id.clone()).collect();
        // 手元に無い担当は出さず、畳む数にも数えない。
        let drawable: Vec<CardOshiEntry> = all.iter().filter(|o| o.idol_id != "sora").cloned().collect();
        let face = producer_card_face(&card, &drawable);
        assert_eq!(face.oshi_idol_ids, vec!["miki", "temari", "misuzu", "momoko"]);
        assert_eq!(face.more_oshi, 0);
    }

    #[test]
    fn pick_oshi_keeps_one_per_brand_before_filling_by_order() {
        // アプリの担当が 8 人 (765AS が 4 人続いてから他のブランド)。先頭から切ると 765AS だけになる。
        let oshi = vec![
            entry("haruka", "天海春香", "765as", "765AS"),
            entry("chihaya", "如月千早", "765as", "765AS"),
            entry("miki", "星井美希", "765as", "765AS"),
            entry("yukiho", "萩原雪歩", "765as", "765AS"),
            entry("sora", "上水流宇宙", "876", "876"),
            entry("temari", "月村手毬", "gakuen", "学マス"),
            entry("misuzu", "秦谷美鈴", "gakuen", "学マス"),
            entry("momoko", "周防桃子", "ml", "ミリオン"),
        ];
        // ブランドごとに 1 人 (春香・宇宙・手毬・桃子) を先に、残りの 1 枠に並び順で千早。並びはアプリのまま。
        assert_eq!(producer_card_pick_oshi(&oshi), vec!["haruka", "chihaya", "sora", "temari", "momoko"]);
        // 5 人以下はそのまま。同じ id は 1 度だけ。
        let few = vec![oshi[0].clone(), oshi[4].clone(), oshi[0].clone()];
        assert_eq!(producer_card_pick_oshi(&few), vec!["haruka", "sora"]);
        // ブランドが枠より多ければ、並びで先に出たブランドから。ブランドが分からない担当は 1 人ずつ数える。
        let wide: Vec<CardOshiEntry> =
            (0..7).map(|i| entry(&format!("i{i}"), "名前", &format!("b{i}"), "")).collect();
        assert_eq!(producer_card_pick_oshi(&wide), vec!["i0", "i1", "i2", "i3", "i4"]);
        let unknown = vec![entry("a", "名前", "", ""), entry("b", "名前", "", "")];
        assert_eq!(producer_card_pick_oshi(&unknown), vec!["a", "b"]);
    }

    #[test]
    fn card_face_folds_with_brand_representatives_when_over_slots() {
        // 名刺の上限を超える担当が来たとき (古い版の名刺など) も、ブランドの代表を先に並べて残りを畳む。
        let mut card = encode_producer_card(&input()).card;
        let mut all = five_in_four_brands();
        all.insert(1, entry("haruka", "天海春香", "765as", "765AS"));
        card.oshi_idol_ids = all.iter().map(|o| o.idol_id.clone()).collect();
        let face = producer_card_face(&card, &all);
        assert_eq!(face.more_oshi, 2);
        assert_eq!(face.oshi_idol_ids, vec!["miki", "temari", "sora", "momoko"]);
    }

    #[test]
    fn card_face_prefers_x_handle_and_prints_since_and_date() {
        let mut card = encode_producer_card(&input()).card;
        card.links.reverse(); // Bluesky が先頭でも X を選ぶ。
        let face = producer_card_face(&card, &[]);
        assert_eq!(face.handle.map(|h| h.display), Some("@fuga_p".to_string()));
        assert_eq!(face.since_imprint.as_deref(), Some("SINCE 2014"));
        assert_eq!(face.issued_label, "2026.10.06 時点");
        card.links.retain(|l| l.kind != CardLinkKind::X);
        assert_eq!(
            producer_card_face(&card, &[]).handle.map(|h| h.display),
            Some("fuga.bsky.social".to_string())
        );
        card.links.clear();
        card.since_year = None;
        let face = producer_card_face(&card, &[]);
        assert!(face.handle.is_none());
        assert!(face.since_imprint.is_none());
    }

    fn input() -> ProducerCardInput {
        ProducerCardInput {
            name: "ふがP".into(),
            message: "現地派・Pライブ皆勤目指してます".into(),
            since_year: Some(2014),
            oshi_idol_ids: vec!["765_天海春香".into(), "765_如月千早".into()],
            links: vec![
                CardLink {
                    kind: CardLinkKind::X,
                    value: "@fuga_p".into(),
                },
                CardLink {
                    kind: CardLinkKind::Bluesky,
                    value: "fuga.bsky.social".into(),
                },
            ],
            show_count: Some(87),
            song_count: Some(412),
            next_show_id: Some("sh_e656e30e-e4a6-4f8e-84fe-ab83bc7f7eb8".into()),
            attended: vec![
                CardShowRef {
                    show_id: "sh_a".into(),
                    date: "2015-07-18".into(),
                },
                CardShowRef {
                    show_id: "sh_b".into(),
                    date: "2026-10-05".into(),
                },
            ],
            issued_on: "2026-10-06".into(),
            design: None,
            qr_url: None,
        }
    }

    #[test]
    fn round_trips_through_url() {
        let enc = encode_producer_card(&input());
        assert!(enc.url.starts_with("https://idollivedb.fugaapp.site/p/#"));
        let back = decode_producer_card(&enc.url).expect("decodes");
        assert_eq!(back, enc.card);
        assert_eq!(
            back.links[0],
            CardLink {
                kind: CardLinkKind::X,
                value: "fuga_p".into()
            }
        );
        assert_eq!(back.issued_on, "2026-10-06");
        assert_eq!(enc.dropped_shows, 0);
    }

    #[test]
    fn decodes_bare_payload_and_rejects_other_urls() {
        let enc = encode_producer_card(&input());
        let payload = enc.url.split_once('#').unwrap().1;
        assert_eq!(decode_producer_card(payload), Some(enc.card.clone()));
        assert_eq!(
            decode_producer_card(&format!("https://example.com/p/#{payload}")),
            None
        );
        assert_eq!(
            decode_producer_card("https://idollivedb.fugaapp.site/p/#!!"),
            None
        );
    }

    #[test]
    fn rejects_unknown_version_and_trailing_bytes() {
        let mut bytes = write_card(&encode_producer_card(&input()).card);
        bytes[0] = 9;
        assert_eq!(read_card(&bytes), None);
        let mut bytes = write_card(&encode_producer_card(&input()).card);
        bytes.push(0);
        assert_eq!(read_card(&bytes), None);
    }

    #[test]
    fn drops_oldest_shows_to_fit_qr() {
        let mut i = input();
        i.attended = (0..900)
            .map(|n| CardShowRef {
                show_id: format!("sh_{n}"),
                date: day_to_date(3000 + n * 5),
            })
            .collect();
        let enc = encode_producer_card(&i);
        assert!(enc.url.len() <= MAX_URL_LEN, "{}", enc.url.len());
        assert!(enc.dropped_shows > 0);
        assert!(enc.card.attended_truncated);
        // 残るのは新しい方
        assert_eq!(enc.card.attended.last().unwrap().day, 3000 + 899 * 5);
        assert_eq!(decode_producer_card(&enc.url), Some(enc.card));
    }

    #[test]
    fn common_points_match_by_date_and_fingerprint() {
        let card = encode_producer_card(&input()).card;
        let mine = vec![
            CardShowRef {
                show_id: "sh_b".into(),
                date: "2026-10-05".into(),
            },
            CardShowRef {
                show_id: "sh_c".into(),
                date: "2026-10-05".into(),
            },
            CardShowRef {
                show_id: "sh_a".into(),
                date: "2015-07-18".into(),
            },
        ];
        let common = producer_card_common(&card, &["765_如月千早".into()], &mine);
        assert_eq!(common.shared_oshi_ids, vec!["765_如月千早".to_string()]);
        assert_eq!(
            common.shared_show_ids,
            vec!["sh_a".to_string(), "sh_b".to_string()]
        );
    }

    #[test]
    fn validates_input() {
        let mut i = input();
        assert_eq!(validate_producer_card(&i), None);
        i.name = "  ".into();
        assert_eq!(
            validate_producer_card(&i),
            Some(ProducerCardInputError::NameEmpty)
        );
        let mut i = input();
        i.links.push(CardLink {
            kind: CardLinkKind::Bluesky,
            value: "no space allowed".into(),
        });
        assert_eq!(
            validate_producer_card(&i),
            Some(ProducerCardInputError::LinkInvalid)
        );
        let mut i = input();
        i.name = "あ".repeat(25);
        assert_eq!(
            validate_producer_card(&i),
            Some(ProducerCardInputError::NameTooLong)
        );
    }

    #[test]
    fn normalizes_links_from_handles_and_urls() {
        let n = |kind, v: &str| {
            normalize_link(&CardLink {
                kind,
                value: v.into(),
            })
            .map(|l| l.value)
        };
        assert_eq!(n(CardLinkKind::X, "@fuga_p"), Some("fuga_p".into()));
        assert_eq!(
            n(CardLinkKind::X, "https://twitter.com/fuga_p?s=21"),
            Some("fuga_p".into())
        );
        assert_eq!(
            n(CardLinkKind::X, "https://bsky.app/profile/a.bsky.social"),
            None
        );
        assert_eq!(
            n(CardLinkKind::Misskey, "@fuga@Misskey.io"),
            Some("fuga@misskey.io".into())
        );
        assert_eq!(
            n(CardLinkKind::Web, "lit.link/fuga"),
            Some("https://lit.link/fuga".into())
        );
        let v = card_link_view(&CardLink {
            kind: CardLinkKind::Misskey,
            value: "fuga@misskey.io".into(),
        });
        assert_eq!(v.url, "https://misskey.io/@fuga");
        assert_eq!(v.display, "@fuga@misskey.io");
    }

    #[test]
    fn classifies_scanned_codes() {
        let enc = encode_producer_card(&input());
        assert!(matches!(
            classify_scanned_code(&enc.url),
            ScannedCode::Card { .. }
        ));
        assert_eq!(
            classify_scanned_code("https://x.com/karuta_p"),
            ScannedCode::Link {
                url: "https://x.com/karuta_p".into(),
                link: Some(CardLink {
                    kind: CardLinkKind::X,
                    value: "karuta_p".into()
                }),
            }
        );
        assert!(matches!(
            classify_scanned_code("https://lit.link/en/karuta"),
            ScannedCode::Link {
                link: Some(CardLink {
                    kind: CardLinkKind::Web,
                    ..
                }),
                ..
            }
        ));
        assert_eq!(
            classify_scanned_code("こんにちは"),
            ScannedCode::Text {
                text: "こんにちは".into()
            }
        );
    }

    #[test]
    fn exchange_candidates_prefer_today_then_yesterday() {
        let mine = vec![
            CardShowRef {
                show_id: "sh_y".into(),
                date: "2026-10-04".into(),
            },
            CardShowRef {
                show_id: "sh_t2".into(),
                date: "2026-10-05".into(),
            },
            CardShowRef {
                show_id: "sh_t1".into(),
                date: "2026-10-05".into(),
            },
        ];
        assert_eq!(
            card_exchange_show_candidates("2026-10-05", &mine),
            vec!["sh_t1", "sh_t2"]
        );
        assert_eq!(
            card_exchange_show_candidates("2026-10-07", &mine),
            Vec::<String>::new()
        );
        assert_eq!(
            card_exchange_show_candidates("2026-10-05", &mine[..1]),
            vec!["sh_y"]
        );
    }

    #[test]
    fn case_groups_by_show_then_received_day() {
        let e = |id: &str, show: Option<(&str, &str)>, at: &str| CardCaseEntry {
            id: id.into(),
            show_id: show.map(|s| s.0.into()),
            show_date: show.map(|s| s.1.into()),
            received_at: at.into(),
        };
        let sections = card_case_sections(&[
            e(
                "1",
                Some(("sh_b", "2026-10-05")),
                "2026-10-05T18:00:00+09:00",
            ),
            e(
                "2",
                Some(("sh_b", "2026-10-05")),
                "2026-10-05T21:00:00+09:00",
            ),
            e("3", None, "2026-10-06T12:00:00+09:00"),
            // UTC で 10/5 17:56 = JST 10/6 02:56 → 10/6 の束
            e("5", None, "2026-10-05T17:56:00Z"),
            e(
                "4",
                Some(("sh_a", "2026-09-14")),
                "2026-09-14T20:00:00+09:00",
            ),
        ]);
        let shape: Vec<(Option<String>, String, Vec<String>)> = sections
            .into_iter()
            .map(|s| (s.show_id, s.date, s.entry_ids))
            .collect();
        assert_eq!(
            shape,
            vec![
                (None, "2026-10-06".into(), vec!["3".into(), "5".into()]),
                (
                    Some("sh_b".into()),
                    "2026-10-05".into(),
                    vec!["2".into(), "1".into()]
                ),
                (Some("sh_a".into()), "2026-09-14".into(), vec!["4".into()]),
            ]
        );
    }

    #[test]
    fn base64url_round_trips_all_lengths() {
        for len in 0..10 {
            let bytes: Vec<u8> = (0..len).map(|n| (n * 37 + 11) as u8).collect();
            assert_eq!(base64url_decode(&base64url_encode(&bytes)), Some(bytes));
        }
    }

    #[test]
    fn fingerprint_is_stable() {
        // Web (wasm) と端末で同じ値になることの固定。変えると交換済みの名刺の共通点が壊れる。
        assert_eq!(fingerprint("sh_e656e30e-e4a6-4f8e-84fe-ab83bc7f7eb8"), 3751);
        assert_ne!(fingerprint("sh_a"), fingerprint("sh_b"));
    }

    #[test]
    fn record_summary_splits_past_and_next() {
        let refs = vec![
            CardShowRef {
                show_id: "b".into(),
                date: "2026-10-06".into(),
            },
            CardShowRef {
                show_id: "a".into(),
                date: "2025-01-01".into(),
            },
            CardShowRef {
                show_id: "z".into(),
                date: "2026-12-01".into(),
            },
            CardShowRef {
                show_id: "y".into(),
                date: "2026-10-18".into(),
            },
            CardShowRef {
                show_id: "a".into(),
                date: "2025-01-01".into(),
            },
            CardShowRef {
                show_id: "bad".into(),
                date: "".into(),
            },
        ];
        let s = producer_card_record_summary("2026-10-06", &refs);
        assert_eq!(s.show_count, 2);
        assert_eq!(
            s.attended_past
                .iter()
                .map(|r| r.show_id.as_str())
                .collect::<Vec<_>>(),
            vec!["a", "b"]
        );
        assert_eq!(s.next_show_id.as_deref(), Some("y"));
        assert_eq!(producer_card_record_summary("", &refs).show_count, 0);
    }

    #[test]
    fn issued_label_is_dotted() {
        assert_eq!(card_issued_label("2026-10-06"), "2026.10.06 時点");
        assert_eq!(card_issued_label(""), "");
    }

    #[test]
    fn links_json_round_trips_and_skips_unknown() {
        let links = vec![
            CardLink {
                kind: CardLinkKind::X,
                value: "fuga_p".into(),
            },
            CardLink {
                kind: CardLinkKind::Misskey,
                value: "a@misskey.io".into(),
            },
        ];
        let json = card_links_to_json(&links);
        assert_eq!(card_links_from_json(&json), links);
        let mixed = r#"[{"kind":"x","value":"a"},{"kind":"mastodon","value":"b"},3]"#;
        assert_eq!(card_links_from_json(mixed).len(), 1);
        assert!(card_links_from_json("not json").is_empty());
        for info in card_link_kinds() {
            assert_eq!(
                card_link_kind_from_key(&card_link_kind_key(info.kind)),
                Some(info.kind)
            );
        }
    }

    #[test]
    fn card_file_round_trips_only_oshi_images() {
        let enc = encode_producer_card(&input());
        let payload = enc.url.split_once('#').unwrap().1.to_string();
        let images = vec![
            CardFileImage {
                idol_id: "765_如月千早".into(),
                jpeg: vec![0xFF, 0xD8, 0xFF, 3],
                kind: CardFileImageKind::Oshi,
                photo_source: None,
            },
            CardFileImage {
                idol_id: "961_黒井".into(),
                jpeg: vec![0xFF, 0xD8, 0xFF, 9],
                kind: CardFileImageKind::Oshi,
                photo_source: None,
            },
            CardFileImage {
                idol_id: "765_天海春香".into(),
                jpeg: vec![0xFF, 0xD8, 0xFF, 5],
                kind: CardFileImageKind::Oshi,
                photo_source: None,
            },
            CardFileImage {
                idol_id: "765_天海春香".into(),
                jpeg: vec![],
                kind: CardFileImageKind::Oshi,
                photo_source: None,
            },
        ];
        // URL を渡しても `#` の後ろだけを入れる。
        let bytes = encode_card_file(&enc.url, &images).unwrap();
        let file = decode_card_file(&bytes).unwrap();
        assert_eq!(file.payload, payload);
        assert_eq!(file.card, enc.card);
        assert_eq!(
            file.images
                .iter()
                .map(|i| i.idol_id.as_str())
                .collect::<Vec<_>>(),
            vec!["765_天海春香", "765_如月千早"]
        );
        assert_eq!(file.images[0].jpeg, vec![0xFF, 0xD8, 0xFF, 5]);
    }

    #[test]
    fn card_file_rejects_garbage() {
        assert!(decode_card_file(b"").is_none());
        assert!(decode_card_file(b"IMASCARD").is_none());
        assert!(decode_card_file(b"NOTACARD\x01").is_none());
        assert!(encode_card_file("not a card", &[]).is_none());
        let enc = encode_producer_card(&input());
        let bytes = encode_card_file(&enc.url, &[]).unwrap();
        // 途中で切れたファイルは読まない。
        let mut cut = bytes.clone();
        cut.truncate(bytes.len() - 1);
        assert!(decode_card_file(&cut).is_none());
        let mut v2 = bytes.clone();
        v2[8] = 2;
        assert!(decode_card_file(&v2).is_none());
    }

    #[test]
    fn card_file_name_drops_path_chars() {
        let mut card = encode_producer_card(&input()).card;
        assert_eq!(card_file_name(&card), "ふがPのP名刺.imascard");
        card.name = "a/b:c".into();
        assert_eq!(card_file_name(&card), "abcのP名刺.imascard");
        card.name = " ".into();
        assert_eq!(card_file_name(&card), "P名刺.imascard");
    }

    #[test]
    fn peer_tag_is_same_for_url_and_payload() {
        let enc = encode_producer_card(&input());
        let payload = enc.url.split_once('#').unwrap().1;
        assert_eq!(card_peer_tag(&enc.url), card_peer_tag(payload));
        assert_eq!(card_peer_tag(payload).len(), 16);
    }

    #[test]
    fn card_file_payload_is_normalized_from_url() {
        let enc = encode_producer_card(&input());
        let payload = enc.url.split_once('#').unwrap().1.to_string();
        // URL の形のまま入れたファイルでも `#` の後ろだけを返す。
        let mut w = Vec::new();
        w.extend_from_slice(CARD_FILE_MAGIC);
        w.push(CARD_FILE_VERSION);
        put_str(&mut w, &enc.url);
        put_varint(&mut w, 0);
        assert_eq!(decode_card_file(&w).unwrap().payload, payload);
    }

    #[test]
    fn non_jpeg_images_are_dropped() {
        let enc = encode_producer_card(&input());
        let png = CardFileImage {
            idol_id: "765_如月千早".into(),
            jpeg: vec![0x89, b'P', b'N', b'G'],
            kind: CardFileImageKind::Oshi,
            photo_source: None,
        };
        let file = decode_card_file(&encode_card_file(&enc.url, &[png]).unwrap()).unwrap();
        assert!(file.images.is_empty());
    }

    #[test]
    fn oversized_cards_are_not_read() {
        let mut card = encode_producer_card(&input()).card;
        card.name = "あ".repeat(MAX_NAME_CHARS as usize + 1);
        assert!(decode_producer_card(&producer_card_payload(&card)).is_none());
        let mut card = encode_producer_card(&input()).card;
        card.oshi_idol_ids = vec!["x".repeat(MAX_ID_BYTES + 1)];
        assert!(decode_producer_card(&producer_card_payload(&card)).is_none());
        assert!(decode_producer_card(&"A".repeat(MAX_URL_LEN + 1)).is_none());
    }

    #[test]
    fn invite_proof_differs_from_peer_tag() {
        let enc = encode_producer_card(&input());
        let payload = enc.url.split_once('#').unwrap().1;
        assert_eq!(card_invite_proof(&enc.url), card_invite_proof(payload));
        assert!(!card_invite_proof(payload).starts_with(&card_peer_tag(payload)));
    }

    #[test]
    fn default_card_bytes_are_unchanged_by_new_fields() {
        // 既定のデザインで自分の QR も無い名刺は、項目を足す前と同じ中身 (古いアプリでも読める)。
        let mut i = input();
        i.design = Some(CardDesign::Pass);
        let enc = encode_producer_card(&i);
        assert_eq!(enc.card.design, None);
        let bytes = write_card(&enc.card);
        assert_eq!(bytes[1] & (FLAG_DESIGN | FLAG_QR_URL), 0);
        // 足す前の版で作った名刺の中身 (固定) と 1 バイトも変わらず、今も同じに読める。
        let payload = enc.url.split_once('#').unwrap().1;
        assert_eq!(payload, V1_PAYLOAD);
        assert_eq!(read_card(&bytes), Some(enc.card));
    }

    #[test]
    fn design_and_qr_url_round_trip() {
        let mut i = input();
        i.design = Some(CardDesign::Formal);
        i.qr_url = Some("lit.link/fuga".into());
        let enc = encode_producer_card(&i);
        assert_eq!(enc.card.design, Some(CardDesign::Formal));
        assert_eq!(enc.card.qr_url.as_deref(), Some("https://lit.link/fuga"));
        let back = decode_producer_card(&enc.url).unwrap();
        assert_eq!(back, enc.card);
        let shown = producer_card_display_design(&back, false);
        assert_eq!(shown.key, "formal");
        assert_eq!(shown.font.key, "mincho");
        let view = card_qr_link_view(back.qr_url.as_deref().unwrap());
        assert_eq!(view.label, "QR");
        assert_eq!(view.url, "https://lit.link/fuga");
        assert_eq!(view.display, "lit.link/fuga");
    }

    #[test]
    fn old_reader_shape_rejects_new_fields_but_not_plain_cards() {
        // 古いアプリは旗を知らず、末尾に余りがあると読まない。デザインの入った名刺の末尾は
        // デザインの番号の 1 バイトだけであること (= 古いアプリは「読めない名刺」にして誤読しない)。
        let mut i = input();
        let plain = write_card(&encode_producer_card(&i).card);
        i.design = Some(CardDesign::Custom);
        let with_font = write_card(&encode_producer_card(&i).card);
        assert_eq!(with_font.len(), plain.len() + 1);
        assert_eq!(&with_font[2..plain.len()], &plain[2..]);
    }

    #[test]
    fn unknown_design_code_reads_as_default_and_unknown_flag_is_rejected() {
        let mut i = input();
        i.design = Some(CardDesign::Pop);
        let mut bytes = write_card(&encode_producer_card(&i).card);
        let last = bytes.len() - 1;
        bytes[last] = 200;
        let card = read_card(&bytes).expect("知らないデザインは既定で読む");
        assert_eq!(card.design, None);
        let mut bytes = write_card(&encode_producer_card(&input()).card);
        bytes[1] |= 1 << 7;
        assert_eq!(read_card(&bytes), None);
    }

    #[test]
    fn qr_url_is_validated_and_normalized() {
        assert_eq!(
            normalize_card_qr_url("lit.link/fuga").as_deref(),
            Some("https://lit.link/fuga")
        );
        assert_eq!(
            normalize_card_qr_url("https://x.com/fuga_p").as_deref(),
            Some("https://x.com/fuga_p")
        );
        assert_eq!(normalize_card_qr_url("javascript:alert(1)"), None);
        assert_eq!(normalize_card_qr_url("こんにちは"), None);
        // 交換用の QR (アプリの名刺) は自分の QR にしない。
        let enc = encode_producer_card(&input());
        assert_eq!(normalize_card_qr_url(&enc.url), None);
        let mut i = input();
        i.qr_url = Some("not a url".into());
        assert_eq!(
            validate_producer_card(&i),
            Some(ProducerCardInputError::QrUrlInvalid)
        );
        i.qr_url = Some("  ".into());
        assert_eq!(validate_producer_card(&i), None);
        assert_eq!(encode_producer_card(&i).card.qr_url, None);
    }

    #[test]
    fn too_long_cards_are_rejected_by_validation() {
        let mut i = input();
        i.links = (0..4)
            .map(|n| CardLink {
                kind: CardLinkKind::Web,
                value: format!("https://example.com/{n}/{}", "a".repeat(170)),
            })
            .collect();
        i.qr_url = Some(format!("https://example.com/{}", "b".repeat(170)));
        assert_eq!(
            validate_producer_card(&i),
            Some(ProducerCardInputError::TooLong)
        );
    }

    #[test]
    fn hand_built_cards_drop_unsafe_links() {
        let mut card = encode_producer_card(&input()).card;
        card.links.push(CardLink {
            kind: CardLinkKind::Web,
            value: "javascript:alert(1)".into(),
        });
        card.qr_url = Some("javascript:alert(1)".into());
        let back = decode_producer_card(&producer_card_payload(&card)).unwrap();
        assert_eq!(back.links.len(), 2);
        assert_eq!(back.qr_url, None);
    }

    #[test]
    fn design_keys_and_codes_round_trip() {
        let designs = card_designs();
        assert_eq!(designs.len(), 4);
        assert_eq!(designs[0].design, CardDesign::default());
        for info in &designs {
            assert_eq!(card_design_from_key(&info.key), Some(info.design));
            assert_eq!(
                design_from_code(design_code(info.design)).unwrap_or_default(),
                info.design
            );
            assert_eq!(info.uses_face_image, info.design == CardDesign::Custom);
        }
        assert_eq!(card_design_from_key(""), None);
        assert_eq!(card_design_from_key("comic"), None);
        for font in card_name_fonts() {
            assert!(font
                .file_stem
                .bytes()
                .all(|b| b.is_ascii_lowercase() || b == b'_'));
        }
    }

    #[test]
    fn old_font_keys_and_codes_read_as_nearest_design() {
        // 書体を選んでいた頃の保存のキー。
        assert_eq!(card_design_from_key("gothic"), Some(CardDesign::Pass));
        assert_eq!(card_design_from_key("mincho"), Some(CardDesign::Formal));
        assert_eq!(card_design_from_key("maru"), Some(CardDesign::Pop));
        assert_eq!(card_design_from_key("pop"), Some(CardDesign::Pop));
        assert_eq!(card_design_from_key("hand"), Some(CardDesign::Pop));
        // 書体を選んでいた頃の名刺の中身 (書体の番号 0〜4)。
        let expected = [
            None,
            Some(CardDesign::Formal),
            Some(CardDesign::Pop),
            Some(CardDesign::Pop),
            Some(CardDesign::Pop),
        ];
        let plain = write_card(&encode_producer_card(&input()).card);
        for (code, want) in expected.into_iter().enumerate() {
            let mut bytes = plain.clone();
            bytes[1] |= FLAG_DESIGN;
            bytes.push(code as u8);
            let card = read_card(&bytes).expect("書体の頃の名刺も読める");
            assert_eq!(card.design, want, "書体の番号 {code}");
        }
    }

    #[test]
    fn custom_design_falls_back_to_pass_without_face_image() {
        let mut i = input();
        i.design = Some(CardDesign::Custom);
        let card = encode_producer_card(&i).card;
        assert_eq!(
            producer_card_display_design(&card, true).design,
            CardDesign::Custom
        );
        assert_eq!(
            producer_card_display_design(&card, false).design,
            CardDesign::Pass
        );
        let plain = encode_producer_card(&input()).card;
        assert_eq!(
            producer_card_display_design(&plain, true).design,
            CardDesign::Pass
        );
    }

    #[test]
    fn card_file_carries_face_images_only_for_custom_design() {
        let face = |kind, tag| CardFileImage {
            idol_id: "x".into(),
            jpeg: jpeg(tag),
            kind,
            photo_source: None,
        };
        let images = vec![
            face(CardFileImageKind::FaceBack, 2),
            face(CardFileImageKind::FaceFront, 1),
            face(CardFileImageKind::Photo, 7),
        ];
        let mut i = input();
        i.design = Some(CardDesign::Custom);
        let custom = encode_producer_card(&i);
        let file = decode_card_file(&encode_card_file(&custom.url, &images).unwrap()).unwrap();
        assert_eq!(
            file.images
                .iter()
                .map(|i| (i.kind, i.jpeg[3]))
                .collect::<Vec<_>>(),
            vec![
                (CardFileImageKind::Photo, 7),
                (CardFileImageKind::FaceFront, 1),
                (CardFileImageKind::FaceBack, 2),
            ]
        );
        assert!(file.images.iter().all(|i| i.idol_id.is_empty()));

        // 裏だけでは載せない (表が名刺の顔)。
        let back_only = encode_card_file(&custom.url, &images[..1]).unwrap();
        assert!(decode_card_file(&back_only).unwrap().images.is_empty());

        // 自作の画像のデザインでない名刺には載せない。
        let plain = encode_producer_card(&input());
        let file = decode_card_file(&encode_card_file(&plain.url, &images).unwrap()).unwrap();
        assert_eq!(file.images.len(), 1);
        assert_eq!(file.images[0].kind, CardFileImageKind::Photo);

        // 表・裏を足す前の版の読み方 (写真の区画だけを読み、知らない区画は飛ばす) でも開ける:
        // 区画の数と長さで飛ばせる形であること。
        let bytes = encode_card_file(&custom.url, &images).unwrap();
        let without_faces = encode_card_file(&custom.url, &images[2..]).unwrap();
        assert!(bytes.len() > without_faces.len());
        let mut r = Reader {
            bytes: &bytes[CARD_FILE_MAGIC.len()..],
            pos: 0,
        };
        r.u8().unwrap();
        r.str().unwrap();
        assert_eq!(r.count(MAX_OSHI as usize), Some(0));
        let sections = r.count(MAX_CARD_FILE_SECTIONS).unwrap();
        assert_eq!(sections, 3);
        for _ in 0..sections {
            r.u8().unwrap();
            let len = r.count(MAX_CARD_FILE_IMAGE_BYTES).unwrap();
            r.pos += len;
        }
        assert_eq!(r.pos, r.bytes.len());
    }

    /// 書体・自分の QR を足す前のコア (7826fcba) が `input()` から作った名刺の中身。
    const V1_PAYLOAD: &str = "AQ8H44G144GMUC7nj77lnLDmtL7jg7tQ44Op44Kk44OW55qG5Yuk55uu5oyH44GX44Gm44G-44GZ3g9XnAMnc2hfZTY1NmUzMGUtZTRhNi00ZjhlLTg0ZmUtYWI4M2JjN2Y3ZWI4r0wCEDc2NV_lpKnmtbfmmKXpppkQNzY1X-WmguaciOWNg-aXqQIABmZ1Z2FfcAEQZnVnYS5ic2t5LnNvY2lhbAKtLCeAgSCygA";

    fn jpeg(tag: u8) -> Vec<u8> {
        vec![0xFF, 0xD8, 0xFF, tag]
    }

    #[test]
    fn card_file_carries_photo_and_old_layout_still_reads() {
        let enc = encode_producer_card(&input());
        let images = vec![
            CardFileImage {
                idol_id: "765_如月千早".into(),
                jpeg: jpeg(3),
                kind: CardFileImageKind::Oshi,
                photo_source: None,
            },
            CardFileImage {
                idol_id: "whatever".into(),
                jpeg: jpeg(7),
                kind: CardFileImageKind::Photo,
                photo_source: None,
            },
            CardFileImage {
                idol_id: String::new(),
                jpeg: jpeg(8),
                kind: CardFileImageKind::Photo,
                photo_source: None,
            },
        ];
        let bytes = encode_card_file(&enc.url, &images).unwrap();
        let file = decode_card_file(&bytes).unwrap();
        assert_eq!(file.images.len(), 2);
        assert_eq!(file.images[0].kind, CardFileImageKind::Oshi);
        assert_eq!(file.images[1].kind, CardFileImageKind::Photo);
        assert_eq!(file.images[1].jpeg, jpeg(7));
        assert_eq!(file.images[1].idol_id, "");

        // 古い版のアプリの読み方 (担当の画像の後ろを読まない) でも担当の画像は読める。
        let without_photo = encode_card_file(&enc.url, &images[..1]).unwrap();
        assert!(bytes.starts_with(&without_photo));

        // 足す前の形 (区画の無いファイル) も読める。
        let mut w = Vec::new();
        w.extend_from_slice(CARD_FILE_MAGIC);
        w.push(CARD_FILE_VERSION);
        put_str(&mut w, enc.url.split_once('#').unwrap().1);
        put_varint(&mut w, 1);
        put_str(&mut w, "765_天海春香");
        put_varint(&mut w, 4);
        w.extend_from_slice(&jpeg(5));
        let old = decode_card_file(&w).unwrap();
        assert_eq!(old.images.len(), 1);
        assert_eq!(old.images[0].kind, CardFileImageKind::Oshi);

        // 写真の区画が途中で切れていたら読まない。
        let mut cut = bytes.clone();
        cut.truncate(bytes.len() - 1);
        assert!(decode_card_file(&cut).is_none());

        // 知らない種類の区画は飛ばす。
        let mut unknown = without_photo.clone();
        put_varint(&mut unknown, 1);
        unknown.push(9);
        put_varint(&mut unknown, 2);
        unknown.extend_from_slice(&[1, 2]);
        let read = decode_card_file(&unknown).unwrap();
        assert_eq!(read.images.len(), 1);
    }

    #[test]
    fn card_file_carries_x_icon_photo_source_and_older_readers_keep_the_photo() {
        let enc = encode_producer_card(&input());
        let photo = |source| CardFileImage {
            idol_id: String::new(),
            jpeg: jpeg(7),
            kind: CardFileImageKind::Photo,
            photo_source: source,
        };
        // X のアイコンは出どころが届く (丸く出す)。
        let bytes = encode_card_file(&enc.url, &[photo(Some(CardPhotoSource::XIcon))]).unwrap();
        let file = decode_card_file(&bytes).unwrap();
        assert_eq!(file.images.len(), 1);
        assert_eq!(file.images[0].photo_source, Some(CardPhotoSource::XIcon));
        assert_eq!(card_photo_shape(CardPhotoSource::XIcon), CardPhotoShape::Round);
        // 写真から選んだ写真は出どころを書かない (足す前のファイルと同じ形)。
        let picked = encode_card_file(&enc.url, &[photo(Some(CardPhotoSource::Picked))]).unwrap();
        assert_eq!(picked, encode_card_file(&enc.url, &[photo(None)]).unwrap());
        assert_eq!(decode_card_file(&picked).unwrap().images[0].photo_source, None);
        assert_eq!(card_photo_shape(CardPhotoSource::Picked), CardPhotoShape::Square);
        // 出どころは写真の後ろの別の区画なので、その区画を知らない読み方でも写真は読める
        // (知らない区画として飛ばす。区画の種類を知らない番号に替えて確かめる)。
        let mut older = bytes.clone();
        let at = older.len() - 3;
        assert_eq!(older[at], SECTION_PHOTO_SOURCE);
        older[at] = 9;
        let read = decode_card_file(&older).unwrap();
        assert_eq!(read.images.len(), 1);
        assert_eq!(read.images[0].jpeg, jpeg(7));
        assert_eq!(read.images[0].photo_source, None);
        // 担当の画像には出どころを持たせない。
        let oshi = CardFileImage {
            idol_id: "765_如月千早".into(),
            jpeg: jpeg(3),
            kind: CardFileImageKind::Oshi,
            photo_source: Some(CardPhotoSource::XIcon),
        };
        let file = decode_card_file(&encode_card_file(&enc.url, &[oshi]).unwrap()).unwrap();
        assert_eq!(file.images[0].photo_source, None);
    }

    #[test]
    fn photo_source_keys_round_trip_and_unknown_reads_as_picked() {
        for source in [CardPhotoSource::Picked, CardPhotoSource::XIcon] {
            assert_eq!(card_photo_source_from_key(&card_photo_source_key(source)), source);
        }
        assert_eq!(card_photo_source_from_key(""), CardPhotoSource::Picked);
        assert_eq!(card_photo_source_from_key("instagram"), CardPhotoSource::Picked);
    }
}
