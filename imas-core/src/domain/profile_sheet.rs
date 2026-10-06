//! P名刺の画像 (SNS に貼る自己紹介の 1 枚絵) の中身・欄の割り当て・行の組み立て。
//!
//! P名刺の 3 つ目の出し方 (交換する・紙に刷る・SNS に貼る画像)。名刺は交換するもの (誰で、どうつながれるか)、
//! この画像は見せるもの (どんな P か)。2026-10 に「プロフィール帳」という別の機能をやめて P名刺に一本化した。
//! P を「職業」に見立てた **履歴書** の様式で 1 枚にする
//! (職務経歴書の様式は 2026-10 にやめた。1 つに絞り、絵になる証明写真・押印・担当ブランドの丸のある履歴書を残した)。
//! **自分で書く欄は無い**。中身はすべてアプリの記録から埋まり、本人は大きさと載せる記録を選ぶだけ。
//!
//! 欄: 氏名・押印・証明写真・P歴・担当・連絡先、担当ブランド、P歴 (学歴・職歴) の表
//! (就任 / はじめての参加 / 最近の現場 / 以上)、免許・資格 (参加公演数・回収曲数)、
//! 志望の動機 (好きな曲)、本人希望記入欄 (次の現場)。
//! 本人が選んだもの (担当・好きな曲・担当ブランド・写真) を前に出し、記録から数えた数字は一目で分かるもの
//! (P歴・はじめての参加・次の現場・参加公演数) だけを小さく載せる (担当の歌唱の回数・現地でいちばん聴いた曲・
//! いちばん通った会場・いちばん通った年・現地に行った都道府県の数はやめた。2026-10 ユーザー
//! 「基本いらない」「一番聞いた曲とかは本人からしても『あ、そうなんだ』って感じ」
//! 「一番通った年とか書いてもあんまり意味ないかもしれない」)。
//! 好きな曲はお気に入りの中から本人が選ぶ (`favorite_song_picks`。まだ選んでいなければ新しい順の先頭から)。
//!
//! どの記録がどの欄に入るか・欄の並び・行の組み立て・上限・文字の詰め方 (`ProfileSheetDensity`)・
//! 担当ブランドの丸はここで決め、端末 (iOS / Android) はこの結果を描くだけにする。
//! 担当ブランドの丸はアプリ全体の設定 (`brand_role`。担当 = 丸・メイン = 二重丸、メインは複数可) から描き、
//! 設定がまだ無ければ記録から組んだ既定を使う。P名刺の画像の中では丸を上書きしない。
//!
//! 保存するのは選択だけ (自分の P名刺の行に JSON で持つ。`profile_sheet_to_json`)。大きさと外した欄は画像の
//! 画面で、好きな曲 (曲 id の並び) は P名刺の編集で選ぶ (好きな曲は P名刺の項目。名刺の QR には入らない)。
//! 名前・P歴・書体・リンク・自分の QR・証明写真の欄の写真は P名刺のものを使う。

use crate::domain::brand_role::{
    brand_role_settings, BrandRole, BrandRoleBrand, BrandRoleRecord, BrandRoleVisit,
};
use crate::domain::favorite_song_picks::{favorite_song_picked, ProfileSongInput};
use chrono::{Datelike, NaiveDate};
use std::collections::HashSet;

// ---------------------------------------------------------------------------
// 型
// ---------------------------------------------------------------------------

/// 書き出す画像の大きさ。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum ProfileSheetSize {
    /// 4:5 (1080×1350px)。X のタイムラインで大きく出る。
    #[default]
    Portrait,
    /// 9:16 (1080×1920px)。ストーリーズ向け。
    Story,
}

/// アプリの記録から自動で埋まる欄 (外せる)。保存のキーは変えない。並びは選ぶ画面の順。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileAutoField {
    /// 証明写真の欄。
    Photo,
    /// 担当 (押印欄の判子と担当の行)。
    Oshi,
    /// 担当ブランド (ブランドの名前に丸)。
    Brands,
    /// P歴 (就任の年。P名刺から)。
    Since,
    /// はじめて参加したライブ・最近の現場。
    Shows,
    /// 次の現場。
    NextShow,
    /// 参加公演数・回収曲数。
    Counts,
    /// 好きな曲 (お気に入りの中から選んだ曲)。
    Songs,
    /// リンク (連絡先。P名刺から)。
    Links,
    /// 自分の QR (P名刺から。既定は載せない)。
    Qr,
}

/// 欄 (履歴書の下の 2 つ)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileSlot {
    /// 志望の動機 (好きな曲)。
    Motivation,
    /// 本人希望記入欄 (次の現場)。
    Wish,
}

/// 文字の詰め方。中身の量と画像の大きさで決まる (端末は文字の大きさに読み替える)。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProfileSheetDensity {
    /// ゆったり。
    Regular,
    /// 詰める。
    Compact,
    /// さらに詰める (それでも入らない分は端末が行の中で縮める)。
    Tight,
}

/// P名刺の画像の選択 (端末に保存するもの)。中身は毎回アプリの記録から組む。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheet {
    pub size: ProfileSheetSize,
    /// 外した自動の欄。
    pub hidden: Vec<ProfileAutoField>,
    /// 載せる好きな曲 (曲 id、載せる順)。None はまだ選んでいない (お気に入りの新しい順の先頭から)。
    pub songs: Option<Vec<String>>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAutoFieldInfo {
    pub field: ProfileAutoField,
    pub key: String,
    /// 選ぶ画面の名前 (「参加公演数・回収曲数」)。
    pub label: String,
}

/// 選ぶ画面の「載せる記録」の 1 行。記録の無い欄は並べない。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAutoFieldRow {
    pub field: ProfileAutoField,
    pub key: String,
    pub label: String,
    /// 今の記録で載る中身の短い見本 (「19公演・323曲」)。写真・QR・担当ブランドは空。
    pub value: String,
    /// 載せているか。
    pub shown: bool,
    /// 中身が P名刺から入る欄か (P歴・リンク・自分の QR)。直すのは P名刺の編集。
    pub from_card: bool,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheetSizeInfo {
    pub size: ProfileSheetSize,
    pub key: String,
    /// 「4:5」。
    pub label: String,
    /// 「縦長」。
    pub caption: String,
    pub width_px: u32,
    pub height_px: u32,
}

// --- 組み立ての材料 (端末がアプリの記録から集めて渡す) ---

/// 参加を付けた公演 1 件 (今後の参加予定も混ざってよい)。表記は端末が引いて渡す。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileShowInput {
    pub show_id: String,
    /// `YYYY-MM-DD`。
    pub date: String,
    /// 公演の表記 (`show_display_title`)。
    pub title: String,
    pub venue: Option<String>,
    /// ライブのブランド。
    pub brand_id: Option<String>,
}

/// ブランド 1 つ (端末のマスタのまま渡す。並べる順と並べないブランドはコアが決める)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileBrandInput {
    pub id: String,
    /// 短い名前 (「ミリオン」)。
    pub label: String,
    /// ブランドの色 (hex)。丸の線に使う。
    pub color: Option<String>,
    pub sort_order: i64,
}

/// P名刺の画像の材料。名前・P歴・リンク・QR は P名刺から、ほかはアプリの記録から。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheetRecord {
    /// 今日 (`YYYY-MM-DD`、JST)。
    pub today: String,
    pub name: String,
    pub since_year: Option<u16>,
    /// 担当の名前 (担当の順)。
    pub oshi_names: Vec<String>,
    /// 担当の所属ブランド (担当の順。担当ブランドの既定に使う)。
    pub oshi_brand_ids: Vec<String>,
    pub attended: Vec<ProfileShowInput>,
    pub song_count: u32,
    pub brands: Vec<ProfileBrandInput>,
    /// 担当ブランドの設定 (アプリ全体の設定の保存の形 `brand_roles_to_json`。空はまだ決めていない)。
    pub brand_roles_json: String,
    /// お気に入りの曲すべて (並びは問わない。載せる曲と順は [`ProfileSheet::songs`] の選択から)。
    pub favorite_songs: Vec<ProfileSongInput>,
    /// 連絡先に出すリンク (`card_link_view` の display)。
    pub links: Vec<String>,
    /// 証明写真の欄に入れる画像があるか (P名刺の写真があるか)。
    pub has_photo: bool,
    /// P名刺に自分の QR があるか。
    pub has_qr: bool,
}

// --- 組み立てた結果 (端末が描く) ---

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProfileHistoryKind {
    Since,
    FirstShow,
    RecentShow,
    /// 免許・資格の行 (記録の達成)。
    Count,
    /// 表の終わりの「以上」(右に寄せる)。
    Closing,
}

/// 年・月・内容の 1 行 (P歴と免許・資格の表)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileHistoryRow {
    pub year: String,
    pub month: String,
    pub text: String,
    pub kind: ProfileHistoryKind,
}

/// 手描きの楕円 1 本。揺らぎは id から決まる (書き出すたびに形が変わらない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileHandRing {
    /// 傾き (度)。
    pub tilt_degrees: f64,
    /// 横の伸び (1.0 で名前の幅どおり)。
    pub stretch: f64,
    /// 線の書き始めの角度 (度、0〜359)。書き終わりは少し行き過ぎて重なる。
    pub start_degrees: f64,
    /// 大きさ (1.0 で 1 本目と同じ)。
    pub scale: f64,
    /// 中心のずれ (名前の枠の幅・高さに対する割合)。
    pub offset_x: f64,
    pub offset_y: f64,
}

/// 担当ブランドのブランド 1 つ。刷ってあるブランドの名前に、担当しているものだけ手描きの丸を付ける
/// (メインは 2 本の二重丸。メインは複数あってよい)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileBrandCheck {
    pub id: String,
    pub label: String,
    pub color: Option<String>,
    /// 丸を付けるか (担当かメイン)。
    pub checked: bool,
    /// メイン (二重丸) か。
    pub main: bool,
    /// 描く楕円 (なしは 0 本・担当は 1 本・メインは 2 本)。
    pub rings: Vec<ProfileHandRing>,
}

/// 欄の中の 1 項目 (見出しと中身)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileEntry {
    pub field: ProfileAutoField,
    /// 「現地でいちばん聴いた曲」。
    pub label: String,
    pub text: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSection {
    pub slot: ProfileSlot,
    /// 「志望の動機」。
    pub title: String,
    /// 英字の印字 (「MOTIVATION」)。
    pub imprint: String,
    pub entries: Vec<ProfileEntry>,
}

/// 描く形。欄は様式の並び順で、中身の無い欄は入れない。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileSheetLayout {
    pub size: ProfileSheetSize,
    /// 「履歴書」。
    pub title: String,
    /// 「RÉSUMÉ」。
    pub imprint: String,
    /// 「2026年10月6日現在」。
    pub as_of: String,
    pub name: String,
    pub show_photo: bool,
    pub show_oshi: bool,
    pub show_qr: bool,
    /// 「2014年 就任 · P歴12年」。外したら None。
    pub since_label: Option<String>,
    /// 連絡先 (外したら空)。
    pub contacts: Vec<String>,
    /// 担当ブランドの欄の名前 (「担当ブランド」)。
    pub brands_title: String,
    /// 担当ブランドの並び (外したら空)。
    pub brands: Vec<ProfileBrandCheck>,
    /// P歴の表。最後の行は「以上」。
    pub history: Vec<ProfileHistoryRow>,
    /// 免許・資格。
    pub licenses: Vec<ProfileHistoryRow>,
    pub sections: Vec<ProfileSection>,
    pub density: ProfileSheetDensity,
}

// ---------------------------------------------------------------------------
// 決まり
// ---------------------------------------------------------------------------

const TITLE: &str = "履歴書";
const IMPRINT: &str = "RÉSUMÉ";
const BRANDS_TITLE: &str = "担当ブランド";

/// 選ぶ画面の順。本人が選んだもの (写真・担当・担当ブランド・好きな曲) を先に、記録から数えたものを後に。
const ALL_AUTO_FIELDS: [ProfileAutoField; 10] = [
    ProfileAutoField::Photo,
    ProfileAutoField::Oshi,
    ProfileAutoField::Brands,
    ProfileAutoField::Songs,
    ProfileAutoField::Since,
    ProfileAutoField::Shows,
    ProfileAutoField::NextShow,
    ProfileAutoField::Counts,
    ProfileAutoField::Links,
    ProfileAutoField::Qr,
];

const ALL_SIZES: [ProfileSheetSize; 2] = [ProfileSheetSize::Portrait, ProfileSheetSize::Story];

const SLOTS: [ProfileSlot; 2] = [ProfileSlot::Motivation, ProfileSlot::Wish];

pub fn profile_auto_field_info(field: ProfileAutoField) -> ProfileAutoFieldInfo {
    use ProfileAutoField as F;
    let (key, label) = match field {
        F::Photo => ("photo", "証明写真"),
        F::Oshi => ("oshi", "担当"),
        F::Brands => ("brands", "担当ブランド"),
        F::Since => ("since", "P歴"),
        F::Shows => ("shows", "はじめての参加・最近の現場"),
        F::NextShow => ("next_show", "次の現場"),
        F::Counts => ("counts", "参加公演数・回収曲数"),
        F::Songs => ("songs", "好きな曲"),
        F::Links => ("links", "連絡先 (リンク)"),
        F::Qr => ("qr", "自分の QR"),
    };
    ProfileAutoFieldInfo {
        field,
        key: key.into(),
        label: label.into(),
    }
}

/// 自動の欄の一覧 (選ぶ画面の順)。
pub fn profile_auto_fields() -> Vec<ProfileAutoFieldInfo> {
    ALL_AUTO_FIELDS
        .into_iter()
        .map(profile_auto_field_info)
        .collect()
}

/// 中身が P名刺から入る欄。
fn from_card(field: ProfileAutoField) -> bool {
    matches!(
        field,
        ProfileAutoField::Since | ProfileAutoField::Links | ProfileAutoField::Qr
    )
}

pub fn profile_sheet_size_info(size: ProfileSheetSize) -> ProfileSheetSizeInfo {
    let (key, label, caption, h) = match size {
        ProfileSheetSize::Portrait => ("portrait", "4:5", "縦長", 1350),
        ProfileSheetSize::Story => ("story", "9:16", "ストーリーズ", 1920),
    };
    ProfileSheetSizeInfo {
        size,
        key: key.into(),
        label: label.into(),
        caption: caption.into(),
        width_px: 1080,
        height_px: h,
    }
}

pub fn profile_sheet_sizes() -> Vec<ProfileSheetSizeInfo> {
    ALL_SIZES.into_iter().map(profile_sheet_size_info).collect()
}

/// はじめて開いたときの選択。4:5、自分の QR だけ外しておく (載せるかは本人が決める)。
pub fn profile_sheet_default() -> ProfileSheet {
    ProfileSheet {
        size: ProfileSheetSize::default(),
        hidden: vec![ProfileAutoField::Qr],
        songs: None,
    }
}

fn slot_title(slot: ProfileSlot) -> (&'static str, &'static str) {
    match slot {
        ProfileSlot::Motivation => ("志望の動機", "MOTIVATION"),
        ProfileSlot::Wish => ("本人希望記入欄", "REQUESTS"),
    }
}

// ---------------------------------------------------------------------------
// 保存の形 (端末の表に JSON で入れる)
// ---------------------------------------------------------------------------

fn auto_field_from_key(key: &str) -> Option<ProfileAutoField> {
    ALL_AUTO_FIELDS
        .into_iter()
        .find(|f| profile_auto_field_info(*f).key == key)
}

/// 保存の形。前の版が書いた `style` (職務経歴書)・`brandOn` / `brandOff` / `brandMain` (P名刺の画像の中の
/// 丸の上書き)・`furigana` / `answers` / `songs` (自分で書く欄) は読み捨てる (serde は知らないキーを無視する)。
/// 選んだ好きな曲は `songIds` (前の版の `songs` とは別のキー。無ければまだ選んでいない)。
#[derive(serde::Serialize, serde::Deserialize, Default)]
#[serde(default)]
struct SheetDto {
    size: String,
    hidden: Vec<String>,
    #[serde(rename = "songIds", skip_serializing_if = "Option::is_none")]
    song_ids: Option<Vec<String>>,
}

/// 保存の形 (キーは英字)。
pub fn profile_sheet_to_json(sheet: &ProfileSheet) -> String {
    let dto = SheetDto {
        size: profile_sheet_size_info(sheet.size).key,
        hidden: ALL_AUTO_FIELDS
            .into_iter()
            .filter(|f| sheet.hidden.contains(f))
            .map(|f| profile_auto_field_info(f).key)
            .collect(),
        song_ids: sheet.songs.clone(),
    };
    serde_json::to_string(&dto).unwrap_or_default()
}

/// 保存の形から戻す。空・壊れた JSON は既定の選択。知らない欄のキー (新しい版が足したもの・
/// 前の版にあってやめた欄) は捨てる (読めない 1 項目のために全部を失わない)。
pub fn profile_sheet_from_json(json: &str) -> ProfileSheet {
    let Ok(dto) = serde_json::from_str::<SheetDto>(json) else {
        return profile_sheet_default();
    };
    let size = ALL_SIZES
        .into_iter()
        .find(|s| profile_sheet_size_info(*s).key == dto.size)
        .unwrap_or_default();
    let mut hidden: Vec<ProfileAutoField> = Vec::new();
    for f in dto.hidden.iter().filter_map(|k| auto_field_from_key(k)) {
        if !hidden.contains(&f) {
            hidden.push(f);
        }
    }
    ProfileSheet {
        size,
        hidden,
        songs: dto.song_ids,
    }
}

// ---------------------------------------------------------------------------
// 組み立て
// ---------------------------------------------------------------------------

/// 大きさごとの P歴の表の行数の上限 (「以上」を除く)。
fn history_cap(size: ProfileSheetSize) -> usize {
    match size {
        ProfileSheetSize::Portrait => 4,
        ProfileSheetSize::Story => 5,
    }
}

/// 中身の量 (行の見積もり) の上限。これを超えたら 1 段ずつ詰める。
fn density_caps(size: ProfileSheetSize) -> (u32, u32) {
    match size {
        ProfileSheetSize::Portrait => (16, 23),
        ProfileSheetSize::Story => (34, 46),
    }
}

/// 1 行に入る文字数の見積もり (全角で、欄の幅いっぱい)。
const CHARS_PER_LINE: usize = 30;

/// 記録を数えた中間の形 (組み立てと選ぶ画面の見本で共有する)。
struct Facts<'a> {
    today: Option<NaiveDate>,
    /// 行った公演 (日付の昇順、重複なし)。
    past: Vec<(NaiveDate, &'a ProfileShowInput)>,
    /// 次の現場 (いちばん近い予定)。
    next: Option<(NaiveDate, &'a ProfileShowInput)>,
    /// 載せる好きな曲 (選んだ順。まだ選んでいなければお気に入りの新しい順の先頭から)。
    songs: Vec<ProfileSongInput>,
    /// 好きな曲を本人が選んだか。
    songs_chosen: bool,
    record: &'a ProfileSheetRecord,
}

impl<'a> Facts<'a> {
    fn new(sheet: &ProfileSheet, record: &'a ProfileSheetRecord) -> Self {
        let today = parse_date(&record.today);
        let mut seen = HashSet::new();
        let mut past: Vec<(NaiveDate, &ProfileShowInput)> = Vec::new();
        let mut next: Option<(NaiveDate, &ProfileShowInput)> = None;
        for s in &record.attended {
            if !seen.insert(s.show_id.as_str()) {
                continue;
            }
            let (Some(day), Some(today)) = (parse_date(&s.date), today) else {
                continue;
            };
            if day <= today {
                past.push((day, s));
            } else if next.is_none_or(|(d, n)| (day, &s.show_id) < (d, &n.show_id)) {
                next = Some((day, s));
            }
        }
        past.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.show_id.cmp(&b.1.show_id)));

        Facts {
            today,
            past,
            next,
            songs: favorite_song_picked(sheet.songs.as_deref(), &record.favorite_songs),
            songs_chosen: sheet.songs.is_some(),
            record,
        }
    }

    fn favorite_titles(&self) -> Option<String> {
        let titles: Vec<String> = self
            .songs
            .iter()
            .map(|s| format!("「{}」", s.title))
            .collect();
        (!titles.is_empty()).then(|| titles.join(""))
    }

    fn has_counts(&self) -> bool {
        !self.past.is_empty() || self.record.song_count > 0
    }

    fn counts_text(&self) -> String {
        format!(
            "参加公演 {}公演・回収曲 {}曲",
            self.past.len(),
            self.record.song_count
        )
    }

    fn next_text(&self) -> Option<String> {
        self.next.map(|(d, s)| {
            let venue = s
                .venue
                .as_deref()
                .map(str::trim)
                .filter(|v| !v.is_empty())
                .map(|v| format!("（{v}）"))
                .unwrap_or_default();
            format!(
                "{}年{}月{}日　{}{venue}",
                d.year(),
                d.month(),
                d.day(),
                s.title
            )
        })
    }

    /// その欄に載せる記録があるか (無い欄は出さない・選ぶ画面に並べない)。
    fn has(&self, field: ProfileAutoField) -> bool {
        use ProfileAutoField as F;
        let r = self.record;
        match field {
            F::Photo => r.has_photo,
            F::Oshi => !r.oshi_names.is_empty(),
            F::Brands => !listed_brands(r).is_empty(),
            F::Since => r.since_year.is_some(),
            F::Shows => !self.past.is_empty(),
            F::NextShow => self.next.is_some(),
            F::Counts => self.has_counts(),
            F::Songs => !r.favorite_songs.is_empty(),
            F::Links => !r.links.is_empty(),
            F::Qr => r.has_qr,
        }
    }

    /// 選ぶ画面に添える短い見本。
    fn preview(&self, field: ProfileAutoField) -> String {
        use ProfileAutoField as F;
        let r = self.record;
        match field {
            F::Photo | F::Qr | F::Brands => String::new(),
            F::Oshi => r.oshi_names.join("・"),
            F::Since => r
                .since_year
                .map(|y| format!("{y}年 就任"))
                .unwrap_or_default(),
            F::Shows => self
                .past
                .first()
                .map(|(_, s)| format!("はじめて参加　{}", s.title))
                .unwrap_or_default(),
            F::NextShow => self.next.map(|(_, s)| s.title.clone()).unwrap_or_default(),
            F::Counts => format!("{}公演・{}曲", self.past.len(), r.song_count),
            F::Songs => match self.favorite_titles() {
                Some(titles) if self.songs_chosen => titles,
                Some(titles) => format!("おまかせ (お気に入りの新しい順)　{titles}"),
                None => "載せる曲を選んでいません".into(),
            },
            F::Links => r.links.join("　"),
        }
    }
}

/// 選ぶ画面の「載せる記録」の行。記録のある欄だけを選ぶ画面の順に。
pub fn profile_auto_field_rows(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> Vec<ProfileAutoFieldRow> {
    let facts = Facts::new(sheet, record);
    ALL_AUTO_FIELDS
        .into_iter()
        .filter(|f| facts.has(*f))
        .map(|f| {
            let info = profile_auto_field_info(f);
            ProfileAutoFieldRow {
                field: f,
                key: info.key,
                label: info.label,
                value: facts.preview(f),
                shown: !sheet.hidden.contains(&f),
                from_card: from_card(f),
            }
        })
        .collect()
}

/// 載せる欄を 1 つ付け外しした選択。外した欄は選ぶ画面の順に並べ直す (保存の形と同じ並びにして、
/// 付けて外して戻しただけの選択が「変わった」に見えないように)。
pub fn profile_toggle_field(sheet: &ProfileSheet, field: ProfileAutoField) -> ProfileSheet {
    let mut out = sheet.clone();
    let hide = !out.hidden.contains(&field);
    out.hidden = ALL_AUTO_FIELDS
        .into_iter()
        .filter(|f| {
            if *f == field {
                hide
            } else {
                sheet.hidden.contains(f)
            }
        })
        .collect();
    out
}

pub fn profile_sheet_layout(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> ProfileSheetLayout {
    let facts = Facts::new(sheet, record);
    // 載せる欄: 外しておらず、記録がある。
    let on = |f: ProfileAutoField| !sheet.hidden.contains(&f) && facts.has(f);
    let today = facts.today;
    let past = &facts.past;

    let since_label = record
        .since_year
        .filter(|_| on(ProfileAutoField::Since))
        .map(|y| match today.map(|t| t.year() - i32::from(y)) {
            Some(n) if n >= 1 => format!("{y}年 就任 · P歴{n}年"),
            _ => format!("{y}年 就任"),
        });

    let brands = if on(ProfileAutoField::Brands) {
        profile_brand_marks(record)
    } else {
        Vec::new()
    };

    // P歴の表: 年の順 (同じ年は 就任 → はじめて → 最近)。
    let mut dated: Vec<((i32, u32), ProfileHistoryRow)> = Vec::new();
    if let Some(y) = record.since_year.filter(|_| on(ProfileAutoField::Since)) {
        dated.push((
            (i32::from(y), 0),
            ProfileHistoryRow {
                year: y.to_string(),
                month: String::new(),
                text: "プロデューサーに就任".into(),
                kind: ProfileHistoryKind::Since,
            },
        ));
    }
    if on(ProfileAutoField::Shows) {
        if let Some((d, s)) = past.first() {
            dated.push((
                (d.year(), d.month()),
                history_row(
                    *d,
                    format!("はじめて参加　{}", s.title),
                    ProfileHistoryKind::FirstShow,
                ),
            ));
        }
    }
    if on(ProfileAutoField::Shows) && past.len() >= 2 {
        let (d, s) = past[past.len() - 1];
        dated.push((
            (d.year(), 14),
            history_row(
                d,
                format!("最近の現場　{}", s.title),
                ProfileHistoryKind::RecentShow,
            ),
        ));
    }
    dated.sort_by_key(|(k, _)| *k);
    let mut history: Vec<ProfileHistoryRow> = dated.into_iter().map(|(_, r)| r).collect();
    history.truncate(history_cap(sheet.size));
    if !history.is_empty() {
        history.push(ProfileHistoryRow {
            year: String::new(),
            month: String::new(),
            text: "以上".into(),
            kind: ProfileHistoryKind::Closing,
        });
    }

    // 免許・資格: 記録の達成 (今日の日付で)。
    let mut licenses = Vec::new();
    if let Some(t) = today {
        if on(ProfileAutoField::Counts) {
            licenses.push(history_row(
                t,
                format!("{} 達成", facts.counts_text()),
                ProfileHistoryKind::Count,
            ));
        }
    }

    // 欄: 記録を様式の欄に割り当てる。中身の無い欄は出さない。
    let mut sections: Vec<ProfileSection> = Vec::new();
    for slot in SLOTS {
        let mut entries: Vec<ProfileEntry> = Vec::new();
        let mut push = |field: ProfileAutoField, label: &str, text: Option<String>| {
            if let Some(text) = text.filter(|_| on(field)) {
                entries.push(ProfileEntry {
                    field,
                    label: label.into(),
                    text,
                });
            }
        };
        use ProfileAutoField as F;
        match slot {
            ProfileSlot::Motivation => {
                push(F::Songs, "好きな曲", facts.favorite_titles());
            }
            ProfileSlot::Wish => {
                push(F::NextShow, "次の現場", facts.next_text());
            }
        }
        if !entries.is_empty() {
            let (title, imprint) = slot_title(slot);
            sections.push(ProfileSection {
                slot,
                title: title.into(),
                imprint: imprint.into(),
                entries,
            });
        }
    }

    let density = density_of(sheet.size, &sections, &history, &licenses);

    ProfileSheetLayout {
        size: sheet.size,
        title: TITLE.into(),
        imprint: IMPRINT.into(),
        as_of: today
            .map(|d| format!("{}年{}月{}日現在", d.year(), d.month(), d.day()))
            .unwrap_or_default(),
        name: record.name.trim().to_string(),
        show_photo: on(ProfileAutoField::Photo),
        show_oshi: on(ProfileAutoField::Oshi),
        show_qr: on(ProfileAutoField::Qr),
        since_label,
        contacts: if on(ProfileAutoField::Links) {
            record.links.clone()
        } else {
            Vec::new()
        },
        brands_title: BRANDS_TITLE.into(),
        brands,
        history,
        licenses,
        sections,
        density,
    }
}

/// 中身の量の見積もり: 欄の項目 (見出し 1 行 + 本文の折り返し)・表の行。
/// 趣味・特技と本人希望記入欄は左右に半分ずつ並ぶので、1 行に入る字も半分。
/// 横に並ぶ欄は高い方に揃うので、2 つのうち多い方を数える。
fn density_of(
    size: ProfileSheetSize,
    sections: &[ProfileSection],
    history: &[ProfileHistoryRow],
    licenses: &[ProfileHistoryRow],
) -> ProfileSheetDensity {
    let paired = |s: &ProfileSection| s.slot != ProfileSlot::Motivation;
    let section_lines = |s: &ProfileSection| -> u32 {
        let per_line = if paired(s) {
            CHARS_PER_LINE / 2
        } else {
            CHARS_PER_LINE
        };
        let entries: u32 = s
            .entries
            .iter()
            .map(|e| {
                let label = u32::from(!e.label.is_empty());
                let body: u32 = e
                    .text
                    .split('\n')
                    .map(|l| char_len(l).div_ceil(per_line).max(1) as u32)
                    .sum();
                label + body
            })
            .sum();
        1 + entries
    };
    let full: u32 = sections
        .iter()
        .filter(|s| !paired(s))
        .map(section_lines)
        .sum();
    let pair: u32 = sections
        .iter()
        .filter(|s| paired(s))
        .map(section_lines)
        .max()
        .unwrap_or(0);
    let table_lines = (history.len() + licenses.len()) as u32;
    let load = full + pair + table_lines;
    let (regular, compact) = density_caps(size);
    if load <= regular {
        ProfileSheetDensity::Regular
    } else if load <= compact {
        ProfileSheetDensity::Compact
    } else {
        ProfileSheetDensity::Tight
    }
}

fn history_row(day: NaiveDate, text: String, kind: ProfileHistoryKind) -> ProfileHistoryRow {
    ProfileHistoryRow {
        year: day.year().to_string(),
        month: day.month().to_string(),
        text,
        kind,
    }
}

// ---------------------------------------------------------------------------
// 担当ブランド (アプリ全体の設定から丸を付ける・メインは二重丸)
// ---------------------------------------------------------------------------

/// 担当ブランドの設定の材料 (P名刺の画像の材料から)。
fn brand_role_record(record: &ProfileSheetRecord) -> BrandRoleRecord {
    BrandRoleRecord {
        today: record.today.clone(),
        brands: record
            .brands
            .iter()
            .map(|b| BrandRoleBrand {
                id: b.id.clone(),
                label: b.label.clone(),
                color: b.color.clone(),
                sort_order: b.sort_order,
            })
            .collect(),
        oshi_brand_ids: record.oshi_brand_ids.clone(),
        visits: record
            .attended
            .iter()
            .map(|s| BrandRoleVisit {
                date: s.date.clone(),
                brand_id: s.brand_id.clone(),
            })
            .collect(),
    }
}

/// 並べるブランド (ブランドの並び順、その他を除く)。
fn listed_brands(record: &ProfileSheetRecord) -> Vec<BrandRoleBrand> {
    let r = brand_role_record(record);
    crate::domain::brand_role::listed_brands(&r.brands)
        .into_iter()
        .cloned()
        .collect()
}

/// 担当ブランドの並び (ブランドの並び順、その他を除く) と丸。丸は担当ブランドの設定 (まだ決めて
/// いなければ記録から組んだ既定) から: 担当は丸、メインは二重丸 (メインは複数あってよい)。
pub fn profile_brand_marks(record: &ProfileSheetRecord) -> Vec<ProfileBrandCheck> {
    brand_role_settings(&record.brand_roles_json, &brand_role_record(record))
        .rows
        .into_iter()
        .map(|row| {
            let rings = match row.role {
                BrandRole::None => Vec::new(),
                BrandRole::Oshi => vec![hand_ring(&row.brand_id, 0)],
                BrandRole::Main => vec![hand_ring(&row.brand_id, 0), hand_ring(&row.brand_id, 1)],
            };
            ProfileBrandCheck {
                checked: row.role != BrandRole::None,
                main: row.role == BrandRole::Main,
                id: row.brand_id,
                label: row.label,
                color: row.color,
                rings,
            }
        })
        .collect()
}

/// 手描きの楕円の揺らぎ (id と何本目かから決める)。1 本目は名前を囲み、2 本目は少し大きく、
/// 傾きと中心をずらして重ねる (二重丸)。
fn hand_ring(id: &str, nth: u32) -> ProfileHandRing {
    let h = fnv1a(id);
    let base_tilt = f64::from(h % 19) - 9.0;
    if nth == 0 {
        return ProfileHandRing {
            tilt_degrees: base_tilt,
            stretch: 0.92 + f64::from((h >> 8) % 21) / 100.0,
            start_degrees: f64::from((h >> 16) % 360),
            scale: 1.0,
            offset_x: 0.0,
            offset_y: 0.0,
        };
    }
    let g = fnv1a(&format!("{id}#{nth}"));
    // 2 本目は傾きを 1 本目と逆向きに 6〜11 度ずらす (同じ向きだと 1 本の太い線に見える)。
    let turn = 6.0 + f64::from(g % 6);
    let tilt = if base_tilt >= 0.0 {
        base_tilt - turn
    } else {
        base_tilt + turn
    };
    ProfileHandRing {
        tilt_degrees: tilt,
        stretch: 0.96 + f64::from((g >> 8) % 17) / 100.0,
        start_degrees: f64::from((g >> 16) % 360),
        scale: 1.22 + f64::from((g >> 4) % 9) / 100.0,
        offset_x: (f64::from((g >> 12) % 9) - 4.0) / 100.0,
        offset_y: (f64::from((g >> 20) % 21) - 10.0) / 100.0,
    }
}

/// 32 bit FNV-1a (丸の揺らぎを id から決めるだけに使う)。
fn fnv1a(s: &str) -> u32 {
    let mut h: u32 = 0x811c_9dc5;
    for b in s.bytes() {
        h ^= u32::from(b);
        h = h.wrapping_mul(0x0100_0193);
    }
    h
}

fn parse_date(s: &str) -> Option<NaiveDate> {
    NaiveDate::parse_from_str(s.get(..10)?, "%Y-%m-%d").ok()
}

fn char_len(s: &str) -> usize {
    s.chars().count()
}

// ---------------------------------------------------------------------------
// テスト
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    fn show(id: &str, date: &str, brand: &str) -> ProfileShowInput {
        ProfileShowInput {
            show_id: id.into(),
            date: date.into(),
            title: format!("公演{id}"),
            venue: Some(format!("会場{id}")),
            brand_id: Some(brand.into()),
        }
    }

    fn song(id: &str, at: &str) -> ProfileSongInput {
        ProfileSongInput {
            id: id.into(),
            title: format!("曲{}", id.trim_start_matches('s')),
            favorited_at: at.into(),
        }
    }

    fn brand(id: &str, label: &str, order: i64) -> ProfileBrandInput {
        ProfileBrandInput {
            id: id.into(),
            label: label.into(),
            color: None,
            sort_order: order,
        }
    }

    fn record() -> ProfileSheetRecord {
        ProfileSheetRecord {
            today: "2026-10-06".into(),
            name: " ふがP ".into(),
            since_year: Some(2014),
            oshi_names: vec!["天海春香".into()],
            oshi_brand_ids: vec!["765".into()],
            attended: vec![
                show("b", "2025-03-01", "ml"),
                show("a", "2015-07-18", "765"),
                show("c", "2026-09-14", "cg"),
                show("d", "2026-09-15", "cg"),
                show("n", "2026-11-03", "765"),
                show("a", "2015-07-18", "765"),
            ],
            song_count: 523,
            brands: vec![
                brand("765", "765", 1),
                brand("cg", "シンデレラ", 4),
                brand("ml", "ミリオン", 5),
                brand("sm", "SideM", 6),
            ],
            brand_roles_json: String::new(),
            favorite_songs: vec![
                song("s1", "2026-01-01T00:00:00Z"),
                song("s2", "2026-02-01T00:00:00Z"),
            ],
            links: vec!["@fuga_p".into()],
            has_photo: true,
            has_qr: true,
        }
    }

    /// 記録の少ない人 (参加 1 公演だけ・担当なし・お気に入りなし)。
    fn sparse_record() -> ProfileSheetRecord {
        ProfileSheetRecord {
            since_year: None,
            oshi_names: Vec::new(),
            oshi_brand_ids: Vec::new(),
            attended: vec![show("x", "2026-08-01", "ml")],
            song_count: 0,
            favorite_songs: Vec::new(),
            links: Vec::new(),
            has_photo: false,
            has_qr: false,
            ..record()
        }
    }

    #[test]
    fn default_is_portrait_with_qr_hidden() {
        let s = profile_sheet_default();
        assert_eq!(s.size, ProfileSheetSize::Portrait);
        assert_eq!(s.hidden, vec![ProfileAutoField::Qr]);
    }

    #[test]
    fn json_round_trip_keeps_choices() {
        let s = ProfileSheet {
            size: ProfileSheetSize::Story,
            hidden: vec![ProfileAutoField::Photo, ProfileAutoField::Counts],
            songs: Some(vec!["s2".into(), "s1".into()]),
        };
        assert_eq!(profile_sheet_from_json(&profile_sheet_to_json(&s)), s);
        assert_eq!(
            profile_sheet_to_json(&profile_sheet_default()),
            r#"{"size":"portrait","hidden":["qr"]}"#
        );
        // 選んでから全部外した (空) と、まだ選んでいない (キーなし) は別。
        let emptied = ProfileSheet {
            songs: Some(Vec::new()),
            ..profile_sheet_default()
        };
        assert_eq!(
            profile_sheet_to_json(&emptied),
            r#"{"size":"portrait","hidden":["qr"],"songIds":[]}"#
        );
        assert_eq!(
            profile_sheet_from_json(&profile_sheet_to_json(&emptied)),
            emptied
        );
    }

    #[test]
    fn chosen_songs_lead_the_motivation_and_drop_unfavorited_ones() {
        let mut rec = record();
        rec.favorite_songs.push(song("s3", "2026-03-01T00:00:00Z"));
        let text = |sheet: &ProfileSheet, rec: &ProfileSheetRecord| {
            profile_sheet_layout(sheet, rec).sections[0].entries[0]
                .text
                .clone()
        };
        // まだ選んでいなければお気に入りの新しい順。
        assert_eq!(
            text(&profile_sheet_default(), &rec),
            "「曲3」「曲2」「曲1」"
        );
        // 選んだ順。お気に入りから外した曲 (s9) は抜ける。
        let sheet = ProfileSheet {
            songs: Some(vec!["s1".into(), "s9".into(), "s3".into()]),
            ..profile_sheet_default()
        };
        assert_eq!(text(&sheet, &rec), "「曲1」「曲3」");
        rec.favorite_songs.retain(|s| s.id != "s1");
        assert_eq!(text(&sheet, &rec), "「曲3」");
        // 全部外せば志望の動機の欄は出さないが、選ぶ画面の行は残す (選び直せるように)。
        let none = ProfileSheet {
            songs: Some(Vec::new()),
            ..profile_sheet_default()
        };
        let layout = profile_sheet_layout(&none, &rec);
        assert!(layout
            .sections
            .iter()
            .all(|s| s.slot != ProfileSlot::Motivation));
        let row = profile_auto_field_rows(&none, &rec)
            .into_iter()
            .find(|r| r.field == ProfileAutoField::Songs)
            .unwrap();
        assert_eq!(row.value, "載せる曲を選んでいません");
    }

    #[test]
    fn old_json_with_career_style_brand_overrides_and_answers_still_reads() {
        assert_eq!(profile_sheet_from_json(""), profile_sheet_default());
        assert_eq!(profile_sheet_from_json("{"), profile_sheet_default());
        // 前の版: 職務経歴書の様式・丸の上書き・自分で書く欄・やめた欄 (担当の歌唱・年ごと・現場歴・ブランド)。
        let s = profile_sheet_from_json(
            r#"{"style":"career","size":"story","furigana":"ふがぴー",
                "answers":[{"q":"message","prompt":"","text":"よろしく"}],
                "hidden":["qr","qr","sparkles","oshi_heard","yearly","field_years","top_brand","peak_year","prefectures","songs"],
                "songs":["a","b"],"brandOn":["sm","sm"],"brandOff":[],"brandMain":"ml"}"#,
        );
        assert_eq!(s.size, ProfileSheetSize::Story);
        assert_eq!(
            s.hidden,
            vec![ProfileAutoField::Qr, ProfileAutoField::Songs]
        );
        // 前の版の `songs` (自分で書いた曲名) は選んだ曲として読まない。
        assert_eq!(s.songs, None);
        // 書き直すと前の版の項目は残らない。
        let json = profile_sheet_to_json(&s);
        for gone in ["answers", "furigana", "style", "brandOn", "brandMain"] {
            assert!(!json.contains(gone), "{gone}");
        }
    }

    #[test]
    fn history_and_licenses_come_from_records() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &record());
        assert_eq!(layout.title, "履歴書");
        assert_eq!(layout.imprint, "RÉSUMÉ");
        assert_eq!(layout.as_of, "2026年10月6日現在");
        assert_eq!(layout.name, "ふがP");
        assert_eq!(layout.since_label.as_deref(), Some("2014年 就任 · P歴12年"));
        let rows: Vec<(String, String, String)> = layout
            .history
            .iter()
            .map(|r| (r.year.clone(), r.month.clone(), r.text.clone()))
            .collect();
        // いちばん通った年の行はやめた。
        assert_eq!(
            rows,
            vec![
                ("2014".into(), "".into(), "プロデューサーに就任".into()),
                ("2015".into(), "7".into(), "はじめて参加　公演a".into()),
                ("2026".into(), "9".into(), "最近の現場　公演d".into()),
                ("".into(), "".into(), "以上".into()),
            ]
        );
        // 重複した参加は 1 回に数え、予定は数えない。現場歴・都道府県の行はやめた。
        let licenses: Vec<&str> = layout.licenses.iter().map(|r| r.text.as_str()).collect();
        assert_eq!(licenses, vec!["参加公演 4公演・回収曲 523曲 達成"]);
        assert_eq!(layout.brands_title, "担当ブランド");
        assert_eq!(layout.contacts, vec!["@fuga_p"]);
        assert!(!layout.show_qr);
        assert!(layout.show_photo);
    }

    #[test]
    fn slots_hold_songs_places_and_next_show() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &record());
        let got: Vec<(ProfileSlot, Vec<(&str, &str)>)> = layout
            .sections
            .iter()
            .map(|s| {
                (
                    s.slot,
                    s.entries
                        .iter()
                        .map(|e| (e.label.as_str(), e.text.as_str()))
                        .collect(),
                )
            })
            .collect();
        assert_eq!(
            got,
            vec![
                (
                    ProfileSlot::Motivation,
                    vec![("好きな曲", "「曲2」「曲1」")]
                ),
                (
                    ProfileSlot::Wish,
                    vec![("次の現場", "2026年11月3日　公演n（会場n）")]
                ),
            ]
        );
    }

    #[test]
    fn sparse_records_leave_no_empty_slots() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &sparse_record());
        // 参加 1 公演: はじめての参加だけ。
        assert_eq!(layout.history.len(), 2);
        assert_eq!(layout.licenses.len(), 1);
        assert_eq!(layout.licenses[0].text, "参加公演 1公演・回収曲 0曲 達成");
        assert!(layout.sections.is_empty());
        assert!(!layout.show_photo && !layout.show_oshi);
        assert!(layout.since_label.is_none());
        // 選ぶ画面にも記録の無い欄は並ばない。
        let keys: Vec<String> = profile_auto_field_rows(&profile_sheet_default(), &sparse_record())
            .into_iter()
            .map(|r| r.key)
            .collect();
        assert_eq!(keys, vec!["brands", "shows", "counts"]);
    }

    #[test]
    fn rows_mark_fields_that_come_from_the_producer_card() {
        let rows = profile_auto_field_rows(&profile_sheet_default(), &record());
        let from_card: Vec<&str> = rows
            .iter()
            .filter(|r| r.from_card)
            .map(|r| r.key.as_str())
            .collect();
        assert_eq!(from_card, vec!["since", "links", "qr"]);
        let links = rows.iter().find(|r| r.key == "links").unwrap();
        assert_eq!(links.value, "@fuga_p");
        assert!(!rows.iter().find(|r| r.key == "qr").unwrap().shown);
    }

    #[test]
    fn hidden_fields_drop_their_rows() {
        let mut sheet = profile_sheet_default();
        sheet.hidden = ALL_AUTO_FIELDS.to_vec();
        let layout = profile_sheet_layout(&sheet, &record());
        assert!(layout.history.is_empty(), "行が無ければ「以上」も出さない");
        assert!(layout.licenses.is_empty());
        assert!(layout.brands.is_empty());
        assert!(layout.contacts.is_empty());
        assert!(layout.since_label.is_none());
        assert!(layout.sections.is_empty());
        assert!(!layout.show_qr && !layout.show_photo);
        let shown = profile_toggle_field(&sheet, ProfileAutoField::Qr);
        assert!(profile_sheet_layout(&shown, &record()).show_qr);
        assert_eq!(profile_toggle_field(&shown, ProfileAutoField::Qr), sheet);
        // 外す順が違っても同じ選択になる (保存の形の並び)。
        let mut a = profile_sheet_default();
        a.hidden.clear();
        let a = profile_toggle_field(
            &profile_toggle_field(&a, ProfileAutoField::Qr),
            ProfileAutoField::Photo,
        );
        assert_eq!(
            a.hidden,
            vec![ProfileAutoField::Photo, ProfileAutoField::Qr]
        );
        assert_eq!(profile_sheet_from_json(&profile_sheet_to_json(&a)), a);
    }

    #[test]
    fn history_caps_rows_by_size() {
        let mut rec = record();
        rec.attended = vec![
            show("a", "2015-07-18", "765"),
            show("b", "2020-01-01", "765"),
            show("c", "2020-02-01", "765"),
            show("d", "2026-09-01", "765"),
        ];
        let layout = profile_sheet_layout(&profile_sheet_default(), &rec);
        // 就任・はじめて・最近の 3 行 + 以上。
        assert_eq!(layout.history.len(), 4);
        rec.since_year = Some(2030);
        let story = profile_sheet_layout(
            &ProfileSheet {
                size: ProfileSheetSize::Story,
                ..profile_sheet_default()
            },
            &rec,
        );
        assert_eq!(
            story.history.last().unwrap().kind,
            ProfileHistoryKind::Closing
        );
        assert_eq!(story.history.len(), 4);
    }

    #[test]
    fn density_relaxes_for_sparse_records_and_on_story() {
        let sparse = profile_sheet_layout(&profile_sheet_default(), &sparse_record());
        assert_eq!(sparse.density, ProfileSheetDensity::Regular);
        let mut rec = record();
        rec.favorite_songs = (0..5)
            .map(|i| ProfileSongInput {
                id: format!("f{i}"),
                title: "長いお気に入りの曲の名前".repeat(3),
                favorited_at: String::new(),
            })
            .collect();
        let dense = profile_sheet_layout(&profile_sheet_default(), &rec);
        assert_ne!(dense.density, ProfileSheetDensity::Regular);
        let story = ProfileSheet {
            size: ProfileSheetSize::Story,
            ..profile_sheet_default()
        };
        assert_eq!(
            profile_sheet_layout(&story, &rec).density,
            ProfileSheetDensity::Regular
        );
    }

    #[test]
    fn info_lists_have_unique_keys() {
        let mut keys: Vec<String> = profile_auto_fields().into_iter().map(|f| f.key).collect();
        let n = keys.len();
        keys.sort();
        keys.dedup();
        assert_eq!(keys.len(), n);
        assert_eq!(profile_sheet_sizes()[1].height_px, 1920);
        assert_eq!(
            profile_auto_field_info(ProfileAutoField::Brands).label,
            "担当ブランド"
        );
    }

    #[test]
    fn brand_marks_follow_the_app_setting_with_multiple_mains() {
        let mut rec = record();
        rec.brands.push(brand("other", "Other", 99));
        rec.brands.reverse();
        // 未設定: 担当 (765) のブランドがメイン、2 公演行った cg が担当。
        let marks = profile_brand_marks(&rec);
        let ids: Vec<(&str, bool, bool, usize)> = marks
            .iter()
            .map(|b| (b.id.as_str(), b.checked, b.main, b.rings.len()))
            .collect();
        assert_eq!(
            ids,
            vec![
                ("765", true, true, 2),
                ("cg", true, false, 1),
                ("ml", false, false, 0),
                ("sm", false, false, 0),
            ]
        );
        // 設定があればそれだけ (メインは複数)。
        rec.brand_roles_json = r#"{"main":["ml","sm"],"oshi":["765"]}"#.into();
        let marks = profile_brand_marks(&rec);
        let got: Vec<(&str, usize)> = marks
            .iter()
            .map(|b| (b.id.as_str(), b.rings.len()))
            .collect();
        assert_eq!(got, vec![("765", 1), ("cg", 0), ("ml", 2), ("sm", 2)]);
        // 外せば並べない。
        let mut sheet = profile_sheet_default();
        sheet.hidden.push(ProfileAutoField::Brands);
        assert!(profile_sheet_layout(&sheet, &rec).brands.is_empty());
    }

    #[test]
    fn brand_rings_are_stable_and_in_range() {
        let mut rec = record();
        rec.brand_roles_json = r#"{"main":["765","cg","ml","sm"]}"#.into();
        let a = profile_brand_marks(&rec);
        assert_eq!(a, profile_brand_marks(&rec));
        for m in &a {
            assert_eq!(m.rings.len(), 2);
            for (i, r) in m.rings.iter().enumerate() {
                assert!((-20.0..=20.0).contains(&r.tilt_degrees));
                assert!((0.92..=1.13).contains(&r.stretch));
                assert!((0.0..360.0).contains(&r.start_degrees));
                assert!((-0.04..=0.04).contains(&r.offset_x) && (-0.1..=0.1).contains(&r.offset_y));
                if i == 0 {
                    assert_eq!(r.scale, 1.0);
                } else {
                    assert!((1.22..=1.30).contains(&r.scale));
                    assert_ne!(r.tilt_degrees, m.rings[0].tilt_degrees);
                }
            }
        }
    }
}
