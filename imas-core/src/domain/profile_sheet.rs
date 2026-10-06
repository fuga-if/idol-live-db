//! プロフィール帳 (SNS に貼る自己紹介の 1 枚絵) の中身・欄の割り当て・行の組み立て。
//!
//! P名刺 (QR で交換する名刺) の続きで、P を「職業」に見立てた事務書類の様式で 1 枚にする。
//! 様式は 2 つ:
//!
//! - **履歴書** (既定): 氏名・ふりがな・証明写真・P歴 (就任の年)・「学歴・職歴」を読み替えた
//!   P歴の表 (就任 / はじめての参加 / 最近の現場 / 次の現場 / 以上)・免許・資格 (記録の数)・
//!   志望の動機・趣味・特技・本人希望記入欄。
//! - **職務経歴書**: 職務要約・職務経歴 (参加した公演を年ごとの表に)・活かせる経験・知識・スキル・自己PR。
//!
//! 自分で書く欄は「用意した質問」から選んで足す (質問文は書き換えられる)。どの質問がどの様式の
//! どの欄に入るか・欄の並び・行の組み立て・上限・文字の詰め方 (`ProfileSheetDensity`) はここで決め、
//! 端末 (iOS / Android) はこの結果を描くだけにする。
//!
//! 中身は端末ローカル (自分の P名刺の行に JSON で持つ。`profile_sheet_to_json`)。
//! 名前・写真・書体・リンク・自分の QR は P名刺のものを使う。

use chrono::{Datelike, NaiveDate};

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

/// 用意した質問。並び順は「質問を足す」の一覧の順。保存のキーは変えない。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileQuestion {
    /// Pになったきっかけ。
    Trigger,
    /// 担当のここが好き。
    OshiLove,
    /// いちばん思い出のライブ。
    BestLive,
    /// 好きなコール。
    FavoriteCall,
    /// 遠征の思い出。
    Expedition,
    /// 現場での目印。
    Landmark,
    /// ひとこと。
    Message,
    /// 自分で質問を書く欄 (何度でも足せる)。
    Free,
}

/// アプリの記録から自動で埋まる欄 (外せる)。保存のキーは変えない。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ProfileAutoField {
    /// P名刺の写真 (証明写真の欄)。
    Photo,
    /// 担当 (押印欄の判子と担当の行)。
    Oshi,
    /// ブランドのチェック欄。
    Brands,
    /// P歴 (就任の年)。
    Since,
    /// 参加公演数・回収曲数。
    Counts,
    /// はじめて参加したライブ・最近の現場・職務経歴の表。
    Shows,
    /// 次の現場。
    NextShow,
    /// 好きな曲。
    Songs,
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

/// 自分で書く欄 1 つ。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAnswer {
    pub question: ProfileQuestion,
    /// 質問文。空なら用意した質問文 (`ProfileQuestionInfo::prompt`)。
    pub prompt: String,
    pub text: String,
}

/// プロフィール帳の中身 (端末に保存するもの)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheet {
    pub style: ProfileSheetStyle,
    pub size: ProfileSheetSize,
    /// 氏名のふりがな (履歴書の欄)。
    pub furigana: String,
    /// 自分で書く欄 (並べた順)。
    pub answers: Vec<ProfileAnswer>,
    /// 外した自動の欄。
    pub hidden: Vec<ProfileAutoField>,
    /// 好きな曲 (お気に入りの曲から、並べた順)。
    pub favorite_song_ids: Vec<String>,
    /// 対応範囲で自分で丸を付けたブランド (記録からは付かないもの)。
    pub brand_on: Vec<String>,
    /// 対応範囲で自分で丸を外したブランド (記録からは付くもの)。
    pub brand_off: Vec<String>,
}

#[derive(uniffi::Record, Clone, Copy, Debug, PartialEq, Eq)]
pub struct ProfileSheetLimits {
    pub max_answers: u32,
    pub max_answer_chars: u32,
    pub max_prompt_chars: u32,
    pub max_furigana_chars: u32,
    pub max_songs: u32,
}

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProfileSheetError {
    TooManyAnswers,
    AnswerTooLong,
    PromptTooLong,
    FuriganaTooLong,
    TooManySongs,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileQuestionInfo {
    pub question: ProfileQuestion,
    pub key: String,
    /// 用意した質問文 (「Pになったきっかけ」)。
    pub prompt: String,
    /// 答えの欄の書き方の例。
    pub placeholder: String,
}

#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileAutoFieldInfo {
    pub field: ProfileAutoField,
    pub key: String,
    /// 編集画面の名前 (「参加公演数・回収曲数」)。
    pub label: String,
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

/// プロフィール帳の材料。名前・P歴・リンクは P名刺から、ほかはアプリの記録から。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileSheetRecord {
    /// 今日 (`YYYY-MM-DD`、JST)。
    pub today: String,
    pub name: String,
    pub since_year: Option<u16>,
    /// 担当の所属ブランド (チェック欄に印を付ける)。
    pub oshi_brand_ids: Vec<String>,
    pub attended: Vec<ProfileShowInput>,
    pub song_count: u32,
    pub brands: Vec<ProfileBrandInput>,
    /// 好きな曲 (端末が `favorite_song_ids` の順に引いたもの。引けない曲は入れない)。
    pub favorite_songs: Vec<ProfileSongInput>,
    /// 連絡先に出すリンク (`card_link_view` の display)。
    pub links: Vec<String>,
}

// --- 組み立てた結果 (端末が描く) ---

#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum ProfileHistoryKind {
    Since,
    FirstShow,
    RecentShow,
    NextShow,
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

/// 対応範囲のブランド 1 つ。刷ってあるブランドの名前に、対応しているものだけ手描きの丸を付ける。
/// 丸の形の揺らぎは id から決まる (書き出すたびに形が変わらない)。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ProfileBrandCheck {
    pub id: String,
    pub label: String,
    pub color: Option<String>,
    /// 丸を付けるか。
    pub checked: bool,
    /// 記録 (担当・参加した公演) から付く丸か。編集画面で「記録から」と添える。
    pub from_record: bool,
    /// 丸の傾き (度、-9〜9)。
    pub tilt_degrees: f64,
    /// 丸の横の伸び (1.0 で名前の幅どおり、0.92〜1.12)。
    pub stretch: f64,
    /// 線の書き始めの角度 (度、0〜359)。書き終わりは少し行き過ぎて重なる。
    pub start_degrees: f64,
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

/// 欄の中の 1 項目 (質問と答え、または自動の項目)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ProfileEntry {
    pub label: String,
    pub text: String,
    /// アプリの記録から入った項目 (答えの書体でなく印字で出す)。
    pub is_auto: bool,
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
    pub style: ProfileSheetStyle,
    pub size: ProfileSheetSize,
    /// 「履歴書」。
    pub title: String,
    /// 「RÉSUMÉ」。
    pub imprint: String,
    /// 「2026年10月6日現在」。
    pub as_of: String,
    pub name: String,
    pub furigana: String,
    pub show_photo: bool,
    pub show_oshi: bool,
    pub show_qr: bool,
    /// 「2014年 就任 · P歴12年」。外したら None。
    pub since_label: Option<String>,
    /// 連絡先 (外したら空)。
    pub contacts: Vec<String>,
    /// 対応範囲の欄の名前 (「対応範囲」)。
    pub brands_title: String,
    /// 対応範囲のブランド (外したら空)。
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

const MAX_ANSWERS: u32 = 8;
const MAX_ANSWER_CHARS: u32 = 80;
const MAX_PROMPT_CHARS: u32 = 16;
const MAX_FURIGANA_CHARS: u32 = 24;
const MAX_SONGS: u32 = 3;

const ALL_QUESTIONS: [ProfileQuestion; 8] = [
    ProfileQuestion::Trigger,
    ProfileQuestion::OshiLove,
    ProfileQuestion::BestLive,
    ProfileQuestion::FavoriteCall,
    ProfileQuestion::Expedition,
    ProfileQuestion::Landmark,
    ProfileQuestion::Message,
    ProfileQuestion::Free,
];

const ALL_AUTO_FIELDS: [ProfileAutoField; 10] = [
    ProfileAutoField::Photo,
    ProfileAutoField::Oshi,
    ProfileAutoField::Brands,
    ProfileAutoField::Since,
    ProfileAutoField::Counts,
    ProfileAutoField::Shows,
    ProfileAutoField::NextShow,
    ProfileAutoField::Songs,
    ProfileAutoField::Links,
    ProfileAutoField::Qr,
];

const ALL_STYLES: [ProfileSheetStyle; 2] = [ProfileSheetStyle::Resume, ProfileSheetStyle::Career];
const ALL_SIZES: [ProfileSheetSize; 2] = [ProfileSheetSize::Portrait, ProfileSheetSize::Story];

pub fn profile_sheet_limits() -> ProfileSheetLimits {
    ProfileSheetLimits {
        max_answers: MAX_ANSWERS,
        max_answer_chars: MAX_ANSWER_CHARS,
        max_prompt_chars: MAX_PROMPT_CHARS,
        max_furigana_chars: MAX_FURIGANA_CHARS,
        max_songs: MAX_SONGS,
    }
}

pub fn profile_question_info(question: ProfileQuestion) -> ProfileQuestionInfo {
    let (key, prompt, placeholder) = match question {
        ProfileQuestion::Trigger => (
            "trigger",
            "Pになったきっかけ",
            "アニメで見たステージに心をつかまれて",
        ),
        ProfileQuestion::OshiLove => (
            "oshi_love",
            "担当のここが好き",
            "まっすぐなところ。歌声に背中を押される",
        ),
        ProfileQuestion::BestLive => (
            "best_live",
            "いちばん思い出のライブ",
            "はじめての現地。1 曲目で泣いた",
        ),
        ProfileQuestion::FavoriteCall => ("favorite_call", "好きなコール", "サビ前のクラップ"),
        ProfileQuestion::Expedition => ("expedition", "遠征の思い出", "夜行バスで行った西武ドーム"),
        ProfileQuestion::Landmark => (
            "landmark",
            "現場での目印",
            "担当色のタオルを首に巻いています",
        ),
        ProfileQuestion::Message => (
            "message",
            "ひとこと",
            "同僚募集中です。気軽に声をかけてください",
        ),
        ProfileQuestion::Free => ("free", "自由記入", "質問も答えも自由に書けます"),
    };
    ProfileQuestionInfo {
        question,
        key: key.into(),
        prompt: prompt.into(),
        placeholder: placeholder.into(),
    }
}

/// 用意した質問の一覧 (「質問を足す」の順)。
pub fn profile_questions() -> Vec<ProfileQuestionInfo> {
    ALL_QUESTIONS
        .into_iter()
        .map(profile_question_info)
        .collect()
}

/// まだ足していない質問 (自由記入はいつでも足せる)。上限まで足していたら空。
pub fn profile_addable_questions(sheet: &ProfileSheet) -> Vec<ProfileQuestionInfo> {
    if sheet.answers.len() >= MAX_ANSWERS as usize {
        return Vec::new();
    }
    ALL_QUESTIONS
        .into_iter()
        .filter(|q| *q == ProfileQuestion::Free || !sheet.answers.iter().any(|a| a.question == *q))
        .map(profile_question_info)
        .collect()
}

pub fn profile_auto_field_info(field: ProfileAutoField) -> ProfileAutoFieldInfo {
    let (key, label) = match field {
        ProfileAutoField::Photo => ("photo", "写真"),
        ProfileAutoField::Oshi => ("oshi", "担当"),
        ProfileAutoField::Brands => ("brands", "ブランド"),
        ProfileAutoField::Since => ("since", "P歴"),
        ProfileAutoField::Counts => ("counts", "参加公演数・回収曲数"),
        ProfileAutoField::Shows => ("shows", "はじめて参加したライブ・参加の経歴"),
        ProfileAutoField::NextShow => ("next_show", "次の現場"),
        ProfileAutoField::Songs => ("songs", "好きな曲"),
        ProfileAutoField::Links => ("links", "リンク"),
        ProfileAutoField::Qr => ("qr", "自分の QR"),
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

/// はじめて開いたときの中身。履歴書・4:5、質問は「きっかけ・担当のここが好き・ひとこと」、
/// 自分の QR だけ外しておく (載せるかは本人が決める)。
pub fn profile_sheet_default() -> ProfileSheet {
    ProfileSheet {
        style: ProfileSheetStyle::default(),
        size: ProfileSheetSize::default(),
        furigana: String::new(),
        answers: [
            ProfileQuestion::Trigger,
            ProfileQuestion::OshiLove,
            ProfileQuestion::Message,
        ]
        .into_iter()
        .map(|question| ProfileAnswer {
            question,
            prompt: String::new(),
            text: String::new(),
        })
        .collect(),
        hidden: vec![ProfileAutoField::Qr],
        favorite_song_ids: Vec::new(),
        brand_on: Vec::new(),
        brand_off: Vec::new(),
    }
}

pub fn validate_profile_sheet(sheet: &ProfileSheet) -> Option<ProfileSheetError> {
    if sheet.answers.len() > MAX_ANSWERS as usize {
        return Some(ProfileSheetError::TooManyAnswers);
    }
    if sheet
        .answers
        .iter()
        .any(|a| char_len(a.text.trim()) > MAX_ANSWER_CHARS as usize)
    {
        return Some(ProfileSheetError::AnswerTooLong);
    }
    if sheet
        .answers
        .iter()
        .any(|a| char_len(a.prompt.trim()) > MAX_PROMPT_CHARS as usize)
    {
        return Some(ProfileSheetError::PromptTooLong);
    }
    if char_len(sheet.furigana.trim()) > MAX_FURIGANA_CHARS as usize {
        return Some(ProfileSheetError::FuriganaTooLong);
    }
    if sheet.favorite_song_ids.len() > MAX_SONGS as usize {
        return Some(ProfileSheetError::TooManySongs);
    }
    None
}

pub fn profile_sheet_error_message(error: ProfileSheetError) -> String {
    match error {
        ProfileSheetError::TooManyAnswers => format!("書く欄は{MAX_ANSWERS}つまでです"),
        ProfileSheetError::AnswerTooLong => format!("答えは{MAX_ANSWER_CHARS}文字までです"),
        ProfileSheetError::PromptTooLong => format!("質問は{MAX_PROMPT_CHARS}文字までです"),
        ProfileSheetError::FuriganaTooLong => {
            format!("ふりがなは{MAX_FURIGANA_CHARS}文字までです")
        }
        ProfileSheetError::TooManySongs => format!("好きな曲は{MAX_SONGS}曲までです"),
    }
}

/// 質問がどの欄に入るか。
pub fn profile_question_slot(style: ProfileSheetStyle, question: ProfileQuestion) -> ProfileSlot {
    use ProfileQuestion as Q;
    use ProfileSlot as S;
    match style {
        ProfileSheetStyle::Resume => match question {
            Q::Trigger | Q::OshiLove | Q::BestLive => S::Motivation,
            Q::FavoriteCall | Q::Expedition => S::Hobby,
            Q::Landmark | Q::Message | Q::Free => S::Wish,
        },
        ProfileSheetStyle::Career => match question {
            Q::Message => S::Summary,
            Q::FavoriteCall | Q::Expedition | Q::Landmark => S::Skills,
            Q::Trigger | Q::OshiLove | Q::BestLive | Q::Free => S::SelfPr,
        },
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

fn question_from_key(key: &str) -> Option<ProfileQuestion> {
    ALL_QUESTIONS
        .into_iter()
        .find(|q| profile_question_info(*q).key == key)
}

fn auto_field_from_key(key: &str) -> Option<ProfileAutoField> {
    ALL_AUTO_FIELDS
        .into_iter()
        .find(|f| profile_auto_field_info(*f).key == key)
}

#[derive(serde::Serialize, serde::Deserialize, Default)]
#[serde(default)]
struct SheetDto {
    style: String,
    size: String,
    furigana: String,
    answers: Vec<AnswerDto>,
    hidden: Vec<String>,
    songs: Vec<String>,
    #[serde(rename = "brandOn")]
    brand_on: Vec<String>,
    #[serde(rename = "brandOff")]
    brand_off: Vec<String>,
}

#[derive(serde::Serialize, serde::Deserialize, Default)]
#[serde(default)]
struct AnswerDto {
    q: String,
    prompt: String,
    text: String,
}

/// 保存の形 (キーは英字。並べた順を保つ)。
pub fn profile_sheet_to_json(sheet: &ProfileSheet) -> String {
    let dto = SheetDto {
        style: profile_sheet_style_info(sheet.style).key,
        size: profile_sheet_size_info(sheet.size).key,
        furigana: sheet.furigana.clone(),
        answers: sheet
            .answers
            .iter()
            .map(|a| AnswerDto {
                q: profile_question_info(a.question).key,
                prompt: a.prompt.clone(),
                text: a.text.clone(),
            })
            .collect(),
        hidden: ALL_AUTO_FIELDS
            .into_iter()
            .filter(|f| sheet.hidden.contains(f))
            .map(|f| profile_auto_field_info(f).key)
            .collect(),
        songs: sheet.favorite_song_ids.clone(),
        brand_on: sheet.brand_on.clone(),
        brand_off: sheet.brand_off.clone(),
    };
    serde_json::to_string(&dto).unwrap_or_default()
}

/// 保存の形から戻す。空・壊れた JSON は既定の中身。知らない質問・欄のキー (新しい版が足したもの)
/// は捨て、上限を超えた分は落とす (読めない 1 項目のために全部を失わない)。
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
    let answers = dto
        .answers
        .into_iter()
        .filter_map(|a| {
            Some(ProfileAnswer {
                question: question_from_key(&a.q)?,
                prompt: a.prompt,
                text: a.text,
            })
        })
        .take(MAX_ANSWERS as usize)
        .collect();
    let mut hidden: Vec<ProfileAutoField> = Vec::new();
    for f in dto.hidden.iter().filter_map(|k| auto_field_from_key(k)) {
        if !hidden.contains(&f) {
            hidden.push(f);
        }
    }
    let mut songs: Vec<String> = Vec::new();
    for id in dto.songs {
        if !id.is_empty() && !songs.contains(&id) {
            songs.push(id);
        }
    }
    songs.truncate(MAX_SONGS as usize);
    ProfileSheet {
        style,
        size,
        furigana: dto.furigana,
        answers,
        hidden,
        favorite_song_ids: songs,
        brand_on: unique_ids(dto.brand_on),
        brand_off: unique_ids(dto.brand_off),
    }
}

// ---------------------------------------------------------------------------
// 組み立て
// ---------------------------------------------------------------------------

/// 大きさごとの表の行数の上限 (履歴書の P歴は「以上」を除く、職務経歴書は公演の行)。
fn row_caps(size: ProfileSheetSize) -> (usize, usize) {
    match size {
        ProfileSheetSize::Portrait => (4, 5),
        ProfileSheetSize::Story => (5, 12),
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

pub fn profile_sheet_layout(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> ProfileSheetLayout {
    let shows = |f: ProfileAutoField| !sheet.hidden.contains(&f);
    let today = parse_date(&record.today);
    let style = sheet.style;
    let style_info = profile_sheet_style_info(style);

    // 参加を付けた公演を、行った公演 (日付の昇順) と次の現場に分ける (P名刺と同じ分け方)。
    let mut seen = std::collections::HashSet::new();
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
    let next = next.filter(|_| shows(ProfileAutoField::NextShow));

    let since_label = record
        .since_year
        .filter(|_| shows(ProfileAutoField::Since))
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

    let brands = if shows(ProfileAutoField::Brands) {
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
            if let Some(y) = record.since_year.filter(|_| shows(ProfileAutoField::Since)) {
                history.push(ProfileHistoryRow {
                    year: y.to_string(),
                    month: String::new(),
                    text: "プロデューサーに就任".into(),
                    kind: ProfileHistoryKind::Since,
                });
            }
            if shows(ProfileAutoField::Shows) {
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
            if let Some((d, s)) = next {
                history.push(history_row(
                    d,
                    format!("次の現場　{}（予定）", s.title),
                    ProfileHistoryKind::NextShow,
                ));
            }
            // 上限を超えたら「次の現場」と「就任」を残し、間の行から落とす。
            while history.len() > history_cap {
                let drop = history
                    .iter()
                    .rposition(|r| {
                        matches!(
                            r.kind,
                            ProfileHistoryKind::RecentShow | ProfileHistoryKind::FirstShow
                        )
                    })
                    .unwrap_or(history.len() - 1);
                history.remove(drop);
            }
            if !history.is_empty() {
                history.push(ProfileHistoryRow {
                    year: String::new(),
                    month: String::new(),
                    text: "以上".into(),
                    kind: ProfileHistoryKind::Closing,
                });
            }
            if shows(ProfileAutoField::Counts) {
                if let Some(t) = today {
                    licenses.push(history_row(
                        t,
                        format!("参加公演 {}公演 達成", past.len()),
                        ProfileHistoryKind::Count,
                    ));
                    licenses.push(history_row(
                        t,
                        format!("回収曲 {}曲 達成", record.song_count),
                        ProfileHistoryKind::Count,
                    ));
                }
            }
        }
        ProfileSheetStyle::Career => {
            if shows(ProfileAutoField::Shows) || next.is_some() {
                // 新しい公演から。次の現場はその年の頭に「予定」で置く。
                let mut rows: Vec<(NaiveDate, ProfileCareerRow)> = Vec::new();
                if let Some((d, s)) = next {
                    rows.push((d, career_row(d, s, brand_label(&s.brand_id), true)));
                }
                let past_rows: Vec<&(NaiveDate, &ProfileShowInput)> =
                    if shows(ProfileAutoField::Shows) {
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
                            count_label: format!("{count}公演"),
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

    // 欄。自動の項目を先に置き、質問の答えを並べた順に続ける。答えの空の質問は出さない。
    let mut sections: Vec<ProfileSection> = Vec::new();
    for slot in slots(style) {
        let mut entries: Vec<ProfileEntry> = Vec::new();
        match slot {
            ProfileSlot::Summary => {
                if let Some(text) = career_summary(record, past.len(), shows) {
                    entries.push(auto_entry("", text));
                }
            }
            ProfileSlot::Hobby | ProfileSlot::Skills
                if shows(ProfileAutoField::Songs) && !record.favorite_songs.is_empty() =>
            {
                let titles: Vec<String> = record
                    .favorite_songs
                    .iter()
                    .take(MAX_SONGS as usize)
                    .map(|s| format!("「{}」", s.title))
                    .collect();
                entries.push(auto_entry("好きな曲", titles.join("")));
            }
            _ => {}
        }
        for a in &sheet.answers {
            let text = a.text.trim();
            if text.is_empty() || profile_question_slot(style, a.question) != slot {
                continue;
            }
            let prompt = a.prompt.trim();
            entries.push(ProfileEntry {
                label: if prompt.is_empty() {
                    profile_question_info(a.question).prompt
                } else {
                    prompt.to_string()
                },
                text: text.to_string(),
                is_auto: false,
            });
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

    // 中身の量の見積もり: 欄の項目 (見出し 1 行 + 本文の折り返し) と表の行。
    let entry_lines: u32 = sections
        .iter()
        .map(|s| {
            1 + s
                .entries
                .iter()
                .map(|e| {
                    let chars = char_len(&e.label) + char_len(&e.text) + 1;
                    chars.div_ceil(CHARS_PER_LINE).max(1) as u32
                })
                .sum::<u32>()
        })
        .sum();
    let table_lines = (history.len() + licenses.len()) as u32
        + career.iter().map(|y| 1 + y.rows.len() as u32).sum::<u32>();
    let load = entry_lines + table_lines;
    let (regular, compact) = density_caps(sheet.size);
    let density = if load <= regular {
        ProfileSheetDensity::Regular
    } else if load <= compact {
        ProfileSheetDensity::Compact
    } else {
        ProfileSheetDensity::Tight
    };

    ProfileSheetLayout {
        style,
        size: sheet.size,
        title: style_info.label,
        imprint: match style {
            ProfileSheetStyle::Resume => "RÉSUMÉ".into(),
            ProfileSheetStyle::Career => "CAREER HISTORY".into(),
        },
        as_of: today
            .map(|d| format!("{}年{}月{}日現在", d.year(), d.month(), d.day()))
            .unwrap_or_default(),
        name: record.name.trim().to_string(),
        furigana: sheet.furigana.trim().to_string(),
        show_photo: shows(ProfileAutoField::Photo),
        show_oshi: shows(ProfileAutoField::Oshi),
        show_qr: shows(ProfileAutoField::Qr),
        since_label,
        contacts: if shows(ProfileAutoField::Links) {
            record.links.clone()
        } else {
            Vec::new()
        },
        brands_title: "対応範囲".into(),
        brands,
        history,
        licenses,
        career,
        career_more,
        sections,
        density,
    }
}

/// 職務要約の 1 文 (P歴と記録の数から)。
fn career_summary(
    record: &ProfileSheetRecord,
    show_count: usize,
    shows: impl Fn(ProfileAutoField) -> bool,
) -> Option<String> {
    let since = record.since_year.filter(|_| shows(ProfileAutoField::Since));
    let counts = shows(ProfileAutoField::Counts);
    match (since, counts) {
        (Some(y), true) => Some(format!(
            "{y}年よりプロデューサーとして活動。これまでに{show_count}公演に参加し、{}曲を回収。",
            record.song_count
        )),
        (Some(y), false) => Some(format!("{y}年よりプロデューサーとして活動。")),
        (None, true) => Some(format!(
            "これまでに{show_count}公演に参加し、{}曲を回収。",
            record.song_count
        )),
        (None, false) => None,
    }
}

fn auto_entry(label: &str, text: String) -> ProfileEntry {
    ProfileEntry {
        label: label.into(),
        text,
        is_auto: true,
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
// 対応範囲 (ブランドに丸を付ける)
// ---------------------------------------------------------------------------

/// 対応範囲に並べないブランド (その他は「対応している」と言える範囲ではない)。
const BRANDS_NOT_LISTED: [&str; 1] = ["other"];

/// 記録から丸が付くブランド: 担当の所属と、今日までに参加した公演のライブのブランド。
fn record_brand_ids(record: &ProfileSheetRecord) -> std::collections::HashSet<String> {
    let today = parse_date(&record.today);
    let mut ids: std::collections::HashSet<String> =
        record.oshi_brand_ids.iter().cloned().collect();
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

/// 対応範囲の並び (ブランドの並び順、その他を除く) と丸。丸は記録から付け、自分で付け外しした分を重ねる。
pub fn profile_brand_marks(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
) -> Vec<ProfileBrandCheck> {
    let from_record = record_brand_ids(record);
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
        .into_iter()
        .map(|b| {
            let auto = from_record.contains(&b.id);
            let checked = if auto {
                !sheet.brand_off.contains(&b.id)
            } else {
                sheet.brand_on.contains(&b.id)
            };
            let h = fnv1a(&b.id);
            ProfileBrandCheck {
                id: b.id.clone(),
                label: b.label.clone(),
                color: b.color.clone(),
                checked,
                from_record: auto,
                tilt_degrees: f64::from(h % 19) - 9.0,
                stretch: 0.92 + f64::from((h >> 8) % 21) / 100.0,
                start_degrees: f64::from((h >> 16) % 360),
            }
        })
        .collect()
}

/// 対応範囲の丸を 1 つ付け外しした中身。記録から付く丸を外したら `brand_off` に、
/// 記録に無い丸を付けたら `brand_on` に入れる (記録が増えても、自分で決めた分は変えない)。
pub fn profile_toggle_brand(
    sheet: &ProfileSheet,
    record: &ProfileSheetRecord,
    brand_id: &str,
) -> ProfileSheet {
    let mut out = sheet.clone();
    let auto = record_brand_ids(record).contains(brand_id);
    let id = brand_id.to_string();
    if auto {
        if let Some(i) = out.brand_off.iter().position(|b| *b == id) {
            out.brand_off.remove(i);
        } else {
            out.brand_off.push(id);
        }
    } else if let Some(i) = out.brand_on.iter().position(|b| *b == id) {
        out.brand_on.remove(i);
    } else {
        out.brand_on.push(id);
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

    fn record() -> ProfileSheetRecord {
        ProfileSheetRecord {
            today: "2026-10-06".into(),
            name: " ふがP ".into(),
            since_year: Some(2014),
            oshi_brand_ids: vec!["765".into()],
            attended: vec![
                show("b", "2025-03-01", "ml"),
                show("a", "2015-07-18", "765"),
                show("c", "2026-09-14", "cg"),
                show("n", "2026-11-03", "765"),
                show("a", "2015-07-18", "765"),
            ],
            song_count: 523,
            brands: vec![
                ProfileBrandInput {
                    id: "765".into(),
                    label: "765".into(),
                    color: None,
                    sort_order: 1,
                },
                ProfileBrandInput {
                    id: "cg".into(),
                    label: "シンデレラ".into(),
                    color: None,
                    sort_order: 4,
                },
                ProfileBrandInput {
                    id: "ml".into(),
                    label: "ミリオン".into(),
                    color: None,
                    sort_order: 5,
                },
                ProfileBrandInput {
                    id: "sm".into(),
                    label: "SideM".into(),
                    color: None,
                    sort_order: 6,
                },
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
        }
    }

    fn sheet_with(answers: &[(ProfileQuestion, &str)]) -> ProfileSheet {
        ProfileSheet {
            answers: answers
                .iter()
                .map(|(q, t)| ProfileAnswer {
                    question: *q,
                    prompt: String::new(),
                    text: (*t).into(),
                })
                .collect(),
            ..profile_sheet_default()
        }
    }

    #[test]
    fn default_is_resume_with_three_questions_and_qr_hidden() {
        let s = profile_sheet_default();
        assert_eq!(s.style, ProfileSheetStyle::Resume);
        assert_eq!(s.size, ProfileSheetSize::Portrait);
        assert_eq!(s.answers.len(), 3);
        assert_eq!(s.hidden, vec![ProfileAutoField::Qr]);
        assert_eq!(validate_profile_sheet(&s), None);
    }

    #[test]
    fn json_round_trip_keeps_order_and_custom_prompt() {
        let mut s = sheet_with(&[
            (ProfileQuestion::Message, "よろしく"),
            (ProfileQuestion::Free, "答え"),
        ]);
        s.answers[1].prompt = "好きな衣装".into();
        s.style = ProfileSheetStyle::Career;
        s.size = ProfileSheetSize::Story;
        s.furigana = "ふがぴー".into();
        s.hidden = vec![ProfileAutoField::Photo, ProfileAutoField::Qr];
        s.favorite_song_ids = vec!["s1".into(), "s2".into()];
        assert_eq!(profile_sheet_from_json(&profile_sheet_to_json(&s)), s);
    }

    #[test]
    fn broken_or_unknown_json_falls_back_without_losing_the_rest() {
        assert_eq!(profile_sheet_from_json(""), profile_sheet_default());
        assert_eq!(profile_sheet_from_json("{"), profile_sheet_default());
        let s = profile_sheet_from_json(
            r#"{"style":"zine","answers":[{"q":"future","text":"x"},{"q":"message","text":"y"}],
                "hidden":["qr","qr","sparkles"],"songs":["a","a","b","c","d"]}"#,
        );
        assert_eq!(s.style, ProfileSheetStyle::Resume);
        assert_eq!(s.answers.len(), 1);
        assert_eq!(s.answers[0].question, ProfileQuestion::Message);
        assert_eq!(s.hidden, vec![ProfileAutoField::Qr]);
        assert_eq!(s.favorite_song_ids, vec!["a", "b", "c"]);
    }

    #[test]
    fn validation_limits() {
        let mut s = sheet_with(&[(ProfileQuestion::Message, &"あ".repeat(80))]);
        assert_eq!(validate_profile_sheet(&s), None);
        s.answers[0].text.push('あ');
        assert_eq!(
            validate_profile_sheet(&s),
            Some(ProfileSheetError::AnswerTooLong)
        );
        let mut s = sheet_with(&[]);
        s.favorite_song_ids = vec!["1".into(), "2".into(), "3".into(), "4".into()];
        assert_eq!(
            validate_profile_sheet(&s),
            Some(ProfileSheetError::TooManySongs)
        );
        let s = sheet_with(&[(ProfileQuestion::Free, ""); 9]);
        assert_eq!(
            validate_profile_sheet(&s),
            Some(ProfileSheetError::TooManyAnswers)
        );
        assert!(profile_sheet_error_message(ProfileSheetError::AnswerTooLong).contains("80"));
    }

    #[test]
    fn addable_questions_skip_used_ones_but_free_repeats() {
        let s = sheet_with(&[(ProfileQuestion::Trigger, ""), (ProfileQuestion::Free, "")]);
        let keys: Vec<String> = profile_addable_questions(&s)
            .into_iter()
            .map(|q| q.key)
            .collect();
        assert!(!keys.contains(&"trigger".to_string()));
        assert!(keys.contains(&"free".to_string()));
        let full = sheet_with(&[(ProfileQuestion::Free, ""); 8]);
        assert!(profile_addable_questions(&full).is_empty());
    }

    #[test]
    fn resume_history_reads_since_first_recent_next_then_closing() {
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
                ("2026".into(), "9".into(), "最近の現場　公演c".into()),
                ("2026".into(), "11".into(), "次の現場　公演n（予定）".into()),
                ("".into(), "".into(), "以上".into()),
            ]
        );
        // 重複した参加は 1 回に数え、予定は数えない。
        assert_eq!(layout.licenses[0].text, "参加公演 3公演 達成");
        assert_eq!(layout.licenses[1].text, "回収曲 523曲 達成");
        assert!(layout.career.is_empty());
        // 担当のブランドと行ったライブのブランドに印。
        let checked: Vec<&str> = layout
            .brands
            .iter()
            .filter(|b| b.checked)
            .map(|b| b.id.as_str())
            .collect();
        assert_eq!(checked, vec!["765", "cg", "ml"]);
        assert_eq!(layout.contacts, vec!["@fuga_p"]);
        assert!(!layout.show_qr);
    }

    #[test]
    fn resume_slots_place_auto_songs_and_answers() {
        let sheet = sheet_with(&[
            (ProfileQuestion::Message, "よろしく"),
            (ProfileQuestion::Trigger, "アニメ"),
            (ProfileQuestion::FavoriteCall, "  "),
        ]);
        let layout = profile_sheet_layout(&sheet, &record());
        let slots: Vec<ProfileSlot> = layout.sections.iter().map(|s| s.slot).collect();
        assert_eq!(
            slots,
            vec![
                ProfileSlot::Motivation,
                ProfileSlot::Hobby,
                ProfileSlot::Wish
            ]
        );
        assert_eq!(layout.sections[0].entries[0].label, "Pになったきっかけ");
        assert_eq!(layout.sections[1].entries[0].text, "「曲1」「曲2」");
        assert!(layout.sections[1].entries[0].is_auto);
        // 空の答えは出さない (好きなコールは空)。
        assert_eq!(layout.sections[1].entries.len(), 1);
        assert_eq!(layout.sections[2].entries[0].text, "よろしく");
    }

    #[test]
    fn hidden_fields_drop_their_rows() {
        let mut sheet = profile_sheet_default();
        sheet.hidden = vec![
            ProfileAutoField::Since,
            ProfileAutoField::Shows,
            ProfileAutoField::NextShow,
            ProfileAutoField::Counts,
            ProfileAutoField::Brands,
            ProfileAutoField::Links,
            ProfileAutoField::Songs,
        ];
        let layout = profile_sheet_layout(&sheet, &record());
        assert!(layout.history.is_empty(), "行が無ければ「以上」も出さない");
        assert!(layout.licenses.is_empty());
        assert!(layout.brands.is_empty());
        assert!(layout.contacts.is_empty());
        assert!(layout.since_label.is_none());
        assert!(layout.sections.is_empty());
        assert!(layout.show_qr);
    }

    #[test]
    fn career_groups_shows_by_year_newest_first_with_planned_on_top() {
        let mut sheet = sheet_with(&[
            (ProfileQuestion::Message, "同僚募集中"),
            (ProfileQuestion::Landmark, "タオル"),
        ]);
        sheet.style = ProfileSheetStyle::Career;
        let layout = profile_sheet_layout(&sheet, &record());
        assert_eq!(layout.title, "職務経歴書");
        let years: Vec<(&str, &str, usize)> = layout
            .career
            .iter()
            .map(|y| (y.year.as_str(), y.count_label.as_str(), y.rows.len()))
            .collect();
        assert_eq!(
            years,
            vec![
                ("2026年", "1公演", 2),
                ("2025年", "1公演", 1),
                ("2015年", "1公演", 1)
            ]
        );
        assert!(layout.career[0].rows[0].planned);
        assert_eq!(layout.career[0].rows[0].date, "11/3");
        assert_eq!(
            layout.career[0].rows[1].brand.as_deref(),
            Some("シンデレラ")
        );
        assert_eq!(layout.career_more, 0);
        let slots: Vec<ProfileSlot> = layout.sections.iter().map(|s| s.slot).collect();
        assert_eq!(slots, vec![ProfileSlot::Summary, ProfileSlot::Skills]);
        assert!(layout.sections[0].entries[0]
            .text
            .starts_with("2014年よりプロデューサー"));
        assert_eq!(layout.sections[0].entries[1].text, "同僚募集中");
        assert!(layout.history.is_empty());
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
        let mut sheet = profile_sheet_default();
        sheet.style = ProfileSheetStyle::Career;
        let portrait = profile_sheet_layout(&sheet, &rec);
        let shown: usize = portrait.career.iter().map(|y| y.rows.len()).sum();
        assert_eq!(shown, 5);
        assert_eq!(portrait.career_more as usize, rec.attended.len() - 5);
        sheet.size = ProfileSheetSize::Story;
        let story = profile_sheet_layout(&sheet, &rec);
        assert_eq!(story.career.iter().map(|y| y.rows.len()).sum::<usize>(), 12);
    }

    #[test]
    fn density_tightens_as_answers_grow_and_relaxes_on_story() {
        let few = profile_sheet_layout(
            &sheet_with(&[(ProfileQuestion::Message, "よろしく")]),
            &record(),
        );
        assert_eq!(few.density, ProfileSheetDensity::Regular);
        let long = "あ".repeat(80);
        let many: Vec<(ProfileQuestion, &str)> =
            ALL_QUESTIONS.iter().map(|q| (*q, long.as_str())).collect();
        let mut sheet = sheet_with(&many);
        let dense = profile_sheet_layout(&sheet, &record());
        assert_eq!(dense.density, ProfileSheetDensity::Tight);
        sheet.size = ProfileSheetSize::Story;
        let story = profile_sheet_layout(&sheet, &record());
        assert_ne!(story.density, ProfileSheetDensity::Tight);
    }

    #[test]
    fn question_slots_cover_every_question_in_both_styles() {
        for q in ALL_QUESTIONS {
            assert!(slots(ProfileSheetStyle::Resume)
                .contains(&profile_question_slot(ProfileSheetStyle::Resume, q)));
            assert!(slots(ProfileSheetStyle::Career)
                .contains(&profile_question_slot(ProfileSheetStyle::Career, q)));
        }
    }

    #[test]
    fn info_lists_have_unique_keys() {
        let mut keys: Vec<String> = profile_questions().into_iter().map(|q| q.key).collect();
        keys.extend(profile_auto_fields().into_iter().map(|f| f.key));
        let n = keys.len();
        keys.sort();
        keys.dedup();
        assert_eq!(keys.len(), n);
        assert_eq!(profile_sheet_sizes()[1].height_px, 1920);
        assert_eq!(profile_sheet_styles()[0].label, "履歴書");
    }

    #[test]
    fn brand_marks_skip_other_follow_sort_order_and_keep_manual_choices() {
        let mut rec = record();
        rec.brands.push(ProfileBrandInput {
            id: "other".into(),
            label: "Other".into(),
            color: None,
            sort_order: 99,
        });
        rec.brands.reverse();
        let sheet = profile_sheet_default();
        let marks = profile_brand_marks(&sheet, &rec);
        let ids: Vec<&str> = marks.iter().map(|b| b.id.as_str()).collect();
        assert_eq!(ids, vec!["765", "cg", "ml", "sm"]);
        assert!(marks.iter().all(|b| b.checked == b.from_record));
        assert!(!marks[3].checked);

        // 記録から付く丸を外す・記録に無い丸を付ける。もう一度押すと戻る。
        let off = profile_toggle_brand(&sheet, &rec, "cg");
        assert_eq!(off.brand_off, vec!["cg"]);
        let on = profile_toggle_brand(&off, &rec, "sm");
        assert_eq!(on.brand_on, vec!["sm"]);
        let checked: Vec<String> = profile_brand_marks(&on, &rec)
            .into_iter()
            .filter(|b| b.checked)
            .map(|b| b.id)
            .collect();
        assert_eq!(checked, vec!["765", "ml", "sm"]);
        let back = profile_toggle_brand(&profile_toggle_brand(&on, &rec, "cg"), &rec, "sm");
        assert!(back.brand_on.is_empty() && back.brand_off.is_empty());
        assert_eq!(profile_sheet_from_json(&profile_sheet_to_json(&on)), on);
    }

    #[test]
    fn brand_circle_wobble_is_stable_and_in_range() {
        let rec = record();
        let a = profile_brand_marks(&profile_sheet_default(), &rec);
        let b = profile_brand_marks(&profile_sheet_default(), &rec);
        assert_eq!(a, b);
        for m in &a {
            assert!((-9.0..=9.0).contains(&m.tilt_degrees));
            assert!((0.92..=1.12).contains(&m.stretch));
            assert!((0.0..360.0).contains(&m.start_degrees));
        }
        assert!(a.windows(2).any(|w| w[0].tilt_degrees != w[1].tilt_degrees));
    }
}
