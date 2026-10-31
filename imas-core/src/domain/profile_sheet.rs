//! P名刺の画像 (SNS に貼る自己紹介の 1 枚絵) の中身・欄の割り当て・行の組み立て。
//!
//! P名刺の 3 つ目の出し方 (交換する・紙に刷る・SNS に貼る画像)。名刺は交換するもの (誰で、どうつながれるか)、
//! この画像は見せるもの (どんな P か、どう歩んできたか)。2026-10 に「プロフィール帳」という別の機能をやめて
//! P名刺に一本化した。P を「職業」に見立てた **P履歴書** の様式で 1 枚にする。
//!
//! **開けばもう全部埋まっている** (簡単に作れる)。こだわる人は欄ごとの付け外しと、好きな曲・思い出の公演を
//! 自分で選べる (2026-10-31 ユーザー「たくさんこだわって作れるものにしたいな。簡単にも作れるけど」)。
//! 自分で文字を書く欄は無い (ひとことは P名刺のもの)。
//!
//! 欄 (2026-10-26 の作り直し。ユーザー「RESUME みたいなサブタイトルいらない。あと謎のハンコも」
//! 「志望動機とかよりちゃんとした名前のものにしてほしい」「P歴はもっとたくさん書いてあげた方がいい」
//! 「履歴書にはすべての担当を乗せたい」):
//! - 頭: 氏名・P歴・担当 (アプリの担当を全員。名刺に載せる担当の選択とは別。ブランドごとに 1 行)・
//!   連絡先と証明写真。担当ブランド (ブランドの名前に丸)。
//! - P歴の表: 就任 / はじめての参加 / ブランドごとのはじめて / 節目の公演 (10・30・50・100…公演目) /
//!   最近の現場 / 以上。
//! - 欄: 好きな曲・思い出の公演・次の現場・記録 (参加公演・回収曲・円盤)・ひとこと。
//! 英字の印字 (RÉSUMÉ / MOTIVATION) と押印欄の判子は無い (取って付けたように見えるため)。
//! 欄の名前は中身そのまま (志望の動機・本人希望記入欄・免許・資格のような書類の言い換えはしない)。
//! 記録から数えた「へえ」止まりの数字 (担当の歌唱の回数・いちばん聴いた曲・いちばん通った会場や年・
//! 都道府県の数) は載せない (2026-10 ユーザー「基本いらない」)。
//!
//! どの記録がどの欄に入るか・欄の並び・行の組み立て・上限・文字の詰め方 (`ProfileSheetDensity`)・
//! 担当ブランドの丸はここで決め、端末 (iOS / Android) はこの結果を描くだけにする。
//! 担当ブランドの丸はアプリ全体の設定 (`brand_role`。担当 = 丸・メイン = 二重丸、メインは複数可) から描き、
//! 設定がまだ無ければ記録から組んだ既定を使う。P名刺の画像の中では丸を上書きしない。
//!
//! 保存するのは選択だけ (自分の P名刺の行に JSON で持つ。`profile_sheet_to_json`)。大きさ・外した欄・
//! 思い出の公演は画像の画面で、好きな曲 (曲 id の並び) は P名刺の編集で選ぶ (好きな曲は P名刺の項目。
//! 名刺の QR には入らない)。名前・P歴・ひとこと・リンク・自分の QR・証明写真の欄の写真は P名刺のものを使う。

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
    /// 担当 (アプリの担当を全員)。
    Oshi,
    /// 担当ブランド (ブランドの名前に丸)。
    Brands,
    /// P歴 (就任の年。P名刺から)。
    Since,
    /// P歴の表の、はじめて参加したライブ・最近の現場。
    Shows,
    /// P歴の表の、ブランドごとのはじめての参加。
    BrandFirsts,
    /// P歴の表の、節目の公演 (10・30・50・100…公演目)。
    Milestones,
    /// 好きな曲 (お気に入りの中から選んだ曲)。
    Songs,
    /// 思い出の公演 (参加した公演から選ぶ。まだ選んでいなければお気に入りのライブの公演)。
    Memories,
    /// 次の現場 (近い順に 3 つまで)。
    NextShow,
    /// 記録 (参加公演数・回収曲数・円盤の数)。
    Counts,
    /// ひとこと (P名刺から)。
    Message,
    /// リンク (連絡先。P名刺から)。
    Links,
    /// 自分の QR (P名刺から。既定は載せない)。
    Qr,
}

/// 選ぶ画面で欄をまとめる見出し。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileFieldGroup {
    /// 「プロフィール」(写真・担当・担当ブランド)。
    Basics,
    /// 「P歴の表」。
    History,
    /// 「欄」(好きな曲・思い出の公演・次の現場・記録・ひとこと)。
    Sections,
    /// 「連絡先」(リンク・自分の QR)。
    Contact,
}

/// 下に並べる欄。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileSlot {
    /// 好きな曲。
    Songs,
    /// 思い出の公演。
    Memories,
    /// 次の現場。
    NextShow,
    /// 記録。
    Records,
    /// ひとこと。
    Message,
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
    /// 載せる思い出の公演 (公演 id、載せる順)。None はまだ選んでいない
    /// (参加した公演のうち、ライブをお気に入りにしたものを新しい順に)。
    pub memories: Option<Vec<String>>,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAutoFieldInfo {
    pub field: ProfileAutoField,
    pub key: String,
    /// 選ぶ画面の名前 (「節目の公演」)。
    pub label: String,
    pub group: ProfileFieldGroup,
}

/// 選ぶ画面の「載せる項目」の 1 行。記録の無い欄は並べない。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAutoFieldRow {
    pub field: ProfileAutoField,
    pub key: String,
    pub label: String,
    pub group: ProfileFieldGroup,
    /// 今の記録で載る中身の短い見本 (「19公演・323曲」)。写真・QR・担当ブランドは空。
    pub value: String,
    /// 載せているか。
    pub shown: bool,
    /// 中身が P名刺から入る欄か (P歴・ひとこと・リンク・自分の QR)。直すのは P名刺の編集。
    pub from_card: bool,
    /// 中身を自分で選べる欄か (好きな曲・思い出の公演)。端末は選ぶ画面への入口を添える。
    pub pickable: bool,
}

/// 選ぶ画面の見出し 1 つと、その下の行。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileFieldGroupRows {
    pub group: ProfileFieldGroup,
    /// 「P歴の表」。
    pub title: String,
    pub rows: Vec<ProfileAutoFieldRow>,
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
    /// この公演のライブをお気に入りにしているか (思い出の公演の既定に使う)。
    pub favorite: bool,
}

/// 担当 1 人 (アプリの担当の並び)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileOshiInput {
    pub idol_id: String,
    pub name: String,
    /// 所属ブランド。分からなければ空。
    pub brand_id: String,
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

/// P名刺の画像の材料。名前・P歴・ひとこと・リンク・QR は P名刺から、ほかはアプリの記録から。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheetRecord {
    /// 今日 (`YYYY-MM-DD`、JST)。
    pub today: String,
    pub name: String,
    pub since_year: Option<u16>,
    /// アプリの担当すべて (アプリの並び)。
    pub oshi: Vec<ProfileOshiInput>,
    /// 担当の所属ブランド (担当ブランドの既定に使う)。
    pub oshi_brand_ids: Vec<String>,
    pub attended: Vec<ProfileShowInput>,
    pub song_count: u32,
    /// 持っている円盤 (映像) の数。
    pub owned_release_count: u32,
    pub brands: Vec<ProfileBrandInput>,
    /// 担当ブランドの設定 (アプリ全体の設定の保存の形 `brand_roles_to_json`。空はまだ決めていない)。
    pub brand_roles_json: String,
    /// お気に入りの曲すべて (並びは問わない。載せる曲と順は [`ProfileSheet::songs`] の選択から)。
    pub favorite_songs: Vec<ProfileSongInput>,
    /// P名刺のひとこと。
    pub message: String,
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
    /// ブランドごとのはじめての参加。
    BrandFirst,
    /// 節目の公演。
    Milestone,
    RecentShow,
    /// 表の終わりの「以上」(右に寄せる)。
    Closing,
}

/// 年・月・内容の 1 行 (P歴の表)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileHistoryRow {
    pub year: String,
    pub month: String,
    pub text: String,
    pub kind: ProfileHistoryKind,
}

/// 担当の 1 行 (ブランド 1 つ分)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileOshiGroup {
    pub brand_id: String,
    /// 行の頭に刷るブランドの短い名前。ブランドが 1 つだけなら空 (刷らない)。
    pub brand_label: String,
    /// 担当 (アプリの並び)。
    pub idol_ids: Vec<String>,
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

/// 欄の中の 1 項目。好きな曲は `label` が空で `text` が曲名、思い出の公演・次の現場は `label` が日付、
/// 記録は `label` が項目の名前 (「参加公演」) で `text` が数 (「19公演」)、ひとことは `text` だけ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileEntry {
    pub field: ProfileAutoField,
    pub label: String,
    pub text: String,
    /// 添え書き (会場)。無ければ空。
    pub note: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSection {
    pub slot: ProfileSlot,
    /// 「好きな曲」。
    pub title: String,
    pub entries: Vec<ProfileEntry>,
}

/// 描く形。欄は様式の並び順で、中身の無い欄は入れない。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileSheetLayout {
    pub size: ProfileSheetSize,
    /// 「P履歴書」。
    pub title: String,
    /// 「2026年10月6日現在」。
    pub as_of: String,
    pub name: String,
    pub show_photo: bool,
    pub show_qr: bool,
    /// 「2014年 就任 · P歴12年」。外したら None。
    pub since_label: Option<String>,
    /// 担当 (ブランドごとの行。外したら空)。
    pub oshi_groups: Vec<ProfileOshiGroup>,
    /// 連絡先 (外したら空)。
    pub contacts: Vec<String>,
    /// 担当ブランドの欄の名前 (「担当ブランド」)。
    pub brands_title: String,
    /// 担当ブランドの並び (外したら空)。
    pub brands: Vec<ProfileBrandCheck>,
    /// P歴の表の題 (「P歴」)。
    pub history_title: String,
    /// P歴の表。最後の行は「以上」。
    pub history: Vec<ProfileHistoryRow>,
    pub sections: Vec<ProfileSection>,
    pub density: ProfileSheetDensity,
}

/// 思い出の公演を選ぶ画面に並べるもの。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileMemoryPicks {
    /// 載せる公演 (載せる順)。
    pub picked: Vec<ProfileShowInput>,
    /// 本人が選んだか (false はまだ選んでいなくて、既定の選び方の結果が入っている)。
    pub chosen_by_hand: bool,
    /// 参加した公演すべて (新しい順)。
    pub candidates: Vec<ProfileShowInput>,
    pub max: u32,
    /// 上限まで選んだか。
    pub full: bool,
}

// ---------------------------------------------------------------------------
// 決まり
// ---------------------------------------------------------------------------

const TITLE: &str = "P履歴書";
const BRANDS_TITLE: &str = "担当ブランド";
const HISTORY_TITLE: &str = "P歴";

/// 思い出の公演の上限。
pub const MAX_MEMORIES: usize = 5;
/// まだ選んでいないときに既定で載せる思い出の公演の数。
const DEFAULT_MEMORIES: usize = 3;
/// 次の現場の上限。
const MAX_NEXT_SHOWS: usize = 3;
/// 節目の公演 (この公演目に達した公演を P歴に刷る)。
const MILESTONES: [usize; 9] = [10, 30, 50, 100, 150, 200, 300, 400, 500];

/// 選ぶ画面の順 (見出しごと)。
const ALL_AUTO_FIELDS: [ProfileAutoField; 14] = [
    ProfileAutoField::Photo,
    ProfileAutoField::Oshi,
    ProfileAutoField::Brands,
    ProfileAutoField::Since,
    ProfileAutoField::Shows,
    ProfileAutoField::BrandFirsts,
    ProfileAutoField::Milestones,
    ProfileAutoField::Songs,
    ProfileAutoField::Memories,
    ProfileAutoField::NextShow,
    ProfileAutoField::Counts,
    ProfileAutoField::Message,
    ProfileAutoField::Links,
    ProfileAutoField::Qr,
];

const ALL_GROUPS: [ProfileFieldGroup; 4] = [
    ProfileFieldGroup::Basics,
    ProfileFieldGroup::History,
    ProfileFieldGroup::Sections,
    ProfileFieldGroup::Contact,
];

const ALL_SIZES: [ProfileSheetSize; 2] = [ProfileSheetSize::Portrait, ProfileSheetSize::Story];

const SLOTS: [ProfileSlot; 5] = [
    ProfileSlot::Songs,
    ProfileSlot::Memories,
    ProfileSlot::NextShow,
    ProfileSlot::Records,
    ProfileSlot::Message,
];

pub fn profile_auto_field_info(field: ProfileAutoField) -> ProfileAutoFieldInfo {
    use ProfileAutoField as F;
    use ProfileFieldGroup as G;
    let (key, label, group) = match field {
        F::Photo => ("photo", "証明写真", G::Basics),
        F::Oshi => ("oshi", "担当", G::Basics),
        F::Brands => ("brands", "担当ブランド", G::Basics),
        F::Since => ("since", "就任", G::History),
        F::Shows => ("shows", "はじめての参加・最近の現場", G::History),
        F::BrandFirsts => ("brand_firsts", "ブランドごとのはじめて", G::History),
        F::Milestones => ("milestones", "節目の公演", G::History),
        F::Songs => ("songs", "好きな曲", G::Sections),
        F::Memories => ("memories", "思い出の公演", G::Sections),
        F::NextShow => ("next_show", "次の現場", G::Sections),
        F::Counts => ("counts", "記録", G::Sections),
        F::Message => ("message", "ひとこと", G::Sections),
        F::Links => ("links", "リンク", G::Contact),
        F::Qr => ("qr", "自分の QR", G::Contact),
    };
    ProfileAutoFieldInfo {
        field,
        key: key.into(),
        label: label.into(),
        group,
    }
}

/// 自動の欄の一覧 (選ぶ画面の順)。
pub fn profile_auto_fields() -> Vec<ProfileAutoFieldInfo> {
    ALL_AUTO_FIELDS
        .into_iter()
        .map(profile_auto_field_info)
        .collect()
}

fn group_title(group: ProfileFieldGroup) -> &'static str {
    match group {
        ProfileFieldGroup::Basics => "プロフィール",
        ProfileFieldGroup::History => "P歴の表",
        ProfileFieldGroup::Sections => "欄",
        ProfileFieldGroup::Contact => "連絡先",
    }
}

/// 中身が P名刺から入る欄。
fn from_card(field: ProfileAutoField) -> bool {
    matches!(
        field,
        ProfileAutoField::Since
            | ProfileAutoField::Message
            | ProfileAutoField::Links
            | ProfileAutoField::Qr
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
        memories: None,
    }
}

fn slot_title(slot: ProfileSlot) -> &'static str {
    match slot {
        ProfileSlot::Songs => "好きな曲",
        ProfileSlot::Memories => "思い出の公演",
        ProfileSlot::NextShow => "次の現場",
        ProfileSlot::Records => "記録",
        ProfileSlot::Message => "ひとこと",
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
/// 選んだ好きな曲は `songIds` (前の版の `songs` とは別のキー。無ければまだ選んでいない)、
/// 選んだ思い出の公演は `memoryIds`。
#[derive(serde::Serialize, serde::Deserialize, Default)]
#[serde(default)]
struct SheetDto {
    size: String,
    hidden: Vec<String>,
    #[serde(rename = "songIds", skip_serializing_if = "Option::is_none")]
    song_ids: Option<Vec<String>>,
    #[serde(rename = "memoryIds", skip_serializing_if = "Option::is_none")]
    memory_ids: Option<Vec<String>>,
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
        memory_ids: sheet.memories.clone(),
    };
    serde_json::to_string(&dto).unwrap_or_default()
}

/// 保存の形から戻す。空・壊れた JSON は既定の選択。知らない欄のキー (新しい版が足したもの・
/// 前の版にあってやめた欄) は捨てる (読めない 1 項目のために全部を失わない)。
/// 前の版で保存した選択には新しい欄 (ブランドごとのはじめて・節目・思い出の公演・ひとこと) の
/// キーが無いので、新しい欄は載る側から始まる。
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
        memories: dto.memory_ids,
    }
}

// ---------------------------------------------------------------------------
// 組み立て
// ---------------------------------------------------------------------------

/// 大きさごとの P歴の表の行数の上限 (「以上」を除く)。
fn history_cap(size: ProfileSheetSize) -> usize {
    match size {
        ProfileSheetSize::Portrait => 8,
        ProfileSheetSize::Story => 13,
    }
}

/// 中身の量 (行の見積もり) の上限。これを超えたら 1 段ずつ詰める。
fn density_caps(size: ProfileSheetSize) -> (u32, u32) {
    match size {
        ProfileSheetSize::Portrait => (26, 34),
        ProfileSheetSize::Story => (46, 58),
    }
}

/// 1 行に入る文字数の見積もり (全角で、欄の幅いっぱい)。
const CHARS_PER_LINE: usize = 30;
/// 担当の 1 行に並ぶ人数の見積もり (アイコン + 名前)。
const OSHI_PER_LINE: usize = 4;

/// 記録を数えた中間の形 (組み立てと選ぶ画面の見本で共有する)。
struct Facts<'a> {
    today: Option<NaiveDate>,
    /// 行った公演 (日付の昇順、重複なし)。
    past: Vec<(NaiveDate, &'a ProfileShowInput)>,
    /// これからの現場 (近い順、重複なし)。
    upcoming: Vec<(NaiveDate, &'a ProfileShowInput)>,
    /// 載せる好きな曲 (選んだ順。まだ選んでいなければお気に入りの新しい順の先頭から)。
    songs: Vec<ProfileSongInput>,
    /// 好きな曲を本人が選んだか。
    songs_chosen: bool,
    /// 載せる思い出の公演 (選んだ順。まだ選んでいなければお気に入りのライブの公演を新しい順に)。
    memories: Vec<(NaiveDate, &'a ProfileShowInput)>,
    memories_chosen: bool,
    record: &'a ProfileSheetRecord,
}

impl<'a> Facts<'a> {
    fn new(sheet: &ProfileSheet, record: &'a ProfileSheetRecord) -> Self {
        let today = parse_date(&record.today);
        let mut seen = HashSet::new();
        let mut past: Vec<(NaiveDate, &ProfileShowInput)> = Vec::new();
        let mut upcoming: Vec<(NaiveDate, &ProfileShowInput)> = Vec::new();
        for s in &record.attended {
            if !seen.insert(s.show_id.as_str()) {
                continue;
            }
            let (Some(day), Some(today)) = (parse_date(&s.date), today) else {
                continue;
            };
            if day <= today {
                past.push((day, s));
            } else {
                upcoming.push((day, s));
            }
        }
        past.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.show_id.cmp(&b.1.show_id)));
        upcoming.sort_by(|a, b| a.0.cmp(&b.0).then_with(|| a.1.show_id.cmp(&b.1.show_id)));
        let memories = memory_picked(sheet.memories.as_deref(), &past);
        Facts {
            today,
            past,
            upcoming,
            songs: favorite_song_picked(sheet.songs.as_deref(), &record.favorite_songs),
            songs_chosen: sheet.songs.is_some(),
            memories,
            memories_chosen: sheet.memories.is_some(),
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
        !self.past.is_empty() || self.record.song_count > 0 || self.record.owned_release_count > 0
    }

    /// 記録の項目 (名前と数)。0 の項目は載せない。
    fn count_entries(&self) -> Vec<(&'static str, String)> {
        let r = self.record;
        let mut out = Vec::new();
        if !self.past.is_empty() {
            out.push(("参加公演", format!("{}公演", self.past.len())));
        }
        if r.song_count > 0 {
            out.push(("回収曲", format!("{}曲", r.song_count)));
        }
        if r.owned_release_count > 0 {
            out.push(("円盤", format!("{}枚", r.owned_release_count)));
        }
        out
    }

    /// 載せる担当のブランドごとの行 (ブランドの並び順、ブランドの分からない担当は最後)。
    fn oshi_groups(&self) -> Vec<ProfileOshiGroup> {
        let r = self.record;
        let mut seen = HashSet::new();
        let oshi: Vec<&ProfileOshiInput> = r
            .oshi
            .iter()
            .filter(|o| seen.insert(o.idol_id.as_str()))
            .collect();
        let order = |brand_id: &str| -> (i64, usize) {
            match r.brands.iter().find(|b| b.id == brand_id) {
                Some(b) => (b.sort_order, 0),
                None => (i64::MAX, 0),
            }
        };
        let mut groups: Vec<ProfileOshiGroup> = Vec::new();
        for o in oshi {
            match groups
                .iter_mut()
                .find(|g| !o.brand_id.is_empty() && g.brand_id == o.brand_id)
            {
                Some(g) => g.idol_ids.push(o.idol_id.clone()),
                None => groups.push(ProfileOshiGroup {
                    brand_id: o.brand_id.clone(),
                    brand_label: r
                        .brands
                        .iter()
                        .find(|b| b.id == o.brand_id)
                        .map(|b| b.label.clone())
                        .unwrap_or_default(),
                    idol_ids: vec![o.idol_id.clone()],
                }),
            }
        }
        // 並べ替えは安定 (同じ並び順のブランド・分からないブランドはアプリの並びのまま)。
        groups.sort_by_key(|g| order(&g.brand_id));
        if groups.len() <= 1 {
            for g in &mut groups {
                g.brand_label.clear();
            }
        }
        groups
    }

    /// その欄に載せる記録があるか (無い欄は出さない・選ぶ画面に並べない)。
    fn has(&self, field: ProfileAutoField) -> bool {
        use ProfileAutoField as F;
        let r = self.record;
        match field {
            F::Photo => r.has_photo,
            F::Oshi => !r.oshi.is_empty(),
            F::Brands => !listed_brands(r).is_empty(),
            F::Since => r.since_year.is_some(),
            F::Shows => !self.past.is_empty(),
            F::BrandFirsts => !self.brand_firsts().is_empty(),
            F::Milestones => !self.milestones().is_empty(),
            F::Songs => !r.favorite_songs.is_empty(),
            // 選ぶ画面には参加した公演があれば並べる (お気に入りのライブが無くても自分で選べるように)。
            F::Memories => !self.past.is_empty(),
            F::NextShow => !self.upcoming.is_empty(),
            F::Counts => self.has_counts(),
            F::Message => !r.message.trim().is_empty(),
            F::Links => !r.links.is_empty(),
            F::Qr => r.has_qr,
        }
    }

    /// ブランドごとのはじめての参加 (ブランドの並び順で、全体のはじめての参加と同じ公演は除く)。
    fn brand_firsts(&self) -> Vec<(NaiveDate, &'a ProfileShowInput, String)> {
        let first_id = self.past.first().map(|(_, s)| s.show_id.as_str());
        listed_brands(self.record)
            .into_iter()
            .filter_map(|b| {
                let (d, s) = self
                    .past
                    .iter()
                    .find(|(_, s)| s.brand_id.as_deref() == Some(b.id.as_str()))?;
                (Some(s.show_id.as_str()) != first_id).then(|| (*d, *s, b.label.clone()))
            })
            .collect()
    }

    /// 節目の公演 (何公演目か・日付・公演)。
    fn milestones(&self) -> Vec<(usize, NaiveDate, &'a ProfileShowInput)> {
        MILESTONES
            .into_iter()
            .filter(|n| self.past.len() >= *n)
            .map(|n| {
                let (d, s) = self.past[n - 1];
                (n, d, s)
            })
            .collect()
    }

    /// 選ぶ画面に添える短い見本。
    fn preview(&self, field: ProfileAutoField) -> String {
        use ProfileAutoField as F;
        let r = self.record;
        match field {
            F::Photo | F::Qr | F::Brands => String::new(),
            F::Oshi => {
                let names: Vec<&str> = r.oshi.iter().map(|o| o.name.as_str()).collect();
                if names.len() > 3 {
                    format!("{} ほか{}人", names[..3].join("・"), names.len() - 3)
                } else {
                    names.join("・")
                }
            }
            F::Since => r
                .since_year
                .map(|y| format!("{y}年 プロデューサーに就任"))
                .unwrap_or_default(),
            F::Shows => self
                .past
                .first()
                .map(|(_, s)| format!("初参加　{}", s.title))
                .unwrap_or_default(),
            F::BrandFirsts => self
                .brand_firsts()
                .iter()
                .map(|(_, _, label)| label.as_str())
                .collect::<Vec<_>>()
                .join("・"),
            F::Milestones => self
                .milestones()
                .iter()
                .map(|(n, _, _)| format!("{n}公演目"))
                .collect::<Vec<_>>()
                .join("・"),
            F::Songs => match self.favorite_titles() {
                Some(titles) if self.songs_chosen => titles,
                Some(titles) => format!("おまかせ (お気に入りの新しい順)　{titles}"),
                None => "載せる曲を選んでいません".into(),
            },
            F::Memories => {
                let titles: Vec<&str> = self
                    .memories
                    .iter()
                    .map(|(_, s)| s.title.as_str())
                    .collect();
                match (titles.is_empty(), self.memories_chosen) {
                    (true, _) => "載せる公演を選んでいません".into(),
                    (false, true) => titles.join("・"),
                    (false, false) => {
                        format!("おまかせ (お気に入りのライブ)　{}", titles.join("・"))
                    }
                }
            }
            F::NextShow => self
                .upcoming
                .iter()
                .take(MAX_NEXT_SHOWS)
                .map(|(_, s)| s.title.as_str())
                .collect::<Vec<_>>()
                .join("・"),
            F::Counts => self
                .count_entries()
                .into_iter()
                .map(|(_, v)| v)
                .collect::<Vec<_>>()
                .join("・"),
            F::Message => r.message.trim().to_string(),
            F::Links => r.links.join("　"),
        }
    }
}

/// 思い出の公演に載せるもの。選んでいれば選んだ順 (参加した公演に今あるものだけ・上限まで)、
/// まだ選んでいなければ、ライブをお気に入りにした公演を新しい順に既定の数だけ。
fn memory_picked<'a>(
    chosen: Option<&[String]>,
    past: &[(NaiveDate, &'a ProfileShowInput)],
) -> Vec<(NaiveDate, &'a ProfileShowInput)> {
    match chosen {
        Some(ids) => {
            let mut seen = HashSet::new();
            ids.iter()
                .filter(|id| seen.insert(id.as_str()))
                .filter_map(|id| past.iter().find(|(_, s)| &s.show_id == id).copied())
                .take(MAX_MEMORIES)
                .collect()
        }
        None => past
            .iter()
            .rev()
            .filter(|(_, s)| s.favorite)
            .take(DEFAULT_MEMORIES)
            .copied()
            .collect(),
    }
}

/// 選ぶ画面の「載せる項目」の行。記録のある欄だけを選ぶ画面の順に。
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
                group: info.group,
                value: facts.preview(f),
                shown: !sheet.hidden.contains(&f),
                from_card: from_card(f),
                pickable: matches!(f, ProfileAutoField::Songs | ProfileAutoField::Memories),
            }
        })
        .collect()
}

/// 選ぶ画面の行を見出しごとに (行の無い見出しは並べない)。
pub fn profile_auto_field_groups(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> Vec<ProfileFieldGroupRows> {
    let rows = profile_auto_field_rows(sheet, record);
    ALL_GROUPS
        .into_iter()
        .filter_map(|group| {
            let rows: Vec<ProfileAutoFieldRow> =
                rows.iter().filter(|r| r.group == group).cloned().collect();
            (!rows.is_empty()).then(|| ProfileFieldGroupRows {
                group,
                title: group_title(group).into(),
                rows,
            })
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

/// 思い出の公演を選ぶ画面に並べるもの。
pub fn profile_memory_picks(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> ProfileMemoryPicks {
    let facts = Facts::new(sheet, record);
    let picked: Vec<ProfileShowInput> = facts.memories.iter().map(|(_, s)| (*s).clone()).collect();
    ProfileMemoryPicks {
        full: picked.len() >= MAX_MEMORIES,
        chosen_by_hand: facts.memories_chosen,
        candidates: facts.past.iter().rev().map(|(_, s)| (*s).clone()).collect(),
        max: MAX_MEMORIES as u32,
        picked,
    }
}

/// 公演を 1 つ思い出の公演に載せる / 外した後の選択。載っていなければ末尾に足し (上限なら変えない)、
/// 載っていれば外す。まだ選んでいなければ、今載っている既定の並びから始める。
pub fn profile_toggle_memory(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
    show_id: &str,
) -> ProfileSheet {
    let facts = Facts::new(sheet, record);
    let mut ids: Vec<String> = facts
        .memories
        .iter()
        .map(|(_, s)| s.show_id.clone())
        .collect();
    if let Some(i) = ids.iter().position(|id| id == show_id) {
        ids.remove(i);
    } else if ids.len() < MAX_MEMORIES && facts.past.iter().any(|(_, s)| s.show_id == show_id) {
        ids.push(show_id.to_string());
    }
    ProfileSheet {
        memories: Some(ids),
        ..sheet.clone()
    }
}

/// 思い出の公演の並びを入れ替えた後の選択 (`from` の位置の公演を `to` の位置へ)。
pub fn profile_move_memory(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
    from: u32,
    to: u32,
) -> ProfileSheet {
    let facts = Facts::new(sheet, record);
    let mut ids: Vec<String> = facts
        .memories
        .iter()
        .map(|(_, s)| s.show_id.clone())
        .collect();
    let (from, to) = (from as usize, to as usize);
    if from < ids.len() && to < ids.len() && from != to {
        let id = ids.remove(from);
        ids.insert(to, id);
    }
    ProfileSheet {
        memories: Some(ids),
        ..sheet.clone()
    }
}

fn show_label(s: &ProfileShowInput) -> String {
    s.venue
        .as_deref()
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(str::to_string)
        .unwrap_or_default()
}

fn ymd(d: NaiveDate) -> String {
    format!("{}年{}月{}日", d.year(), d.month(), d.day())
}

pub fn profile_sheet_layout(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> ProfileSheetLayout {
    use ProfileAutoField as F;
    let facts = Facts::new(sheet, record);
    // 載せる欄: 外しておらず、記録がある。
    let on = |f: ProfileAutoField| !sheet.hidden.contains(&f) && facts.has(f);
    let today = facts.today;

    let since_label = record.since_year.filter(|_| on(F::Since)).map(|y| {
        match today.map(|t| t.year() - i32::from(y)) {
            Some(n) if n >= 1 => format!("{y}年 就任 · P歴{n}年"),
            _ => format!("{y}年 就任"),
        }
    });
    let brands = if on(F::Brands) {
        profile_brand_marks(record)
    } else {
        Vec::new()
    };
    let oshi_groups = if on(F::Oshi) {
        facts.oshi_groups()
    } else {
        Vec::new()
    };

    let history = history_rows(sheet, &facts, &on);

    // 欄: 記録を欄に割り当てる。中身の無い欄は出さない。
    let mut sections: Vec<ProfileSection> = Vec::new();
    for slot in SLOTS {
        let entry =
            |field: ProfileAutoField, label: String, text: String, note: String| ProfileEntry {
                field,
                label,
                text,
                note,
            };
        let entries: Vec<ProfileEntry> = match slot {
            ProfileSlot::Songs if on(F::Songs) => facts
                .songs
                .iter()
                .map(|s| entry(F::Songs, String::new(), s.title.clone(), String::new()))
                .collect(),
            ProfileSlot::Memories if on(F::Memories) => facts
                .memories
                .iter()
                .map(|(d, s)| entry(F::Memories, ymd(*d), s.title.clone(), show_label(s)))
                .collect(),
            ProfileSlot::NextShow if on(F::NextShow) => facts
                .upcoming
                .iter()
                .take(MAX_NEXT_SHOWS)
                .map(|(d, s)| entry(F::NextShow, ymd(*d), s.title.clone(), show_label(s)))
                .collect(),
            ProfileSlot::Records if on(F::Counts) => facts
                .count_entries()
                .into_iter()
                .map(|(label, value)| entry(F::Counts, label.into(), value, String::new()))
                .collect(),
            ProfileSlot::Message if on(F::Message) => vec![entry(
                F::Message,
                String::new(),
                record.message.trim().to_string(),
                String::new(),
            )],
            _ => Vec::new(),
        };
        if !entries.is_empty() {
            sections.push(ProfileSection {
                slot,
                title: slot_title(slot).into(),
                entries,
            });
        }
    }

    let density = density_of(sheet.size, &oshi_groups, &sections, &history);
    ProfileSheetLayout {
        size: sheet.size,
        title: TITLE.into(),
        as_of: today.map(|d| format!("{}現在", ymd(d))).unwrap_or_default(),
        name: record.name.trim().to_string(),
        show_photo: on(F::Photo),
        show_qr: on(F::Qr),
        since_label,
        oshi_groups,
        contacts: if on(F::Links) {
            record.links.clone()
        } else {
            Vec::new()
        },
        brands_title: BRANDS_TITLE.into(),
        brands,
        history_title: HISTORY_TITLE.into(),
        history,
        sections,
        density,
    }
}

/// P歴の表。大きさの上限を超えるときは、就任 → はじめて → 最近 → ブランドごとのはじめて →
/// 大きい節目の順に残し、残したものを年の順に並べる (同じ年月は 就任 → はじめて → ブランド →
/// 節目 → 最近)。最近の現場が節目と同じ公演なら節目だけを刷る。
fn history_rows(
    sheet: &ProfileSheet,
    facts: &Facts<'_>,
    on: &dyn Fn(ProfileAutoField) -> bool,
) -> Vec<ProfileHistoryRow> {
    use ProfileAutoField as F;
    use ProfileHistoryKind as K;
    let past = &facts.past;
    let record = facts.record;
    // (優先度, 並べる鍵, 行)。
    let mut rows: Vec<(u32, (i32, u32, u32, u32), ProfileHistoryRow)> = Vec::new();
    if let Some(y) = record.since_year.filter(|_| on(F::Since)) {
        rows.push((
            0,
            (i32::from(y), 0, 0, 0),
            ProfileHistoryRow {
                year: y.to_string(),
                month: String::new(),
                text: "プロデューサーに就任".into(),
                kind: K::Since,
            },
        ));
    }
    let key = |d: NaiveDate, order: u32| (d.year(), d.month(), order, d.day());
    let milestones = if on(F::Milestones) {
        facts.milestones()
    } else {
        Vec::new()
    };
    if on(F::Shows) {
        if let Some((d, s)) = past.first() {
            rows.push((
                1,
                key(*d, 1),
                history_row(*d, format!("初参加　{}", s.title), K::FirstShow),
            ));
        }
        if past.len() >= 2 {
            let (d, s) = past[past.len() - 1];
            if !milestones.iter().any(|(_, _, m)| m.show_id == s.show_id) {
                rows.push((
                    2,
                    key(d, 4),
                    history_row(d, format!("最近の現場　{}", s.title), K::RecentShow),
                ));
            }
        }
    }
    if on(F::BrandFirsts) {
        for (d, s, label) in facts.brand_firsts() {
            rows.push((
                3,
                key(d, 2),
                history_row(d, format!("{label}　初参加　{}", s.title), K::BrandFirst),
            ));
        }
    }
    // 大きい節目ほど優先 (残す順) を上げる。
    for (n, d, s) in milestones.iter().rev() {
        rows.push((
            4,
            key(*d, 3),
            history_row(*d, format!("{n}公演目　{}", s.title), K::Milestone),
        ));
    }
    // 優先度の順に (同じ優先度は入れた順に) 上限まで残す。
    let mut kept: Vec<(usize, &(u32, (i32, u32, u32, u32), ProfileHistoryRow))> =
        rows.iter().enumerate().collect();
    kept.sort_by_key(|(i, (p, _, _))| (*p, *i));
    kept.truncate(history_cap(sheet.size));
    kept.sort_by_key(|(i, (_, k, _))| (*k, *i));
    let mut history: Vec<ProfileHistoryRow> =
        kept.into_iter().map(|(_, (_, _, r))| r.clone()).collect();
    if !history.is_empty() {
        history.push(ProfileHistoryRow {
            year: String::new(),
            month: String::new(),
            text: "以上".into(),
            kind: K::Closing,
        });
    }
    history
}

/// 中身の量の見積もり: 頭 (氏名・P歴・担当の行・連絡先)・P歴の表・欄 (題 1 行 + 項目)。
/// 次の現場と記録は左右に半分ずつ並ぶので、2 つのうち多い方を数える。
fn density_of(
    size: ProfileSheetSize,
    oshi_groups: &[ProfileOshiGroup],
    sections: &[ProfileSection],
    history: &[ProfileHistoryRow],
) -> ProfileSheetDensity {
    let paired =
        |s: &ProfileSection| matches!(s.slot, ProfileSlot::NextShow | ProfileSlot::Records);
    let section_lines = |s: &ProfileSection| -> u32 {
        let per_line = if paired(s) {
            CHARS_PER_LINE / 2
        } else {
            CHARS_PER_LINE
        };
        let entries: u32 = match s.slot {
            // 好きな曲は「」で続けて流し組み。
            ProfileSlot::Songs => {
                let chars: usize = s.entries.iter().map(|e| char_len(&e.text) + 2).sum();
                chars.div_ceil(per_line).max(1) as u32
            }
            _ => s
                .entries
                .iter()
                .map(|e| {
                    let body = char_len(&e.text) + char_len(&e.label) + char_len(&e.note);
                    body.div_ceil(per_line).max(1) as u32
                })
                .sum(),
        };
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
    let oshi_lines: u32 = oshi_groups
        .iter()
        .map(|g| g.idol_ids.len().div_ceil(OSHI_PER_LINE) as u32)
        .sum();
    // 頭は氏名 2 行 + 担当の行 + 2 行 (P歴・連絡先)、担当ブランド 2 行。
    let head = 4 + oshi_lines + 2;
    let load = head + full + pair + history.len() as u32;
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
            favorite: false,
        }
    }

    fn fav(mut s: ProfileShowInput) -> ProfileShowInput {
        s.favorite = true;
        s
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

    fn oshi(id: &str, brand: &str) -> ProfileOshiInput {
        ProfileOshiInput {
            idol_id: id.into(),
            name: format!("アイドル{id}"),
            brand_id: brand.into(),
        }
    }

    fn record() -> ProfileSheetRecord {
        ProfileSheetRecord {
            today: "2026-10-06".into(),
            name: " ふがP ".into(),
            since_year: Some(2014),
            oshi: vec![
                oshi("haruka", "765"),
                oshi("shizuka", "ml"),
                oshi("chihaya", "765"),
            ],
            oshi_brand_ids: vec!["765".into(), "ml".into()],
            attended: vec![
                fav(show("b", "2025-03-01", "ml")),
                show("a", "2015-07-18", "765"),
                fav(show("c", "2026-09-14", "cg")),
                show("d", "2026-09-15", "cg"),
                show("n", "2026-11-03", "765"),
                show("m", "2026-12-24", "ml"),
                show("a", "2015-07-18", "765"),
            ],
            song_count: 523,
            owned_release_count: 12,
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
            message: " よろしくお願いします ".into(),
            links: vec!["@fuga_p".into()],
            has_photo: true,
            has_qr: true,
        }
    }

    /// 記録の少ない人 (参加 1 公演だけ・担当なし・お気に入りなし)。
    fn sparse_record() -> ProfileSheetRecord {
        ProfileSheetRecord {
            since_year: None,
            oshi: Vec::new(),
            oshi_brand_ids: Vec::new(),
            attended: vec![show("x", "2026-08-01", "ml")],
            song_count: 0,
            owned_release_count: 0,
            favorite_songs: Vec::new(),
            message: String::new(),
            links: Vec::new(),
            has_photo: false,
            has_qr: false,
            ..record()
        }
    }

    /// 参加を n 公演 (2016-01-01 から 1 日ずつ、ブランドは 765)。
    fn many_shows(n: usize) -> Vec<ProfileShowInput> {
        let start = NaiveDate::from_ymd_opt(2016, 1, 1).unwrap();
        (0..n)
            .map(|i| {
                let d = start + chrono::Days::new(i as u64);
                show(
                    &format!("p{i:03}"),
                    &d.format("%Y-%m-%d").to_string(),
                    "765",
                )
            })
            .collect()
    }

    fn texts(rows: &[ProfileHistoryRow]) -> Vec<&str> {
        rows.iter().map(|r| r.text.as_str()).collect()
    }

    #[test]
    fn default_is_portrait_with_qr_hidden() {
        let s = profile_sheet_default();
        assert_eq!(s.size, ProfileSheetSize::Portrait);
        assert_eq!(s.hidden, vec![ProfileAutoField::Qr]);
        assert_eq!(s.memories, None);
    }

    #[test]
    fn json_round_trip_keeps_choices() {
        let s = ProfileSheet {
            size: ProfileSheetSize::Story,
            hidden: vec![ProfileAutoField::Photo, ProfileAutoField::Milestones],
            songs: Some(vec!["s2".into(), "s1".into()]),
            memories: Some(vec!["c".into()]),
        };
        assert_eq!(profile_sheet_from_json(&profile_sheet_to_json(&s)), s);
        assert_eq!(
            profile_sheet_to_json(&profile_sheet_default()),
            r#"{"size":"portrait","hidden":["qr"]}"#
        );
        // 選んでから全部外した (空) と、まだ選んでいない (キーなし) は別。
        let emptied = ProfileSheet {
            songs: Some(Vec::new()),
            memories: Some(Vec::new()),
            ..profile_sheet_default()
        };
        assert_eq!(
            profile_sheet_to_json(&emptied),
            r#"{"size":"portrait","hidden":["qr"],"songIds":[],"memoryIds":[]}"#
        );
        assert_eq!(
            profile_sheet_from_json(&profile_sheet_to_json(&emptied)),
            emptied
        );
        assert_eq!(profile_sheet_from_json("壊れた"), profile_sheet_default());
    }

    #[test]
    fn old_json_still_reads_and_new_fields_start_shown() {
        let old = r#"{"size":"story","style":"career","hidden":["counts","qr","nope"],
            "brandOn":["ml"],"answers":{"x":"y"},"songIds":["s1"]}"#;
        let s = profile_sheet_from_json(old);
        assert_eq!(s.size, ProfileSheetSize::Story);
        assert_eq!(
            s.hidden,
            vec![ProfileAutoField::Counts, ProfileAutoField::Qr]
        );
        assert_eq!(s.songs, Some(vec!["s1".into()]));
        assert_eq!(s.memories, None);
        let layout = profile_sheet_layout(&s, &record());
        assert!(layout
            .sections
            .iter()
            .any(|x| x.slot == ProfileSlot::Message));
        assert!(layout
            .history
            .iter()
            .any(|r| r.kind == ProfileHistoryKind::BrandFirst));
    }

    #[test]
    fn heading_has_no_imprints_or_form_wording() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &record());
        assert_eq!(layout.title, "P履歴書");
        assert_eq!(layout.history_title, "P歴");
        assert_eq!(layout.as_of, "2026年10月6日現在");
        assert_eq!(layout.name, "ふがP");
        let titles: Vec<&str> = layout.sections.iter().map(|s| s.title.as_str()).collect();
        assert_eq!(
            titles,
            vec!["好きな曲", "思い出の公演", "次の現場", "記録", "ひとこと"]
        );
        for s in &layout.sections {
            assert!(s.title.chars().all(|c| !c.is_ascii_uppercase()));
        }
    }

    #[test]
    fn all_oshi_are_grouped_by_brand_order() {
        let mut rec = record();
        rec.oshi.push(oshi("unknown", ""));
        rec.oshi.push(oshi("haruka", "765"));
        let layout = profile_sheet_layout(&profile_sheet_default(), &rec);
        let got: Vec<(&str, &str, Vec<&str>)> = layout
            .oshi_groups
            .iter()
            .map(|g| {
                (
                    g.brand_id.as_str(),
                    g.brand_label.as_str(),
                    g.idol_ids.iter().map(String::as_str).collect(),
                )
            })
            .collect();
        assert_eq!(
            got,
            vec![
                ("765", "765", vec!["haruka", "chihaya"]),
                ("ml", "ミリオン", vec!["shizuka"]),
                ("", "", vec!["unknown"]),
            ]
        );
        // ブランドが 1 つならブランドの名前は刷らない。
        rec.oshi = (0..12).map(|i| oshi(&format!("i{i}"), "765")).collect();
        let layout = profile_sheet_layout(&profile_sheet_default(), &rec);
        assert_eq!(layout.oshi_groups.len(), 1);
        assert_eq!(layout.oshi_groups[0].idol_ids.len(), 12);
        assert!(layout.oshi_groups[0].brand_label.is_empty());
        // 外せば並べない。
        let sheet = profile_toggle_field(&profile_sheet_default(), ProfileAutoField::Oshi);
        assert!(profile_sheet_layout(&sheet, &rec).oshi_groups.is_empty());
    }

    #[test]
    fn history_lists_since_firsts_per_brand_and_recent() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &record());
        assert_eq!(
            texts(&layout.history),
            vec![
                "プロデューサーに就任",
                "初参加　公演a",
                "ミリオン　初参加　公演b",
                "シンデレラ　初参加　公演c",
                "最近の現場　公演d",
                "以上",
            ]
        );
        let first = &layout.history[1];
        assert_eq!((first.year.as_str(), first.month.as_str()), ("2015", "7"));
        assert_eq!(layout.history[0].month, "");
        assert_eq!(
            layout.history.last().unwrap().kind,
            ProfileHistoryKind::Closing
        );
    }

    #[test]
    fn milestones_are_dated_by_the_show_that_reached_them() {
        let mut rec = record();
        rec.attended = many_shows(31);
        let layout = profile_sheet_layout(&profile_sheet_default(), &rec);
        let rows: Vec<(&str, &str, &str)> = layout
            .history
            .iter()
            .map(|r| (r.year.as_str(), r.month.as_str(), r.text.as_str()))
            .collect();
        assert_eq!(
            rows,
            vec![
                ("2014", "", "プロデューサーに就任"),
                ("2016", "1", "初参加　公演p000"),
                ("2016", "1", "10公演目　公演p009"),
                ("2016", "1", "30公演目　公演p029"),
                ("2016", "1", "最近の現場　公演p030"),
                ("", "", "以上"),
            ]
        );
        // 最近の現場が節目と同じ公演なら節目だけ。
        rec.attended = many_shows(30);
        let layout = profile_sheet_layout(&profile_sheet_default(), &rec);
        assert!(!layout
            .history
            .iter()
            .any(|r| r.kind == ProfileHistoryKind::RecentShow));
        assert!(texts(&layout.history).contains(&"30公演目　公演p029"));
    }

    #[test]
    fn history_caps_keep_the_important_rows() {
        let mut rec = record();
        let mut shows = many_shows(500);
        // ブランドを散らして、ブランドごとのはじめてを 3 つ作る。
        shows[5].brand_id = Some("ml".into());
        shows[7].brand_id = Some("cg".into());
        shows[9].brand_id = Some("sm".into());
        rec.attended = shows;
        let portrait = profile_sheet_layout(&profile_sheet_default(), &rec);
        // 8 行 + 以上。就任・はじめて・ブランド 3 つが残り、節目は大きい方から 3 つ
        // (最近の現場は 500 公演目と同じ公演なので節目だけ)。
        assert_eq!(portrait.history.len(), 9);
        let kinds: Vec<ProfileHistoryKind> = portrait.history.iter().map(|r| r.kind).collect();
        assert_eq!(
            kinds
                .iter()
                .filter(|k| **k == ProfileHistoryKind::BrandFirst)
                .count(),
            3
        );
        let ms: Vec<&str> = portrait
            .history
            .iter()
            .filter(|r| r.kind == ProfileHistoryKind::Milestone)
            .map(|r| r.text.as_str())
            .collect();
        assert_eq!(
            ms,
            vec![
                "300公演目　公演p299",
                "400公演目　公演p399",
                "500公演目　公演p499"
            ]
        );
        assert!(!kinds.contains(&ProfileHistoryKind::RecentShow));
        let story = profile_sheet_layout(
            &ProfileSheet {
                size: ProfileSheetSize::Story,
                ..profile_sheet_default()
            },
            &rec,
        );
        assert_eq!(story.history.len(), 14);
        // 年の順に並ぶ。
        let years: Vec<&str> = story
            .history
            .iter()
            .map(|r| r.year.as_str())
            .filter(|y| !y.is_empty())
            .collect();
        let mut sorted = years.clone();
        sorted.sort();
        assert_eq!(years, sorted);
    }

    #[test]
    fn sections_hold_songs_memories_next_records_and_message() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &record());
        let get = |slot: ProfileSlot| layout.sections.iter().find(|s| s.slot == slot).unwrap();
        let songs: Vec<&str> = get(ProfileSlot::Songs)
            .entries
            .iter()
            .map(|e| e.text.as_str())
            .collect();
        assert_eq!(songs, vec!["曲2", "曲1"]);
        // 思い出の公演の既定は、お気に入りのライブの公演を新しい順に。
        let memories: Vec<(&str, &str, &str)> = get(ProfileSlot::Memories)
            .entries
            .iter()
            .map(|e| (e.label.as_str(), e.text.as_str(), e.note.as_str()))
            .collect();
        assert_eq!(
            memories,
            vec![
                ("2026年9月14日", "公演c", "会場c"),
                ("2025年3月1日", "公演b", "会場b"),
            ]
        );
        let next: Vec<(&str, &str)> = get(ProfileSlot::NextShow)
            .entries
            .iter()
            .map(|e| (e.label.as_str(), e.text.as_str()))
            .collect();
        assert_eq!(
            next,
            vec![("2026年11月3日", "公演n"), ("2026年12月24日", "公演m")]
        );
        let records: Vec<(&str, &str)> = get(ProfileSlot::Records)
            .entries
            .iter()
            .map(|e| (e.label.as_str(), e.text.as_str()))
            .collect();
        assert_eq!(
            records,
            vec![("参加公演", "4公演"), ("回収曲", "523曲"), ("円盤", "12枚")]
        );
        assert_eq!(
            get(ProfileSlot::Message).entries[0].text,
            "よろしくお願いします"
        );
    }

    #[test]
    fn memories_can_be_chosen_toggled_and_moved() {
        let rec = record();
        let sheet = profile_sheet_default();
        let picks = profile_memory_picks(&sheet, &rec);
        assert!(!picks.chosen_by_hand);
        let ids = |v: &[ProfileShowInput]| v.iter().map(|s| s.show_id.clone()).collect::<Vec<_>>();
        assert_eq!(ids(&picks.picked), vec!["c", "b"]);
        // 候補は参加した公演 (これからの公演は入らない) を新しい順に。
        assert_eq!(ids(&picks.candidates), vec!["d", "c", "b", "a"]);
        // 既定の並びから足す。
        let sheet = profile_toggle_memory(&sheet, &rec, "a");
        assert_eq!(
            sheet.memories,
            Some(vec!["c".into(), "b".into(), "a".into()])
        );
        let sheet = profile_toggle_memory(&sheet, &rec, "c");
        assert_eq!(sheet.memories, Some(vec!["b".into(), "a".into()]));
        // これからの公演・知らない公演は足さない。
        let same = profile_toggle_memory(&sheet, &rec, "n");
        assert_eq!(same.memories, sheet.memories);
        let sheet = profile_move_memory(&sheet, &rec, 1, 0);
        assert_eq!(sheet.memories, Some(vec!["a".into(), "b".into()]));
        assert!(profile_memory_picks(&sheet, &rec).chosen_by_hand);
        // 全部外すと欄は出ないが、選ぶ画面の行は残る。
        let sheet = profile_toggle_memory(&profile_toggle_memory(&sheet, &rec, "a"), &rec, "b");
        assert_eq!(sheet.memories, Some(Vec::new()));
        let layout = profile_sheet_layout(&sheet, &rec);
        assert!(!layout
            .sections
            .iter()
            .any(|s| s.slot == ProfileSlot::Memories));
        assert!(profile_auto_field_rows(&sheet, &rec)
            .iter()
            .any(|r| r.field == ProfileAutoField::Memories && r.pickable));
    }

    #[test]
    fn memories_are_capped() {
        let mut rec = record();
        rec.attended = many_shows(8);
        let mut sheet = profile_sheet_default();
        for i in 0..8 {
            sheet = profile_toggle_memory(&sheet, &rec, &format!("p{i:03}"));
        }
        assert_eq!(sheet.memories.as_ref().unwrap().len(), MAX_MEMORIES);
        assert!(profile_memory_picks(&sheet, &rec).full);
    }

    #[test]
    fn sparse_records_leave_no_empty_sections() {
        let layout = profile_sheet_layout(&profile_sheet_default(), &sparse_record());
        let slots: Vec<ProfileSlot> = layout.sections.iter().map(|s| s.slot).collect();
        assert_eq!(slots, vec![ProfileSlot::Records]);
        assert!(layout.oshi_groups.is_empty());
        assert_eq!(texts(&layout.history), vec!["初参加　公演x", "以上"]);
        assert!(layout.since_label.is_none());
        assert_eq!(layout.density, ProfileSheetDensity::Regular);
    }

    #[test]
    fn rows_are_grouped_and_mark_where_they_come_from() {
        let groups = profile_auto_field_groups(&profile_sheet_default(), &record());
        let titles: Vec<&str> = groups.iter().map(|g| g.title.as_str()).collect();
        assert_eq!(titles, vec!["プロフィール", "P歴の表", "欄", "連絡先"]);
        let rows = profile_auto_field_rows(&profile_sheet_default(), &record());
        let find = |f: ProfileAutoField| rows.iter().find(|r| r.field == f).unwrap();
        assert!(find(ProfileAutoField::Since).from_card);
        assert!(find(ProfileAutoField::Message).from_card);
        assert!(!find(ProfileAutoField::Qr).shown);
        assert_eq!(find(ProfileAutoField::Counts).value, "4公演・523曲・12枚");
        assert_eq!(
            find(ProfileAutoField::Oshi).value,
            "アイドルharuka・アイドルshizuka・アイドルchihaya"
        );
        assert_eq!(
            find(ProfileAutoField::BrandFirsts).value,
            "シンデレラ・ミリオン"
        );
        // 4 公演では節目が無いので並ばない。
        assert!(!rows.iter().any(|r| r.field == ProfileAutoField::Milestones));
        let sparse = profile_auto_field_groups(&profile_sheet_default(), &sparse_record());
        let titles: Vec<&str> = sparse.iter().map(|g| g.title.as_str()).collect();
        assert_eq!(titles, vec!["プロフィール", "P歴の表", "欄"]);
    }

    #[test]
    fn hidden_fields_drop_their_rows_and_toggle_round_trips() {
        let mut sheet = profile_sheet_default();
        for f in [
            ProfileAutoField::Shows,
            ProfileAutoField::BrandFirsts,
            ProfileAutoField::Songs,
            ProfileAutoField::Message,
        ] {
            sheet = profile_toggle_field(&sheet, f);
        }
        let layout = profile_sheet_layout(&sheet, &record());
        assert_eq!(texts(&layout.history), vec!["プロデューサーに就任", "以上"]);
        assert!(!layout
            .sections
            .iter()
            .any(|s| matches!(s.slot, ProfileSlot::Songs | ProfileSlot::Message)));
        let back = [
            ProfileAutoField::Message,
            ProfileAutoField::Songs,
            ProfileAutoField::BrandFirsts,
            ProfileAutoField::Shows,
        ]
        .into_iter()
        .fold(sheet, |s, f| profile_toggle_field(&s, f));
        assert_eq!(back, profile_sheet_default());
    }

    #[test]
    fn density_tightens_with_more_content_and_relaxes_on_story() {
        let mut rec = record();
        rec.oshi = (0..24)
            .map(|i| oshi(&format!("i{i}"), if i % 2 == 0 { "765" } else { "ml" }))
            .collect();
        rec.attended = many_shows(120);
        rec.favorite_songs = (0..5)
            .map(|i| song(&format!("s{i}"), "2026-01-01T00:00:00Z"))
            .collect();
        let mut sheet = profile_sheet_default();
        for i in 0..5 {
            sheet = profile_toggle_memory(&sheet, &rec, &format!("p{i:03}"));
        }
        let portrait = profile_sheet_layout(&sheet, &rec);
        assert_ne!(portrait.density, ProfileSheetDensity::Regular);
        let story = profile_sheet_layout(
            &ProfileSheet {
                size: ProfileSheetSize::Story,
                ..sheet
            },
            &rec,
        );
        assert_ne!(story.density, ProfileSheetDensity::Tight);
    }

    #[test]
    fn info_lists_have_unique_keys() {
        let keys: HashSet<String> = profile_auto_fields().into_iter().map(|f| f.key).collect();
        assert_eq!(keys.len(), ALL_AUTO_FIELDS.len());
        let sizes: HashSet<String> = profile_sheet_sizes().into_iter().map(|s| s.key).collect();
        assert_eq!(sizes.len(), 2);
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
        // 未設定: 担当 (765, ml) のブランドがメイン、2 公演行った cg が担当。
        let marks = profile_brand_marks(&rec);
        let ids: Vec<(&str, bool)> = marks.iter().map(|b| (b.id.as_str(), b.checked)).collect();
        assert_eq!(ids.len(), 4);
        assert!(ids.iter().all(|(id, _)| *id != "other"));
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
