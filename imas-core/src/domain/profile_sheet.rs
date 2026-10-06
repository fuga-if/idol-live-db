//! プロフィール帳 (SNS に貼る自己紹介の 1 枚絵) の中身・欄の割り当て・行の組み立て。
//!
//! P名刺 (QR で交換する名刺) の続きで、P を「職業」に見立てた事務書類の様式で 1 枚にする。
//! **自分で書く欄は無い**。中身はすべてアプリの記録から埋まり、本人は様式・大きさ・載せる記録・
//! 担当ブランドの丸を選ぶだけ (開いたらすぐ書き出せる)。様式は 2 つ:
//!
//! - **履歴書** (既定): 氏名・押印・証明写真・P歴・担当・連絡先、担当ブランド、
//!   P歴 (学歴・職歴) の表 (就任 / はじめての参加 / 最近の現場 / 以上)、免許・資格 (記録の達成)、
//!   志望の動機 (現地でいちばん聴いた曲・担当の歌を聴いた回数)、趣味・特技 (お気に入りの曲・
//!   いちばん通ったブランドと会場)、本人希望記入欄 (次の現場)。
//! - **職務経歴書**: 職務要約 (記録から組んだ文)・職務経歴 (参加した公演を年ごとの表に)・担当・
//!   活かせる経験・知識・スキル・自己PR (実績の数字と年ごとの参加数)。
//!
//! どの記録がどの欄に入るか・欄の並び・行の組み立て・上限・文字の詰め方 (`ProfileSheetDensity`)・
//! 担当ブランドの丸 (メインは二重丸) はここで決め、端末 (iOS / Android) はこの結果を描くだけにする。
//! 参加した公演のセトリからの集計 (いちばん聴いた曲・担当の歌唱・会場・都道府県) は
//! [`profile_live_record`] (スナップショットを読む)。
//!
//! 保存するのは選択だけ (自分の P名刺の行に JSON で持つ。`profile_sheet_to_json`)。
//! 名前・写真・書体・リンク・自分の QR は P名刺のものを使う。

use crate::domain::snapshot::Snapshot;
use chrono::{Datelike, NaiveDate};
use std::collections::{HashMap, HashSet};

// ---------------------------------------------------------------------------
// 型
// ---------------------------------------------------------------------------

/// 様式。並び順は編集画面の選択肢の順。保存のキーは変えない。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum ProfileSheetStyle {
    /// 履歴書 (既定)。
    #[default]
    Resume,
    /// 職務経歴書。
    Career,
}

/// 書き出す画像の大きさ。
#[derive(uniffi::Enum, Clone, Copy, Debug, Default, PartialEq, Eq, Hash)]
pub enum ProfileSheetSize {
    /// 4:5 (1080×1350px)。X のタイムラインで大きく出る。
    #[default]
    Portrait,
    /// 9:16 (1080×1920px)。ストーリーズ向け。
    Story,
}

/// アプリの記録から自動で埋まる欄 (外せる)。保存のキーは変えない。並びは編集画面の順。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileAutoField {
    /// P名刺の写真 (証明写真の欄)。
    Photo,
    /// 担当 (押印欄の判子と担当の行)。
    Oshi,
    /// 担当ブランド (ブランドの名前に丸)。
    Brands,
    /// P歴 (就任の年)。
    Since,
    /// はじめて参加したライブ・最近の現場 (履歴書) / 職務経歴の表 (職務経歴書)。
    Shows,
    /// 次の現場。
    NextShow,
    /// 参加公演数・回収曲数。
    Counts,
    /// 現地でいちばん聴いた曲 (参加した公演のセトリから)。
    TopSongs,
    /// 担当の歌を現地で聴いた回数。
    OshiHeard,
    /// お気に入りの曲。
    Songs,
    /// いちばん通ったブランド。
    TopBrand,
    /// いちばん通った会場。
    TopVenue,
    /// 現地に行った都道府県の数。
    Prefectures,
    /// 年ごとの参加数 (職務経歴書だけ)。
    Yearly,
    /// 現場歴 (はじめての参加からの年数)。
    FieldYears,
    /// リンク (連絡先)。
    Links,
    /// 自分の QR (既定は載せない)。
    Qr,
}

/// 欄。様式ごとに使う欄が決まっている。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileSlot {
    /// 履歴書: 志望の動機。
    Motivation,
    /// 履歴書: 趣味・特技。
    Hobby,
    /// 履歴書: 本人希望記入欄。
    Wish,
    /// 職務経歴書: 職務要約 (職務経歴の表の前)。
    Summary,
    /// 職務経歴書: 活かせる経験・知識・スキル。
    Skills,
    /// 職務経歴書: 自己PR。
    SelfPr,
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

/// プロフィール帳の選択 (端末に保存するもの)。中身は毎回アプリの記録から組む。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheet {
    pub style: ProfileSheetStyle,
    pub size: ProfileSheetSize,
    /// 外した自動の欄。
    pub hidden: Vec<ProfileAutoField>,
    /// 担当ブランドで自分で丸を付けたブランド (記録からは付かないもの)。
    pub brand_on: Vec<String>,
    /// 担当ブランドで自分で丸を外したブランド (記録からは付くもの)。
    pub brand_off: Vec<String>,
    /// メインのブランド (二重丸) の上書き。None は既定 (`profile_brand_marks` の決まり)、
    /// 空文字はメインなし。
    pub brand_main: Option<String>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAutoFieldInfo {
    pub field: ProfileAutoField,
    pub key: String,
    /// 編集画面の名前 (「参加公演数・回収曲数」)。
    pub label: String,
}

/// 編集画面の「載せる記録」の 1 行。記録の無い欄・その様式で使わない欄は並べない。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAutoFieldRow {
    pub field: ProfileAutoField,
    pub key: String,
    pub label: String,
    /// 今の記録で載る中身の短い見本 (「19公演・323曲」)。写真・QR は空。
    pub value: String,
    /// 載せているか。
    pub shown: bool,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheetStyleInfo {
    pub style: ProfileSheetStyle,
    pub key: String,
    /// 「履歴書」。
    pub label: String,
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

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSongInput {
    pub id: String,
    pub title: String,
}

/// 数えたもの 1 つ (曲・担当・会場と回数)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileCount {
    pub id: String,
    pub label: String,
    pub count: u32,
}

/// 参加した公演のセトリ・会場から数えた記録 ([`profile_live_record`])。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq, Default)]
pub struct ProfileLiveRecord {
    /// 現地でいちばん聴いた曲 (2 回以上聴いた曲の上位、多い順)。
    pub top_songs: Vec<ProfileCount>,
    /// 担当の歌を現地で聴いた回数 (担当の順、0 回の担当は入れない)。
    pub oshi_heard: Vec<ProfileCount>,
    /// いちばん通った会場 (2 回以上)。
    pub top_venue: Option<ProfileCount>,
    /// 現地に行った都道府県の数 (会場の所在地が分かる公演だけ)。
    pub prefecture_count: u32,
}

/// プロフィール帳の材料。名前・P歴・リンク・写真・QR は P名刺から、ほかはアプリの記録から。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheetRecord {
    /// 今日 (`YYYY-MM-DD`、JST)。
    pub today: String,
    pub name: String,
    pub since_year: Option<u16>,
    /// 担当の名前 (担当の順)。
    pub oshi_names: Vec<String>,
    /// 担当の所属ブランド (担当の順。丸と、メインの既定に使う)。
    pub oshi_brand_ids: Vec<String>,
    pub attended: Vec<ProfileShowInput>,
    pub song_count: u32,
    pub brands: Vec<ProfileBrandInput>,
    /// お気に入りの曲 (端末の並びのまま。先頭から [`MAX_SONGS`] 曲を載せる)。
    pub favorite_songs: Vec<ProfileSongInput>,
    /// 連絡先に出すリンク (`card_link_view` の display)。
    pub links: Vec<String>,
    /// P名刺に写真があるか。
    pub has_photo: bool,
    /// P名刺に自分の QR があるか。
    pub has_qr: bool,
    /// セトリ・会場から数えた記録。
    pub live: ProfileLiveRecord,
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

/// 年・月・内容の 1 行 (履歴書の P歴と免許・資格の表)。
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
/// (メインは 2 本の二重丸)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileBrandCheck {
    pub id: String,
    pub label: String,
    pub color: Option<String>,
    /// 丸を付けるか。
    pub checked: bool,
    /// メイン (二重丸) か。
    pub main: bool,
    /// 記録 (担当・参加した公演) から付く丸か。編集画面で添える。
    pub from_record: bool,
    /// 描く楕円 (丸なしは 0 本・丸は 1 本・メインは 2 本)。
    pub rings: Vec<ProfileHandRing>,
}

/// 職務経歴の表の 1 行 (公演 1 つ)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileCareerRow {
    /// 「9/14」。
    pub date: String,
    pub title: String,
    pub venue: Option<String>,
    /// ブランドの短い名前。
    pub brand: Option<String>,
    /// 参加予定 (次の現場)。
    pub planned: bool,
}

/// 職務経歴の表の 1 年。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileCareerYear {
    /// 「2026年」。
    pub year: String,
    /// 「12公演」(その年に行った公演の数。表に出し切れない分も数える)。
    pub count_label: String,
    pub rows: Vec<ProfileCareerRow>,
}

/// 欄の中の 1 項目 (見出しと中身)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileEntry {
    pub field: ProfileAutoField,
    /// 「現地でいちばん聴いた曲」。空なら見出しなし。
    pub label: String,
    pub text: String,
}

/// 実績の数字 1 つ (職務経歴書の自己PR)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileStat {
    pub field: ProfileAutoField,
    /// 「参加公演」。
    pub label: String,
    /// 「19」。
    pub value: String,
    /// 「公演」。
    pub unit: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSection {
    pub slot: ProfileSlot,
    /// 「志望の動機」。
    pub title: String,
    /// 英字の印字 (「MOTIVATION」)。
    pub imprint: String,
    /// 実績の数字 (項目の前に 1 列で並べる)。
    pub stats: Vec<ProfileStat>,
    pub entries: Vec<ProfileEntry>,
}

/// 描く形。欄は様式の並び順で、中身の無い欄は入れない。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileSheetLayout {
    pub style: ProfileSheetStyle,
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
    /// 履歴書の P歴の表 (職務経歴書は空)。最後の行は「以上」。
    pub history: Vec<ProfileHistoryRow>,
    /// 履歴書の免許・資格 (職務経歴書は空)。
    pub licenses: Vec<ProfileHistoryRow>,
    /// 職務経歴書の職務経歴 (新しい年から。履歴書は空)。
    pub career: Vec<ProfileCareerYear>,
    /// 職務経歴の表に出し切れなかった公演の数 (「ほか 30 公演」)。
    pub career_more: u32,
    pub sections: Vec<ProfileSection>,
    pub density: ProfileSheetDensity,
}

// ---------------------------------------------------------------------------
// 決まり
// ---------------------------------------------------------------------------

/// お気に入りの曲を載せる数。
pub const MAX_SONGS: usize = 3;
/// 現地でいちばん聴いた曲を載せる数。
const MAX_TOP_SONGS: usize = 3;
/// 年ごとの参加数を載せる年の数 (新しい年から)。
const MAX_YEARS: usize = 5;
/// 「いちばん」と言える回数の下限 (1 回ずつなら順位に意味が無い)。
const MIN_TOP_COUNT: u32 = 2;
/// 都道府県の数を載せる下限 (1 つだけなら「遠征」にならない)。
const MIN_PREFECTURES: u32 = 2;

const BRANDS_TITLE: &str = "担当ブランド";

const ALL_AUTO_FIELDS: [ProfileAutoField; 17] = [
    ProfileAutoField::Photo,
    ProfileAutoField::Oshi,
    ProfileAutoField::Brands,
    ProfileAutoField::Since,
    ProfileAutoField::Shows,
    ProfileAutoField::NextShow,
    ProfileAutoField::Counts,
    ProfileAutoField::TopSongs,
    ProfileAutoField::OshiHeard,
    ProfileAutoField::Songs,
    ProfileAutoField::TopBrand,
    ProfileAutoField::TopVenue,
    ProfileAutoField::Prefectures,
    ProfileAutoField::Yearly,
    ProfileAutoField::FieldYears,
    ProfileAutoField::Links,
    ProfileAutoField::Qr,
];

const ALL_STYLES: [ProfileSheetStyle; 2] = [ProfileSheetStyle::Resume, ProfileSheetStyle::Career];
const ALL_SIZES: [ProfileSheetSize; 2] = [ProfileSheetSize::Portrait, ProfileSheetSize::Story];

pub fn profile_auto_field_info(field: ProfileAutoField) -> ProfileAutoFieldInfo {
    use ProfileAutoField as F;
    let (key, label) = match field {
        F::Photo => ("photo", "写真"),
        F::Oshi => ("oshi", "担当"),
        F::Brands => ("brands", "担当ブランド"),
        F::Since => ("since", "P歴"),
        F::Shows => ("shows", "参加の経歴"),
        F::NextShow => ("next_show", "次の現場"),
        F::Counts => ("counts", "参加公演数・回収曲数"),
        F::TopSongs => ("top_songs", "現地でいちばん聴いた曲"),
        F::OshiHeard => ("oshi_heard", "担当の歌を現地で聴いた回数"),
        F::Songs => ("songs", "お気に入りの曲"),
        F::TopBrand => ("top_brand", "いちばん通ったブランド"),
        F::TopVenue => ("top_venue", "いちばん通った会場"),
        F::Prefectures => ("prefectures", "現地に行った都道府県"),
        F::Yearly => ("yearly", "年ごとの参加数"),
        F::FieldYears => ("field_years", "現場歴"),
        F::Links => ("links", "リンク"),
        F::Qr => ("qr", "自分の QR"),
    };
    ProfileAutoFieldInfo {
        field,
        key: key.into(),
        label: label.into(),
    }
}

/// 自動の欄の一覧 (編集画面の順)。
pub fn profile_auto_fields() -> Vec<ProfileAutoFieldInfo> {
    ALL_AUTO_FIELDS
        .into_iter()
        .map(profile_auto_field_info)
        .collect()
}

/// その様式で使う欄か (年ごとの参加数は職務経歴書だけ)。
fn applies(style: ProfileSheetStyle, field: ProfileAutoField) -> bool {
    !(style == ProfileSheetStyle::Resume && field == ProfileAutoField::Yearly)
}

pub fn profile_sheet_style_info(style: ProfileSheetStyle) -> ProfileSheetStyleInfo {
    let (key, label) = match style {
        ProfileSheetStyle::Resume => ("resume", "履歴書"),
        ProfileSheetStyle::Career => ("career", "職務経歴書"),
    };
    ProfileSheetStyleInfo {
        style,
        key: key.into(),
        label: label.into(),
    }
}

pub fn profile_sheet_styles() -> Vec<ProfileSheetStyleInfo> {
    ALL_STYLES
        .into_iter()
        .map(profile_sheet_style_info)
        .collect()
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

/// はじめて開いたときの選択。履歴書・4:5、自分の QR だけ外しておく (載せるかは本人が決める)。
pub fn profile_sheet_default() -> ProfileSheet {
    ProfileSheet {
        style: ProfileSheetStyle::default(),
        size: ProfileSheetSize::default(),
        hidden: vec![ProfileAutoField::Qr],
        brand_on: Vec::new(),
        brand_off: Vec::new(),
        brand_main: None,
    }
}

fn slots(style: ProfileSheetStyle) -> [ProfileSlot; 3] {
    match style {
        ProfileSheetStyle::Resume => [
            ProfileSlot::Motivation,
            ProfileSlot::Hobby,
            ProfileSlot::Wish,
        ],
        ProfileSheetStyle::Career => [
            ProfileSlot::Summary,
            ProfileSlot::Skills,
            ProfileSlot::SelfPr,
        ],
    }
}

fn slot_title(slot: ProfileSlot) -> (&'static str, &'static str) {
    match slot {
        ProfileSlot::Motivation => ("志望の動機", "MOTIVATION"),
        ProfileSlot::Hobby => ("趣味・特技", "HOBBIES"),
        ProfileSlot::Wish => ("本人希望記入欄", "REQUESTS"),
        ProfileSlot::Summary => ("職務要約", "SUMMARY"),
        ProfileSlot::Skills => ("活かせる経験・知識・スキル", "SKILLS"),
        ProfileSlot::SelfPr => ("自己PR", "SELF-PR"),
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

/// 保存の形。前の版が書いた `furigana` / `answers` / `songs` (自分で書く欄) は読み捨てる
/// (serde は知らないキーを無視する)。
#[derive(serde::Serialize, serde::Deserialize, Default)]
#[serde(default)]
struct SheetDto {
    style: String,
    size: String,
    hidden: Vec<String>,
    #[serde(rename = "brandOn")]
    brand_on: Vec<String>,
    #[serde(rename = "brandOff")]
    brand_off: Vec<String>,
    #[serde(rename = "brandMain", skip_serializing_if = "Option::is_none")]
    brand_main: Option<String>,
}

/// 保存の形 (キーは英字)。
pub fn profile_sheet_to_json(sheet: &ProfileSheet) -> String {
    let dto = SheetDto {
        style: profile_sheet_style_info(sheet.style).key,
        size: profile_sheet_size_info(sheet.size).key,
        hidden: ALL_AUTO_FIELDS
            .into_iter()
            .filter(|f| sheet.hidden.contains(f))
            .map(|f| profile_auto_field_info(f).key)
            .collect(),
        brand_on: sheet.brand_on.clone(),
        brand_off: sheet.brand_off.clone(),
        brand_main: sheet.brand_main.clone(),
    };
    serde_json::to_string(&dto).unwrap_or_default()
}

/// 保存の形から戻す。空・壊れた JSON は既定の選択。知らない欄のキー (新しい版が足したもの) と
/// 前の版の自分で書く欄は捨てる (読めない 1 項目のために全部を失わない)。
pub fn profile_sheet_from_json(json: &str) -> ProfileSheet {
    let Ok(dto) = serde_json::from_str::<SheetDto>(json) else {
        return profile_sheet_default();
    };
    let style = ALL_STYLES
        .into_iter()
        .find(|s| profile_sheet_style_info(*s).key == dto.style)
        .unwrap_or_default();
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
        style,
        size,
        hidden,
        brand_on: unique_ids(dto.brand_on),
        brand_off: unique_ids(dto.brand_off),
        brand_main: dto.brand_main,
    }
}

// ---------------------------------------------------------------------------
// 参加した公演のセトリ・会場から数える
// ---------------------------------------------------------------------------

/// 参加した公演 (`attended_show_ids`。予定も混ざってよい) のうち今日までに行ったものの、
/// セトリと会場から数える。
///
/// - 曲・担当の歌唱は「披露に数える公演」(`Show::counts_as_performance`。上映会・配信だけは除く) だけ。
/// - 担当の歌唱はその担当が歌唱メンバーに入っている披露の数。
/// - 会場は会場マスタ (`venue_id`) で数え、無ければ公演の会場の表記で数える。都道府県は会場マスタから。
/// - 同数は「先に聴いた・行った方」が上 (決定的にするため)。
pub fn profile_live_record(
    snap: &Snapshot,
    attended_show_ids: &[String],
    oshi_idol_ids: &[String],
    today: &str,
) -> ProfileLiveRecord {
    let today = parse_date(today);
    let mut shows: Vec<u32> = Vec::new();
    let mut seen = HashSet::new();
    for id in attended_show_ids {
        let Some(&show) = snap.show_index_by_id.get(id) else {
            continue;
        };
        let past = matches!(
            (parse_date(&snap.shows[show as usize].date), today),
            (Some(d), Some(t)) if d <= t
        );
        if past && seen.insert(show) {
            shows.push(show);
        }
    }
    // 古い公演から (同数のときに先に聴いた方を上にする)。
    shows.sort_by(|a, b| {
        let (sa, sb) = (&snap.shows[*a as usize], &snap.shows[*b as usize]);
        sa.date
            .cmp(&sb.date)
            .then(sa.sort_order.cmp(&sb.sort_order))
            .then(sa.id.cmp(&sb.id))
    });

    let oshi: Vec<u32> = oshi_idol_ids
        .iter()
        .filter_map(|id| snap.idol_index_by_id.get(id).copied())
        .collect();
    let mut song_counts: HashMap<u32, (u32, usize)> = HashMap::new();
    let mut oshi_counts = vec![0u32; oshi.len()];
    let mut venue_counts: HashMap<String, (u32, usize, String)> = HashMap::new();
    let mut prefectures: HashSet<&str> = HashSet::new();
    let mut order = 0usize;
    for &show in &shows {
        let s = &snap.shows[show as usize];
        let venue = s
            .venue_id
            .as_ref()
            .and_then(|id| snap.venue_index_by_id.get(id))
            .map(|&v| &snap.venues[v as usize]);
        if let Some(p) = venue.and_then(|v| v.prefecture.as_deref()) {
            if !p.trim().is_empty() {
                prefectures.insert(p);
            }
        }
        let venue_key = venue
            .map(|v| (format!("v:{}", v.id), v.name.clone()))
            .or_else(|| {
                s.venue
                    .as_deref()
                    .map(str::trim)
                    .filter(|l| !l.is_empty())
                    .map(|l| (format!("l:{l}"), l.to_string()))
            });
        if let Some((key, label)) = venue_key {
            let e = venue_counts.entry(key).or_insert((0, order, label));
            e.0 += 1;
        }
        if s.counts_as_performance() {
            for &item in &snap.setlist_items_by_show[show as usize] {
                let song = snap.setlist_items[item as usize].song;
                let e = song_counts.entry(song).or_insert((0, order));
                e.0 += 1;
                let performers = &snap.performers_by_item[item as usize];
                for (i, idol) in oshi.iter().enumerate() {
                    if performers.contains(idol) {
                        oshi_counts[i] += 1;
                    }
                }
                order += 1;
            }
        }
        order += 1;
    }

    let mut top: Vec<(u32, u32, usize)> = song_counts
        .into_iter()
        .filter(|(_, (n, _))| *n >= MIN_TOP_COUNT)
        .map(|(song, (n, first))| (song, n, first))
        .collect();
    top.sort_by(|a, b| b.1.cmp(&a.1).then(a.2.cmp(&b.2)));
    let top_songs = top
        .into_iter()
        .take(MAX_TOP_SONGS)
        .map(|(song, n, _)| {
            let s = &snap.songs[song as usize];
            ProfileCount {
                id: s.id.clone(),
                label: s.title.clone(),
                count: n,
            }
        })
        .collect();

    let oshi_heard = oshi
        .iter()
        .zip(oshi_counts)
        .filter(|(_, n)| *n > 0)
        .map(|(&idol, n)| {
            let i = &snap.idols[idol as usize];
            ProfileCount {
                id: i.id.clone(),
                label: i.name.clone(),
                count: n,
            }
        })
        .collect();

    let top_venue = venue_counts
        .into_iter()
        .filter(|(_, (n, _, _))| *n >= MIN_TOP_COUNT)
        .min_by(|a, b| b.1 .0.cmp(&a.1 .0).then(a.1 .1.cmp(&b.1 .1)))
        .map(|(key, (n, _, label))| ProfileCount {
            id: key,
            label,
            count: n,
        });

    ProfileLiveRecord {
        top_songs,
        oshi_heard,
        top_venue,
        prefecture_count: prefectures.len() as u32,
    }
}

// ---------------------------------------------------------------------------
// 組み立て
// ---------------------------------------------------------------------------

/// 大きさごとの表の行数の上限 (履歴書の P歴は「以上」を除く、職務経歴書は公演の行)。
fn row_caps(size: ProfileSheetSize) -> (usize, usize) {
    match size {
        ProfileSheetSize::Portrait => (4, 4),
        ProfileSheetSize::Story => (5, 8),
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

/// 記録を数えた中間の形 (組み立てと編集画面の見本で共有する)。
struct Facts<'a> {
    today: Option<NaiveDate>,
    /// 行った公演 (日付の昇順、重複なし)。
    past: Vec<(NaiveDate, &'a ProfileShowInput)>,
    /// 次の現場 (いちばん近い予定)。
    next: Option<(NaiveDate, &'a ProfileShowInput)>,
    /// いちばん通ったブランド (短い名前と公演数)。
    top_brand: Option<(String, u32)>,
    /// 年ごとの参加数 (新しい年から)。
    yearly: Vec<(i32, u32)>,
    /// はじめての参加からの年数 (1 年未満は None)。
    field_years: Option<i32>,
    record: &'a ProfileSheetRecord,
}

impl<'a> Facts<'a> {
    fn new(record: &'a ProfileSheetRecord) -> Self {
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

        let listed = listed_brands(record);
        let mut brand_counts: HashMap<&str, u32> = HashMap::new();
        for (_, s) in &past {
            if let Some(b) = s.brand_id.as_deref() {
                if listed.iter().any(|l| l.id == b) {
                    *brand_counts.entry(b).or_default() += 1;
                }
            }
        }
        // 同数はブランドの並び順で先の方。
        let top_brand = listed
            .iter()
            .filter_map(|b| brand_counts.get(b.id.as_str()).map(|n| (b, *n)))
            .fold(
                None::<(&ProfileBrandInput, u32)>,
                |best, (b, n)| match best {
                    Some((_, m)) if m >= n => best,
                    _ => Some((b, n)),
                },
            )
            .map(|(b, n)| (b.label.clone(), n));

        let mut years: Vec<(i32, u32)> = Vec::new();
        for (d, _) in past.iter().rev() {
            match years.last_mut() {
                Some((y, n)) if *y == d.year() => *n += 1,
                _ => years.push((d.year(), 1)),
            }
        }

        let field_years = match (past.first(), today) {
            (Some((first, _)), Some(t)) => {
                let mut n = t.year() - first.year();
                if (t.month(), t.day()) < (first.month(), first.day()) {
                    n -= 1;
                }
                (n >= 1).then_some(n)
            }
            _ => None,
        };

        Facts {
            today,
            past,
            next,
            top_brand,
            yearly: years,
            field_years,
            record,
        }
    }

    fn favorite_titles(&self) -> Option<String> {
        let titles: Vec<String> = self
            .record
            .favorite_songs
            .iter()
            .take(MAX_SONGS)
            .map(|s| format!("「{}」", s.title))
            .collect();
        (!titles.is_empty()).then(|| titles.join(""))
    }

    fn top_song_text(&self) -> Option<String> {
        let parts: Vec<String> = self
            .record
            .live
            .top_songs
            .iter()
            .take(MAX_TOP_SONGS)
            .map(|c| format!("「{}」{}回", c.label, c.count))
            .collect();
        (!parts.is_empty()).then(|| parts.join("　"))
    }

    fn oshi_heard_text(&self) -> Option<String> {
        let parts: Vec<String> = self
            .record
            .live
            .oshi_heard
            .iter()
            .map(|c| format!("{} {}回", c.label, c.count))
            .collect();
        (!parts.is_empty()).then(|| parts.join("　"))
    }

    fn oshi_heard_total(&self) -> u32 {
        self.record.live.oshi_heard.iter().map(|c| c.count).sum()
    }

    fn prefectures(&self) -> Option<u32> {
        let n = self.record.live.prefecture_count;
        (n >= MIN_PREFECTURES).then_some(n)
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

    fn yearly_text(&self) -> Option<String> {
        let parts: Vec<String> = self
            .yearly
            .iter()
            .take(MAX_YEARS)
            .map(|(y, n)| format!("{y}年 {n}公演"))
            .collect();
        (!parts.is_empty()).then(|| parts.join("　"))
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

    /// その欄に載せる記録があるか (無い欄は出さない・編集画面に並べない)。
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
            F::TopSongs => !r.live.top_songs.is_empty(),
            F::OshiHeard => !r.live.oshi_heard.is_empty(),
            F::Songs => !r.favorite_songs.is_empty(),
            F::TopBrand => self.top_brand.is_some(),
            F::TopVenue => r.live.top_venue.is_some(),
            F::Prefectures => self.prefectures().is_some(),
            F::Yearly => !self.yearly.is_empty(),
            F::FieldYears => self.field_years.is_some(),
            F::Links => !r.links.is_empty(),
            F::Qr => r.has_qr,
        }
    }

    /// 編集画面に添える短い見本。
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
            F::TopSongs => r
                .live
                .top_songs
                .first()
                .map(|c| format!("「{}」{}回", c.label, c.count))
                .unwrap_or_default(),
            F::OshiHeard => format!("{}回", self.oshi_heard_total()),
            F::Songs => r
                .favorite_songs
                .first()
                .map(|s| format!("「{}」", s.title))
                .unwrap_or_default(),
            F::TopBrand => self
                .top_brand
                .as_ref()
                .map(|(b, n)| format!("{b} {n}公演"))
                .unwrap_or_default(),
            F::TopVenue => r
                .live
                .top_venue
                .as_ref()
                .map(|c| format!("{} {}回", c.label, c.count))
                .unwrap_or_default(),
            F::Prefectures => self
                .prefectures()
                .map(|n| format!("{n}都道府県"))
                .unwrap_or_default(),
            F::Yearly => self
                .yearly
                .first()
                .map(|(y, n)| format!("{y}年 {n}公演"))
                .unwrap_or_default(),
            F::FieldYears => self
                .field_years
                .map(|n| format!("{n}年"))
                .unwrap_or_default(),
            F::Links => r.links.join("　"),
        }
    }
}

/// 編集画面の「載せる記録」の行。その様式で使い、記録のある欄だけを編集画面の順に。
pub fn profile_auto_field_rows(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> Vec<ProfileAutoFieldRow> {
    let facts = Facts::new(record);
    ALL_AUTO_FIELDS
        .into_iter()
        .filter(|f| applies(sheet.style, *f) && facts.has(*f))
        .map(|f| {
            let info = profile_auto_field_info(f);
            ProfileAutoFieldRow {
                field: f,
                key: info.key,
                label: info.label,
                value: facts.preview(f),
                shown: !sheet.hidden.contains(&f),
            }
        })
        .collect()
}

/// 載せる欄を 1 つ付け外しした選択。外した欄は編集画面の順に並べ直す (保存の形と同じ並びにして、
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
    let facts = Facts::new(record);
    let style = sheet.style;
    // 載せる欄: 外しておらず、その様式で使い、記録がある。
    let on = |f: ProfileAutoField| !sheet.hidden.contains(&f) && applies(style, f) && facts.has(f);
    let today = facts.today;
    let past = &facts.past;
    let next = facts.next.filter(|_| on(ProfileAutoField::NextShow));

    let since_label = record
        .since_year
        .filter(|_| on(ProfileAutoField::Since))
        .map(|y| match today.map(|t| t.year() - i32::from(y)) {
            Some(n) if n >= 1 => format!("{y}年 就任 · P歴{n}年"),
            _ => format!("{y}年 就任"),
        });

    let brand_label = |id: &Option<String>| -> Option<String> {
        let id = id.as_deref()?;
        record
            .brands
            .iter()
            .find(|b| b.id == id)
            .map(|b| b.label.clone())
    };

    let brands = if on(ProfileAutoField::Brands) {
        profile_brand_marks(sheet, record)
    } else {
        Vec::new()
    };

    let (history_cap, career_cap) = row_caps(sheet.size);
    let mut history = Vec::new();
    let mut licenses = Vec::new();
    let mut career = Vec::new();
    let mut career_more = 0u32;

    match style {
        ProfileSheetStyle::Resume => {
            if let Some(y) = record.since_year.filter(|_| on(ProfileAutoField::Since)) {
                history.push(ProfileHistoryRow {
                    year: y.to_string(),
                    month: String::new(),
                    text: "プロデューサーに就任".into(),
                    kind: ProfileHistoryKind::Since,
                });
            }
            if on(ProfileAutoField::Shows) {
                if let Some((d, s)) = past.first() {
                    history.push(history_row(
                        *d,
                        format!("はじめて参加　{}", s.title),
                        ProfileHistoryKind::FirstShow,
                    ));
                }
                if past.len() >= 2 {
                    let (d, s) = past[past.len() - 1];
                    history.push(history_row(
                        d,
                        format!("最近の現場　{}", s.title),
                        ProfileHistoryKind::RecentShow,
                    ));
                }
            }
            history.truncate(history_cap);
            if !history.is_empty() {
                history.push(ProfileHistoryRow {
                    year: String::new(),
                    month: String::new(),
                    text: "以上".into(),
                    kind: ProfileHistoryKind::Closing,
                });
            }
            // 免許・資格: 記録の達成 (今日の日付で)。
            if let Some(t) = today {
                if on(ProfileAutoField::Counts) {
                    licenses.push(history_row(
                        t,
                        format!("{} 達成", facts.counts_text()),
                        ProfileHistoryKind::Count,
                    ));
                }
                if let Some(n) = facts
                    .prefectures()
                    .filter(|_| on(ProfileAutoField::Prefectures))
                {
                    licenses.push(history_row(
                        t,
                        format!("現地 {n}都道府県 踏破"),
                        ProfileHistoryKind::Count,
                    ));
                }
                if let Some(n) = facts
                    .field_years
                    .filter(|_| on(ProfileAutoField::FieldYears))
                {
                    licenses.push(history_row(
                        t,
                        format!("現場歴 {n}年 到達"),
                        ProfileHistoryKind::Count,
                    ));
                }
            }
        }
        ProfileSheetStyle::Career => {
            let show_past = on(ProfileAutoField::Shows);
            if show_past || next.is_some() {
                // 新しい公演から。次の現場はその年の頭に「予定」で置く。
                let mut rows: Vec<(NaiveDate, ProfileCareerRow)> = Vec::new();
                if let Some((d, s)) = next {
                    rows.push((d, career_row(d, s, brand_label(&s.brand_id), true)));
                }
                let past_rows: Vec<&(NaiveDate, &ProfileShowInput)> = if show_past {
                    past.iter().rev().collect()
                } else {
                    Vec::new()
                };
                let room = career_cap.saturating_sub(rows.len());
                for (d, s) in past_rows.iter().take(room) {
                    rows.push((*d, career_row(*d, s, brand_label(&s.brand_id), false)));
                }
                career_more = past_rows.len().saturating_sub(room) as u32;
                for (d, row) in rows {
                    let year = format!("{}年", d.year());
                    if career
                        .last()
                        .is_none_or(|y: &ProfileCareerYear| y.year != year)
                    {
                        let count = past.iter().filter(|(pd, _)| pd.year() == d.year()).count();
                        career.push(ProfileCareerYear {
                            year,
                            // 予定しかない年は数を出さない (「0公演」にしない)。
                            count_label: if count == 0 {
                                String::new()
                            } else {
                                format!("{count}公演")
                            },
                            rows: Vec::new(),
                        });
                    }
                    if let Some(y) = career.last_mut() {
                        y.rows.push(row);
                    }
                }
            }
        }
    }

    // 欄: 記録を様式の欄に割り当てる。中身の無い欄は出さない。
    let mut sections: Vec<ProfileSection> = Vec::new();
    for slot in slots(style) {
        let mut entries: Vec<ProfileEntry> = Vec::new();
        let mut stats: Vec<ProfileStat> = Vec::new();
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
                push(F::TopSongs, "現地でいちばん聴いた曲", facts.top_song_text());
                push(
                    F::OshiHeard,
                    "担当の歌を現地で聴いた回数",
                    facts.oshi_heard_text(),
                );
            }
            ProfileSlot::Hobby => {
                push(F::Songs, "お気に入りの曲", facts.favorite_titles());
                push(
                    F::TopBrand,
                    "いちばん通ったブランド",
                    facts
                        .top_brand
                        .as_ref()
                        .map(|(b, n)| format!("{b} {n}公演")),
                );
                push(
                    F::TopVenue,
                    "いちばん通った会場",
                    record
                        .live
                        .top_venue
                        .as_ref()
                        .map(|c| format!("{} {}回", c.label, c.count)),
                );
            }
            ProfileSlot::Wish => {
                push(F::NextShow, "次の現場", facts.next_text());
            }
            ProfileSlot::Summary => {
                if let Some(text) = career_summary(&facts, &on) {
                    entries.push(ProfileEntry {
                        field: F::Counts,
                        label: String::new(),
                        text,
                    });
                }
            }
            ProfileSlot::Skills => {
                push(F::TopSongs, "現地でいちばん聴いた曲", facts.top_song_text());
                push(F::Songs, "お気に入りの曲", facts.favorite_titles());
                push(
                    F::TopVenue,
                    "いちばん通った会場",
                    record
                        .live
                        .top_venue
                        .as_ref()
                        .map(|c| format!("{} {}回", c.label, c.count)),
                );
            }
            ProfileSlot::SelfPr => {
                push(F::Yearly, "年ごとの参加", facts.yearly_text());
                let mut stat = |field: F, label: &str, value: u32, unit: &str| {
                    if on(field) {
                        stats.push(ProfileStat {
                            field,
                            label: label.into(),
                            value: value.to_string(),
                            unit: unit.into(),
                        });
                    }
                };
                stat(F::Counts, "参加公演", facts.past.len() as u32, "公演");
                stat(F::Counts, "回収曲", record.song_count, "曲");
                if let Some(n) = facts.prefectures() {
                    stat(F::Prefectures, "現地", n, "都道府県");
                }
                stat(F::OshiHeard, "担当の歌唱", facts.oshi_heard_total(), "回");
                if let Some(n) = facts.field_years {
                    stat(F::FieldYears, "現場歴", n as u32, "年");
                }
            }
        }
        if !entries.is_empty() || !stats.is_empty() {
            let (title, imprint) = slot_title(slot);
            sections.push(ProfileSection {
                slot,
                title: title.into(),
                imprint: imprint.into(),
                stats,
                entries,
            });
        }
    }

    let density = density_of(style, sheet.size, &sections, &history, &licenses, &career);

    ProfileSheetLayout {
        style,
        size: sheet.size,
        title: profile_sheet_style_info(style).label,
        imprint: match style {
            ProfileSheetStyle::Resume => "RÉSUMÉ".into(),
            ProfileSheetStyle::Career => "CAREER HISTORY".into(),
        },
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
        career,
        career_more,
        sections,
        density,
    }
}

/// 中身の量の見積もり: 欄の項目 (見出し 1 行 + 本文の折り返し)・実績の数字 (2 行)・表の行。
/// 履歴書の趣味・特技と本人希望記入欄は左右に半分ずつ並ぶので、1 行に入る字も半分。
/// 横に並ぶ欄は高い方に揃うので、2 つのうち多い方を数える。
fn density_of(
    style: ProfileSheetStyle,
    size: ProfileSheetSize,
    sections: &[ProfileSection],
    history: &[ProfileHistoryRow],
    licenses: &[ProfileHistoryRow],
    career: &[ProfileCareerYear],
) -> ProfileSheetDensity {
    let paired = |s: &ProfileSection| {
        style == ProfileSheetStyle::Resume && s.slot != ProfileSlot::Motivation
    };
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
        1 + entries + if s.stats.is_empty() { 0 } else { 2 }
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
    let table_lines = (history.len() + licenses.len()) as u32
        + career.iter().map(|y| 1 + y.rows.len() as u32).sum::<u32>();
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

/// 職務要約の文 (P歴・はじめての参加・数・いちばん通ったブランドから)。
fn career_summary(facts: &Facts, on: &impl Fn(ProfileAutoField) -> bool) -> Option<String> {
    use ProfileAutoField as F;
    let record = facts.record;
    let mut out = String::new();
    if let Some(y) = record.since_year.filter(|_| on(F::Since)) {
        out.push_str(&format!("{y}年よりプロデューサーとして活動。"));
    }
    let first = facts
        .past
        .first()
        .filter(|_| on(F::FieldYears))
        .map(|(d, _)| format!("{}年{}月", d.year(), d.month()));
    if on(F::Counts) {
        let lead = first
            .map(|f| format!("{f}の初参加から、"))
            .unwrap_or_else(|| "これまでに".into());
        out.push_str(&format!(
            "{lead}{}公演に参加し、{}曲を回収。",
            facts.past.len(),
            record.song_count
        ));
    } else if let Some(f) = first {
        out.push_str(&format!("{f}にはじめて現地に参加。"));
    }
    if let Some((b, _)) = facts.top_brand.as_ref().filter(|_| on(F::TopBrand)) {
        out.push_str(&format!("主に{b}の現場に通う。"));
    }
    (!out.is_empty()).then_some(out)
}

fn history_row(day: NaiveDate, text: String, kind: ProfileHistoryKind) -> ProfileHistoryRow {
    ProfileHistoryRow {
        year: day.year().to_string(),
        month: day.month().to_string(),
        text,
        kind,
    }
}

fn career_row(
    day: NaiveDate,
    show: &ProfileShowInput,
    brand: Option<String>,
    planned: bool,
) -> ProfileCareerRow {
    ProfileCareerRow {
        date: format!("{}/{}", day.month(), day.day()),
        title: show.title.clone(),
        venue: show.venue.clone().filter(|v| !v.trim().is_empty()),
        brand,
        planned,
    }
}

fn unique_ids(ids: Vec<String>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for id in ids {
        if !id.is_empty() && !out.contains(&id) {
            out.push(id);
        }
    }
    out
}

// ---------------------------------------------------------------------------
// 担当ブランド (ブランドに丸を付ける・メインは二重丸)
// ---------------------------------------------------------------------------

/// 担当ブランドに並べないブランド (その他は「担当している」と言える範囲ではない)。
const BRANDS_NOT_LISTED: [&str; 1] = ["other"];

/// 並べるブランド (ブランドの並び順、その他を除く)。
fn listed_brands(record: &ProfileSheetRecord) -> Vec<&ProfileBrandInput> {
    let mut brands: Vec<&ProfileBrandInput> = record
        .brands
        .iter()
        .filter(|b| !BRANDS_NOT_LISTED.contains(&b.id.as_str()))
        .collect();
    brands.sort_by(|a, b| {
        a.sort_order
            .cmp(&b.sort_order)
            .then_with(|| a.id.cmp(&b.id))
    });
    brands
}

/// 記録から丸が付くブランド: 担当の所属と、今日までに参加した公演のライブのブランド。
fn record_brand_ids(record: &ProfileSheetRecord) -> HashSet<String> {
    let today = parse_date(&record.today);
    let mut ids: HashSet<String> = record.oshi_brand_ids.iter().cloned().collect();
    for s in &record.attended {
        let past = matches!((parse_date(&s.date), today), (Some(d), Some(t)) if d <= t);
        if past {
            if let Some(b) = &s.brand_id {
                ids.insert(b.clone());
            }
        }
    }
    ids
}

/// メインの既定: 最初の担当のブランド、担当がいなければいちばん多く参加したブランド。
fn default_main_brand(record: &ProfileSheetRecord) -> Option<String> {
    let listed = listed_brands(record);
    let is_listed = |id: &str| listed.iter().any(|b| b.id == id);
    if let Some(b) = record.oshi_brand_ids.iter().find(|b| is_listed(b)) {
        return Some(b.clone());
    }
    let facts = Facts::new(record);
    let label = facts.top_brand?.0;
    listed
        .iter()
        .find(|b| b.label == label)
        .map(|b| b.id.clone())
}

/// 担当ブランドの並び (ブランドの並び順、その他を除く) と丸。丸は記録から付け、自分で付け外しした分を
/// 重ねる。メイン (二重丸) は 1 つだけで、丸の付いたブランドのうち、上書きがあればそれ、無ければ既定
/// ([`default_main_brand`])。
pub fn profile_brand_marks(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> Vec<ProfileBrandCheck> {
    let from_record = record_brand_ids(record);
    let listed = listed_brands(record);
    let checked_of = |id: &str| -> bool {
        if from_record.contains(id) {
            !sheet.brand_off.iter().any(|b| b == id)
        } else {
            sheet.brand_on.iter().any(|b| b == id)
        }
    };
    let main = match &sheet.brand_main {
        Some(id) if id.is_empty() => None,
        Some(id) => Some(id.clone()),
        None => default_main_brand(record),
    }
    .filter(|id| listed.iter().any(|b| &b.id == id) && checked_of(id));
    listed
        .into_iter()
        .map(|b| {
            let checked = checked_of(&b.id);
            let is_main = main.as_deref() == Some(b.id.as_str());
            let rings = match (checked, is_main) {
                (false, _) => Vec::new(),
                (true, false) => vec![hand_ring(&b.id, 0)],
                (true, true) => vec![hand_ring(&b.id, 0), hand_ring(&b.id, 1)],
            };
            ProfileBrandCheck {
                id: b.id.clone(),
                label: b.label.clone(),
                color: b.color.clone(),
                checked,
                main: is_main,
                from_record: from_record.contains(&b.id),
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

/// 担当ブランドのブランドを 1 回押した選択。押すたびに 丸なし → 丸 → 二重丸 (メイン) → 丸なし と回す。
///
/// - 記録から付く丸を外したら `brand_off` に、記録に無い丸を付けたら `brand_on` に入れる
///   (記録が増えても、自分で決めた分は変えない)。
/// - 丸を二重丸にしたら、それがメイン (前のメインは丸に戻る)。
/// - 二重丸を押したら丸なしにし、メインは「なし」に決める (既定のメインを勝手に戻さない)。
pub fn profile_toggle_brand(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
    brand_id: &str,
) -> ProfileSheet {
    let Some(mark) = profile_brand_marks(sheet, record)
        .into_iter()
        .find(|b| b.id == brand_id)
    else {
        return sheet.clone();
    };
    let mut out = sheet.clone();
    let set_checked = |out: &mut ProfileSheet, checked: bool| {
        // 前に決めた分を両方から消し、今の記録に対して要る方にだけ入れる
        // (記録が後から変わっても、最後に押した向きが残る)。
        out.brand_on.retain(|b| b != brand_id);
        out.brand_off.retain(|b| b != brand_id);
        match (checked, mark.from_record) {
            (false, true) => out.brand_off.push(brand_id.to_string()),
            (true, false) => out.brand_on.push(brand_id.to_string()),
            _ => {}
        }
    };
    match (mark.checked, mark.main) {
        (false, _) => set_checked(&mut out, true),
        (true, false) => out.brand_main = Some(brand_id.to_string()),
        (true, true) => {
            set_checked(&mut out, false);
            out.brand_main = Some(String::new());
        }
    }
    out
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
            favorite_songs: vec![
                ProfileSongInput {
                    id: "s1".into(),
                    title: "曲1".into(),
                },
                ProfileSongInput {
                    id: "s2".into(),
                    title: "曲2".into(),
                },
            ],
            links: vec!["@fuga_p".into()],
            has_photo: true,
            has_qr: true,
            live: ProfileLiveRecord {
                top_songs: vec![
                    ProfileCount {
                        id: "s9".into(),
                        label: "曲9".into(),
                        count: 3,
                    },
                    ProfileCount {
                        id: "s8".into(),
                        label: "曲8".into(),
                        count: 2,
                    },
                ],
                oshi_heard: vec![ProfileCount {
                    id: "haruka".into(),
                    label: "天海春香".into(),
                    count: 5,
                }],
                top_venue: Some(ProfileCount {
                    id: "v:ssa".into(),
                    label: "さいたまスーパーアリーナ".into(),
                    count: 2,
                }),
                prefecture_count: 3,
            },
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
            live: ProfileLiveRecord::default(),
            ..record()
        }
    }

    fn career() -> ProfileSheet {
        ProfileSheet {
            style: ProfileSheetStyle::Career,
            ..profile_sheet_default()
        }
    }

    #[test]
    fn default_is_resume_with_qr_hidden() {
        let s = profile_sheet_default();
        assert_eq!(s.style, ProfileSheetStyle::Resume);
        assert_eq!(s.size, ProfileSheetSize::Portrait);
        assert_eq!(s.hidden, vec![ProfileAutoField::Qr]);
        assert_eq!(s.brand_main, None);
    }

    #[test]
    fn json_round_trip_keeps_choices() {
        let mut s = career();
        s.size = ProfileSheetSize::Story;
        s.hidden = vec![ProfileAutoField::Photo, ProfileAutoField::Yearly];
        s.brand_on = vec!["sm".into()];
        s.brand_off = vec!["cg".into()];
        s.brand_main = Some("ml".into());
        assert_eq!(profile_sheet_from_json(&profile_sheet_to_json(&s)), s);
        // メインなし (空文字) も残る。既定 (None) はキーを書かない。
        s.brand_main = Some(String::new());
        assert_eq!(profile_sheet_from_json(&profile_sheet_to_json(&s)), s);
        assert!(!profile_sheet_to_json(&profile_sheet_default()).contains("brandMain"));
    }

    #[test]
    fn old_json_with_answers_still_reads() {
        assert_eq!(profile_sheet_from_json(""), profile_sheet_default());
        assert_eq!(profile_sheet_from_json("{"), profile_sheet_default());
        let s = profile_sheet_from_json(
            r#"{"style":"career","size":"story","furigana":"ふがぴー",
                "answers":[{"q":"message","prompt":"","text":"よろしく"}],
                "hidden":["qr","qr","sparkles","songs"],"songs":["a","b"],
                "brandOn":["sm","sm"],"brandOff":[]}"#,
        );
        assert_eq!(s.style, ProfileSheetStyle::Career);
        assert_eq!(s.size, ProfileSheetSize::Story);
        assert_eq!(
            s.hidden,
            vec![ProfileAutoField::Qr, ProfileAutoField::Songs]
        );
        assert_eq!(s.brand_on, vec!["sm"]);
        assert_eq!(s.brand_main, None);
        // 書き直すと前の版の答えは残らない。
        let json = profile_sheet_to_json(&s);
        assert!(!json.contains("answers") && !json.contains("furigana"));
    }

    #[test]
    fn resume_history_and_licenses_come_from_records() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &record());
        assert_eq!(layout.title, "履歴書");
        assert_eq!(layout.as_of, "2026年10月6日現在");
        assert_eq!(layout.name, "ふがP");
        assert_eq!(layout.since_label.as_deref(), Some("2014年 就任 · P歴12年"));
        let rows: Vec<(String, String, String)> = layout
            .history
            .iter()
            .map(|r| (r.year.clone(), r.month.clone(), r.text.clone()))
            .collect();
        assert_eq!(
            rows,
            vec![
                ("2014".into(), "".into(), "プロデューサーに就任".into()),
                ("2015".into(), "7".into(), "はじめて参加　公演a".into()),
                ("2026".into(), "9".into(), "最近の現場　公演d".into()),
                ("".into(), "".into(), "以上".into()),
            ]
        );
        // 重複した参加は 1 回に数え、予定は数えない。
        let licenses: Vec<&str> = layout.licenses.iter().map(|r| r.text.as_str()).collect();
        assert_eq!(
            licenses,
            vec![
                "参加公演 4公演・回収曲 523曲 達成",
                "現地 3都道府県 踏破",
                "現場歴 11年 到達",
            ]
        );
        assert!(layout.career.is_empty());
        assert_eq!(layout.brands_title, "担当ブランド");
        assert_eq!(layout.contacts, vec!["@fuga_p"]);
        assert!(!layout.show_qr);
        assert!(layout.show_photo);
    }

    #[test]
    fn resume_slots_hold_songs_places_and_next_show() {
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
                    vec![
                        ("現地でいちばん聴いた曲", "「曲9」3回　「曲8」2回"),
                        ("担当の歌を現地で聴いた回数", "天海春香 5回"),
                    ]
                ),
                (
                    ProfileSlot::Hobby,
                    vec![
                        ("お気に入りの曲", "「曲1」「曲2」"),
                        ("いちばん通ったブランド", "シンデレラ 2公演"),
                        ("いちばん通った会場", "さいたまスーパーアリーナ 2回"),
                    ]
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
        // 参加 1 公演: はじめての参加だけ。P歴・最近の現場・予定・資格の数の他は出ない。
        assert_eq!(layout.history.len(), 2);
        assert_eq!(layout.licenses.len(), 1);
        assert_eq!(layout.licenses[0].text, "参加公演 1公演・回収曲 0曲 達成");
        let fields: Vec<ProfileAutoField> = layout
            .sections
            .iter()
            .flat_map(|s| s.entries.iter().map(|e| e.field))
            .collect();
        assert_eq!(fields, vec![ProfileAutoField::TopBrand]);
        assert!(!layout.show_photo && !layout.show_oshi);
        assert!(layout.since_label.is_none());
        // 編集画面にも記録の無い欄は並ばない。
        let keys: Vec<String> = profile_auto_field_rows(&profile_sheet_default(), &sparse_record())
            .into_iter()
            .map(|r| r.key)
            .collect();
        assert_eq!(keys, vec!["brands", "shows", "counts", "top_brand"]);
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
    fn career_has_summary_table_skills_and_stats() {
        let layout = profile_sheet_layout(&career(), &record());
        assert_eq!(layout.title, "職務経歴書");
        let years: Vec<(&str, &str, usize)> = layout
            .career
            .iter()
            .map(|y| (y.year.as_str(), y.count_label.as_str(), y.rows.len()))
            .collect();
        assert_eq!(years, vec![("2026年", "2公演", 3), ("2025年", "1公演", 1)]);
        assert_eq!(layout.career_more, 1);
        assert!(layout.career[0].rows[0].planned);
        assert_eq!(layout.career[0].rows[0].date, "11/3");
        assert_eq!(
            layout.career[0].rows[1].brand.as_deref(),
            Some("シンデレラ")
        );
        let slots: Vec<ProfileSlot> = layout.sections.iter().map(|s| s.slot).collect();
        assert_eq!(
            slots,
            vec![
                ProfileSlot::Summary,
                ProfileSlot::Skills,
                ProfileSlot::SelfPr
            ]
        );
        assert_eq!(
            layout.sections[0].entries[0].text,
            "2014年よりプロデューサーとして活動。2015年7月の初参加から、4公演に参加し、523曲を回収。主にシンデレラの現場に通う。"
        );
        let stats: Vec<(&str, &str, &str)> = layout.sections[2]
            .stats
            .iter()
            .map(|s| (s.label.as_str(), s.value.as_str(), s.unit.as_str()))
            .collect();
        assert_eq!(
            stats,
            vec![
                ("参加公演", "4", "公演"),
                ("回収曲", "523", "曲"),
                ("現地", "3", "都道府県"),
                ("担当の歌唱", "5", "回"),
                ("現場歴", "11", "年"),
            ]
        );
        assert_eq!(
            layout.sections[2].entries[0].text,
            "2026年 2公演　2025年 1公演　2015年 1公演"
        );
        assert!(layout.history.is_empty());
        // 年ごとの参加数は職務経歴書だけの欄。
        assert!(profile_auto_field_rows(&profile_sheet_default(), &record())
            .iter()
            .all(|r| r.field != ProfileAutoField::Yearly));
        assert!(profile_auto_field_rows(&career(), &record())
            .iter()
            .any(|r| r.field == ProfileAutoField::Yearly));
    }

    #[test]
    fn career_caps_rows_by_size_and_counts_the_rest() {
        let mut rec = record();
        rec.attended = (1..=20)
            .map(|i| {
                show(
                    &format!("s{i:02}"),
                    &format!("2024-{:02}-01", (i % 12) + 1),
                    "765",
                )
            })
            .collect();
        rec.attended.dedup_by(|a, b| a.date == b.date);
        let mut sheet = career();
        let portrait = profile_sheet_layout(&sheet, &rec);
        let shown: usize = portrait.career.iter().map(|y| y.rows.len()).sum();
        assert_eq!(shown, 4);
        assert_eq!(portrait.career_more as usize, rec.attended.len() - 4);
        sheet.size = ProfileSheetSize::Story;
        let story = profile_sheet_layout(&sheet, &rec);
        assert_eq!(story.career.iter().map(|y| y.rows.len()).sum::<usize>(), 8);
    }

    #[test]
    fn density_relaxes_for_sparse_records_and_on_story() {
        let sparse = profile_sheet_layout(&profile_sheet_default(), &sparse_record());
        assert_eq!(sparse.density, ProfileSheetDensity::Regular);
        let mut rec = record();
        rec.live.top_songs = (0..3)
            .map(|i| ProfileCount {
                id: format!("t{i}"),
                label: "とても長い曲名".repeat(4),
                count: 9,
            })
            .collect();
        let dense = profile_sheet_layout(&profile_sheet_default(), &rec);
        assert_ne!(dense.density, ProfileSheetDensity::Regular);
        let mut story = profile_sheet_default();
        story.size = ProfileSheetSize::Story;
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
        assert_eq!(profile_sheet_styles()[0].label, "履歴書");
        assert_eq!(
            profile_auto_field_info(ProfileAutoField::Brands).label,
            "担当ブランド"
        );
    }

    #[test]
    fn brand_marks_skip_other_follow_sort_order_and_keep_manual_choices() {
        let mut rec = record();
        rec.brands.push(brand("other", "Other", 99));
        rec.brands.reverse();
        let sheet = profile_sheet_default();
        let marks = profile_brand_marks(&sheet, &rec);
        let ids: Vec<&str> = marks.iter().map(|b| b.id.as_str()).collect();
        assert_eq!(ids, vec!["765", "cg", "ml", "sm"]);
        assert!(marks.iter().all(|b| b.checked == b.from_record));
        assert!(!marks[3].checked && marks[3].rings.is_empty());

        // 記録に無いのに付けた丸を、記録が付いた後で外し、記録がまた消えても外したまま。
        let mut later = rec.clone();
        later.oshi_brand_ids.push("sm".into());
        let picked = profile_toggle_brand(&sheet, &rec, "sm");
        assert_eq!(picked.brand_on, vec!["sm"]);
        // 記録が付いた後で 丸 → 二重丸 → 丸なし。
        let main = profile_toggle_brand(&picked, &later, "sm");
        let dropped = profile_toggle_brand(&main, &later, "sm");
        assert!(!profile_brand_marks(&dropped, &rec)
            .iter()
            .any(|b| b.id == "sm" && b.checked));
        assert_eq!(
            profile_sheet_from_json(&profile_sheet_to_json(&dropped)),
            dropped
        );
    }

    #[test]
    fn main_brand_defaults_to_first_oshi_then_most_attended() {
        let marks = profile_brand_marks(&profile_sheet_default(), &record());
        let main: Vec<&str> = marks
            .iter()
            .filter(|b| b.main)
            .map(|b| b.id.as_str())
            .collect();
        assert_eq!(main, vec!["765"]);
        assert_eq!(marks[0].rings.len(), 2);
        assert_eq!(marks[1].rings.len(), 1);
        // 担当がいなければいちばん多く参加したブランド。
        let mut rec = record();
        rec.oshi_brand_ids.clear();
        let marks = profile_brand_marks(&profile_sheet_default(), &rec);
        assert_eq!(
            marks
                .iter()
                .filter(|b| b.main)
                .map(|b| b.id.as_str())
                .collect::<Vec<_>>(),
            vec!["cg"]
        );
        // 記録が無ければメインも無い。
        let mut empty = sparse_record();
        empty.attended.clear();
        assert!(profile_brand_marks(&profile_sheet_default(), &empty)
            .iter()
            .all(|b| !b.main && !b.checked));
    }

    #[test]
    fn tapping_a_brand_cycles_none_circle_double_none() {
        let rec = record();
        let s0 = profile_sheet_default();
        let state = |s: &ProfileSheet, id: &str| -> (bool, bool) {
            let m = profile_brand_marks(s, &rec)
                .into_iter()
                .find(|b| b.id == id)
                .unwrap();
            (m.checked, m.main)
        };
        assert_eq!(state(&s0, "sm"), (false, false));
        let s1 = profile_toggle_brand(&s0, &rec, "sm");
        assert_eq!(state(&s1, "sm"), (true, false));
        let s2 = profile_toggle_brand(&s1, &rec, "sm");
        assert_eq!(state(&s2, "sm"), (true, true));
        // メインは 1 つだけ: 前のメインは丸に戻る。
        assert_eq!(state(&s2, "765"), (true, false));
        let s3 = profile_toggle_brand(&s2, &rec, "sm");
        assert_eq!(state(&s3, "sm"), (false, false));
        // 二重丸を外した後は既定のメインを勝手に戻さない。
        assert!(profile_brand_marks(&s3, &rec).iter().all(|b| !b.main));
        assert_eq!(s3.brand_main.as_deref(), Some(""));
        // 記録から付く丸 (cg) も同じ順で回る。
        let c1 = profile_toggle_brand(&s0, &rec, "cg");
        assert_eq!(state(&c1, "cg"), (true, true));
        let c2 = profile_toggle_brand(&c1, &rec, "cg");
        assert_eq!(state(&c2, "cg"), (false, false));
        assert_eq!(c2.brand_off, vec!["cg"]);
        // 知らない id は何も変えない。
        assert_eq!(profile_toggle_brand(&s0, &rec, "zzz"), s0);
    }

    #[test]
    fn brand_rings_are_stable_and_in_range() {
        let rec = record();
        let a = profile_brand_marks(&profile_sheet_default(), &rec);
        assert_eq!(a, profile_brand_marks(&profile_sheet_default(), &rec));
        for m in &a {
            for (i, r) in m.rings.iter().enumerate() {
                assert!((-20.0..=20.0).contains(&r.tilt_degrees));
                assert!((0.92..=1.13).contains(&r.stretch));
                assert!((0.0..360.0).contains(&r.start_degrees));
                assert!(
                    (-0.04..=0.04).contains(&r.offset_x) && (-0.1..=0.1).contains(&r.offset_y)
                );
                if i == 0 {
                    assert_eq!(r.scale, 1.0);
                } else {
                    assert!((1.22..=1.30).contains(&r.scale));
                    assert_ne!(r.tilt_degrees, m.rings[0].tilt_degrees);
                }
            }
        }
    }

    #[test]
    fn live_record_counts_heard_songs_oshi_venues_and_prefectures() {
        use crate::test_support::bundle_snapshot;
        let snap = bundle_snapshot();
        // 披露に数える公演を古い順に 40 公演。
        let shows: Vec<String> = snap
            .shows_in_date_order
            .iter()
            .map(|&s| &snap.shows[s as usize])
            .filter(|s| s.counts_as_performance() && s.date.as_str() <= "2026-01-01")
            .filter(|s| {
                !snap.setlist_items_by_show[snap.show_index_by_id[&s.id] as usize].is_empty()
            })
            .take(40)
            .map(|s| s.id.clone())
            .collect();
        assert_eq!(shows.len(), 40);
        // 最初の公演で最初に歌ったアイドルを担当にする。
        let first = snap.show_index_by_id[&shows[0]];
        let item = snap.setlist_items_by_show[first as usize][0];
        let idol = snap.performers_by_item[item as usize]
            .first()
            .map(|&i| snap.idols[i as usize].id.clone());
        let oshi: Vec<String> = idol
            .into_iter()
            .chain(["no-such-idol".to_string()])
            .collect();
        let mut ids = shows.clone();
        ids.push(shows[0].clone()); // 重複は 1 回
        let live = profile_live_record(snap, &ids, &oshi, "2026-10-06");
        assert!(
            !live.top_songs.is_empty(),
            "40 公演なら 2 回以上聴いた曲がある"
        );
        assert!(live.top_songs.len() <= 3);
        assert!(live.top_songs.windows(2).all(|w| w[0].count >= w[1].count));
        assert!(live.top_songs.iter().all(|c| c.count >= 2));
        // 1 曲目の回数をセトリから数え直して合わせる。
        let top = snap.song_index_by_id[&live.top_songs[0].id];
        let expected = shows
            .iter()
            .map(|id| snap.show_index_by_id[id])
            .flat_map(|s| snap.setlist_items_by_show[s as usize].iter())
            .filter(|&&i| snap.setlist_items[i as usize].song == top)
            .count() as u32;
        assert_eq!(live.top_songs[0].count, expected);
        assert!(live.oshi_heard.len() <= 1 && live.oshi_heard.iter().all(|c| c.count >= 1));
        if let Some(v) = &live.top_venue {
            assert!(v.count >= 2);
        }
        // 今日より後の公演だけなら何も数えない。
        let none = profile_live_record(snap, &shows, &oshi, "1990-01-01");
        assert_eq!(none, ProfileLiveRecord::default());
    }
}
