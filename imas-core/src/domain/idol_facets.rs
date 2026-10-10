//! アイドルの「項目 (ファセット)」の定義と、1 人ぶんの束 (`/facts`) の組み立て。
//!
//! ## 何のためにあるか
//!
//! 最初の利用者は yesno (当てっこゲーム)。アイドルの知識をカテゴリ別に LLM (Jev) へ渡して
//! yes/no を判定させる。そのために、プロフィールを「年齢帯」「髪色」「一人称」のような**細かい
//! 項目**に分け、項目ごとに**値と出どころ**を持つ。タグ (コミュニティの票) からプロフィールへ
//! 昇格しうる値の器でもある。
//!
//! - 項目の一覧と値の語彙は [`FACETS`] が**唯一の正**。`imas-core/facets.json` はこれの書き出し
//!   (テストが一致を固定する) で、タグ側 (`imas-live-api`) や Python のツールはそれを読む。
//! - 値の出どころ ([`Source`]): `official` = マスタの公式の列 / `idol_facets` の公式の行、
//!   `promoted` = タグから昇格して `idol_facets` に保存した値、`tag` = タグの票 (票数つき)。
//!   食い違ったら official > promoted > tag。
//! - 自動で決まる項目 ([`Auto`]): 年齢帯・出身地方・色名・身長帯・誕生月は他の公式の値からの
//!   機械的な変換 (`derived: true`)。学年の段階 (`school_stage`) は推定で、他に値があれば負ける。
//! - 髪は項目の値ではなく**髪型 1 つぶんのまとまり** (`idol_hairstyles`) で持つ。1 人に複数
//!   (基本・セカンドヘア・覚醒後…) 持て、`is_main` はちょうど 1 つ。`/facts` の髪の項目は main の
//!   値で、ほかの髪型は `other_hairstyles` に label つきで並ぶ。目の色・眼鏡などは `idol_facets`。
//!
//! 組み立て ([`build_idol_facts`]) は純粋関数。話し方 (agent::tools::speech) とタグの票の写しは
//! 入力として渡す (この層は agent feature に依存しない)。
//!
//! ## 返さないもの
//!
//! 歌詞・`lyrics_url`・`preview_url`・体重・スリーサイズ・話し方の出典 URL。

use crate::domain::idol_queries as idols;
use crate::domain::idol_song_queries as idol_songs;
use crate::domain::snapshot::{IdolHairstyleRow, Snapshot};
use serde_json::{json, Map, Value};
use std::collections::{BTreeMap, BTreeSet, HashMap};

/// `/facts` 文書の形の版。キーの追加は版を上げない。削除・改名・型の変更で上げる。
pub const FACTS_SCHEMA_VERSION: u32 = 1;
/// 定義 JSON (`facets.json`) の形の版。
pub const DEFINITIONS_SCHEMA_VERSION: u32 = 1;
/// タグの票がこの数に満たない値は項目に載せない (荒らし・誤投票の足切り)。
pub const MIN_TAG_VOTES: i64 = 3;
/// 「代表」の件数 (代表曲・代表ユニット・よく共演する人)。
pub const REPRESENTATIVE_LIMIT: usize = 5;

// ---------------------------------------------------------------------------
// 定義
// ---------------------------------------------------------------------------

/// 項目のカテゴリ。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Category {
    Profile,
    Appearance,
    Personality,
    Career,
    Likes,
    Relations,
    Works,
}

impl Category {
    pub const ALL: [Category; 7] = [
        Category::Profile,
        Category::Appearance,
        Category::Personality,
        Category::Career,
        Category::Likes,
        Category::Relations,
        Category::Works,
    ];
    pub fn key(self) -> &'static str {
        match self {
            Category::Profile => "profile",
            Category::Appearance => "appearance",
            Category::Personality => "personality",
            Category::Career => "career",
            Category::Likes => "likes",
            Category::Relations => "relations",
            Category::Works => "works",
        }
    }
    pub fn label(self) -> &'static str {
        match self {
            Category::Profile => "プロフィール",
            Category::Appearance => "容姿",
            Category::Personality => "性格・話し方",
            Category::Career => "経歴・特技",
            Category::Likes => "好み",
            Category::Relations => "所属・関係",
            Category::Works => "楽曲・ライブ",
        }
    }
}

/// 値の型。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// 1 つだけ持つ文字列。
    Single,
    /// 複数持てる文字列 (`values` の配列)。
    Multi,
    /// 数値。
    Number,
    /// 真偽。
    Bool,
    /// 色。値は `{"hex": "#RRGGBB", "name": "紫"}`。DB には hex だけを保存する。
    Color,
}

impl Kind {
    pub fn key(self) -> &'static str {
        match self {
            Kind::Single => "single",
            Kind::Multi => "multi",
            Kind::Number => "number",
            Kind::Bool => "bool",
            Kind::Color => "color",
        }
    }
}

/// 自動で決まる項目か。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Auto {
    /// 自動ではない。
    No,
    /// 他の公式の値からの機械的な変換 (年齢帯・出身地方・色名…)。`idol_facets` では上書きしない。
    Exact,
    /// 推定 (学年の段階)。`idol_facets` やタグの値があればそちらが勝つ。
    Estimate,
}

/// 項目 1 つの定義。
#[derive(Debug, Clone, Copy)]
pub struct FacetDef {
    pub key: &'static str,
    pub category: Category,
    pub kind: Kind,
    /// 値が決まった語彙のとき、その一覧。`None` は自由文字列。
    pub vocab: Option<&'static [&'static str]>,
    /// 日本語の見出し (Jev に渡すときもこの語)。
    pub label: &'static str,
    /// Jev に渡すときの書き方・解釈の注意。
    pub jev_hint: &'static str,
    /// Jev に渡すか。`false` は照合専用 (質問に曲名が出たときの突き合わせ用の全件など)。
    pub jev: bool,
    pub auto: Auto,
    /// 髪型のまとまり (`idol_hairstyles`) に保存する項目か。`/facts` では main の髪型の値として出る。
    pub hairstyle: bool,
    /// タグの票 (`facet` / `facet_value`) からこの項目に値を足してよいか。
    pub taggable: bool,
    /// 数が多い項目の「全件」側 (対になる「まとめ」側は `summary_of` が指す)。
    pub bulk_full_of: Option<&'static str>,
    /// 値の単位 (表示用)。
    pub unit: Option<&'static str>,
}

const fn f(
    key: &'static str,
    category: Category,
    kind: Kind,
    vocab: Option<&'static [&'static str]>,
    label: &'static str,
    jev_hint: &'static str,
) -> FacetDef {
    FacetDef {
        key,
        category,
        kind,
        vocab,
        label,
        jev_hint,
        jev: true,
        auto: Auto::No,
        hairstyle: false,
        taggable: false,
        bulk_full_of: None,
        unit: None,
    }
}

impl FacetDef {
    const fn auto(mut self, a: Auto) -> Self {
        self.auto = a;
        self
    }
    const fn hair(mut self) -> Self {
        self.hairstyle = true;
        self
    }
    const fn taggable(mut self) -> Self {
        self.taggable = true;
        self
    }
    /// 照合専用 (Jev に渡さない) の全件側。`summary` はまとめ側の項目キー。
    const fn full_of(mut self, summary: &'static str) -> Self {
        self.jev = false;
        self.bulk_full_of = Some(summary);
        self
    }
    const fn unit(mut self, u: &'static str) -> Self {
        self.unit = Some(u);
        self
    }
}

pub const GENDERS: &[&str] = &["女性", "男性"];
pub const AGE_BANDS: &[&str] = &["10歳未満", "10代", "20代", "30代", "40代以上"];
pub const SCHOOL_STAGES: &[&str] = &["小学生", "中学生", "高校生", "大学生", "社会人"];
pub const CONSTELLATIONS: &[&str] = &[
    "牡羊座", "牡牛座", "双子座", "蟹座", "獅子座", "乙女座", "天秤座", "蠍座", "射手座", "山羊座", "水瓶座", "魚座",
];
pub const HEIGHT_BANDS: &[&str] = &["140cm未満", "140cm台", "150cm台", "160cm台", "170cm以上"];
pub const BLOOD_TYPES: &[&str] = &["A", "B", "O", "AB"];
pub const HANDEDNESS: &[&str] = &["右利き", "左利き", "両利き"];
pub const REGIONS: &[&str] = &["北海道", "東北", "関東", "中部", "近畿", "中国", "四国", "九州・沖縄", "海外"];
pub const GRADES: &[&str] = &["1年", "2年", "3年"];
pub const HAIR_COLORS: &[&str] =
    &["黒", "茶", "金", "白・銀", "赤", "オレンジ", "ピンク", "緑", "青", "水色", "紫"];
pub const HAIR_LENGTHS: &[&str] = &["ロング", "ボブ〜ミディアム", "ショート"];
pub const HAIR_STYLES: &[&str] = &[
    "ストレート",
    "ウェーブ",
    "縦ロール",
    "ツインテール",
    "ローツインテール",
    "ポニーテール",
    "サイドテール",
    "ハーフサイドテール",
    "ツーサイドアップ",
    "ハーフアップ",
    "ハーフアップツイン",
    "三つ編み・編み込み",
    "お団子",
    "ひとつ縛り",
    "まとめ髪",
    "姫カット",
    "アホ毛",
    "跳ね毛",
    "外はね",
    "逆立てた髪",
    "オールバック",
    "リーゼント",
];
pub const BANGS: &[&str] = &["ぱっつん", "センター分け", "片目隠れ", "おでこ"];
pub const HAIR_ACCESSORIES: &[&str] = &["リボン", "ヘアバンド", "ヘアピン", "その他の髪飾り"];
pub const EYE_COLORS: &[&str] =
    &["黒", "茶", "青", "水色", "緑", "赤", "ピンク", "紫", "金", "オレンジ", "灰"];
pub const SPEECH_STYLES: &[&str] = &["敬語", "タメ口", "敬語とタメ口の混在"];
pub const DEBUT_ROUTES: &[&str] = &["スカウト", "オーディション", "事務所の紹介", "その他"];

/// main の髪型の label の既定。
pub const MAIN_HAIRSTYLE_LABEL: &str = "基本";

/// 項目の一覧。並びがそのまま出力の並び。**キーの追加はここだけ**。
pub const FACETS: &[FacetDef] = &[
    // --- profile ---
    f("gender", Category::Profile, Kind::Single, Some(GENDERS), "性別", "女性/男性。未設定のアイドルは項目ごと無い"),
    f("age", Category::Profile, Kind::Number, None, "年齢", "設定上の年齢。「17歳以上か」のような比較に使う").unit("歳"),
    f("age_band", Category::Profile, Kind::Single, Some(AGE_BANDS), "年齢帯", "年齢から自動。「10代か」の判定はこれを見る").auto(Auto::Exact),
    f("school_stage", Category::Profile, Kind::Single, Some(SCHOOL_STAGES), "学校の段階", "学年・年齢・公式の値から。推定のときは derived:true。13歳以上19歳未満の境目は年齢の目安").auto(Auto::Estimate),
    f("birthday", Category::Profile, Kind::Single, None, "誕生日", "「1月18日」の形"),
    f("birth_month", Category::Profile, Kind::Number, None, "誕生月", "誕生日から自動 (1〜12)").auto(Auto::Exact).unit("月"),
    f("constellation", Category::Profile, Kind::Single, Some(CONSTELLATIONS), "星座", "12 星座"),
    f("height_cm", Category::Profile, Kind::Number, None, "身長", "cm").unit("cm"),
    f("height_band", Category::Profile, Kind::Single, Some(HEIGHT_BANDS), "身長帯", "身長から自動").auto(Auto::Exact),
    f("blood_type", Category::Profile, Kind::Single, Some(BLOOD_TYPES), "血液型", "A/B/O/AB。不明は項目ごと無い"),
    f("handedness", Category::Profile, Kind::Single, Some(HANDEDNESS), "利き手", "右利き/左利き/両利き"),
    f("birthplace", Category::Profile, Kind::Single, None, "出身地", "都道府県 (「県」「府」「都」は付けない)。海外・市の名前のものは原文に近い形"),
    f("birthplace_region", Category::Profile, Kind::Single, Some(REGIONS), "出身地方", "出身地から自動。近畿は「関西」とも言う").auto(Auto::Exact),
    f("nationality", Category::Profile, Kind::Single, None, "国籍", "公式に分かるものだけ。出身地からは推測しない"),
    f("school", Category::Profile, Kind::Single, None, "学校", "学マスは初星学園。ほかは公式に分かるものだけ").auto(Auto::Exact),
    f("grade", Category::Profile, Kind::Single, None, "学年", "「1年」「中学2年」など"),
    // --- appearance (hair_* は idol_hairstyles に保存。main の値が出る) ---
    f("hair_color", Category::Appearance, Kind::Single, Some(HAIR_COLORS), "髪色", "main の髪型の髪色。ほかの髪型は other_hairstyles に載る").hair(),
    f("hair_color_secondary", Category::Appearance, Kind::Single, Some(HAIR_COLORS), "髪色 (2色目)", "メッシュ・インナー・グラデーションの2色目").hair(),
    f("hair_length", Category::Appearance, Kind::Single, Some(HAIR_LENGTHS), "髪の長さ", "ロング/ボブ〜ミディアム/ショート").hair(),
    f("hair_style", Category::Appearance, Kind::Multi, Some(HAIR_STYLES), "髪型", "main の髪型のかたち。複数あてはまる (ツインテールかつ縦ロール など)").hair(),
    f("bangs", Category::Appearance, Kind::Single, Some(BANGS), "前髪", "特徴のある前髪だけ。普通の前髪は項目ごと無い").hair(),
    f("hair_accessory", Category::Appearance, Kind::Multi, Some(HAIR_ACCESSORIES), "髪飾り", "リボン・ヘアバンド・ヘアピンなど").hair(),
    f("eye_color", Category::Appearance, Kind::Single, Some(EYE_COLORS), "目の色", ""),
    f("glasses", Category::Appearance, Kind::Bool, None, "眼鏡", "普段眼鏡をかけているか"),
    f("image_color", Category::Appearance, Kind::Color, None, "イメージカラー", "公式の色。値は hex と色名 (色名は hex から自動)"),
    f("features", Category::Appearance, Kind::Multi, None, "身体的な特徴", "ほくろ・八重歯・泣きぼくろなど").taggable(),
    // --- personality ---
    f("traits", Category::Personality, Kind::Multi, None, "性格", "性格を表す短い語。ファンの票由来のものは source:tag").taggable(),
    f("first_person", Category::Personality, Kind::Multi, None, "一人称", "場面で変わる子は複数"),
    f("producer_call", Category::Personality, Kind::Multi, None, "プロデューサーの呼び方", ""),
    f("catchphrases", Category::Personality, Kind::Multi, None, "口癖・決まり文句", "「○○」は差し込み部分"),
    f("sentence_endings", Category::Personality, Kind::Multi, None, "語尾", ""),
    f("dialect", Category::Personality, Kind::Single, None, "方言", "関西弁・博多弁など。標準語は項目ごと無い").taggable(),
    f("speech_style", Category::Personality, Kind::Single, Some(SPEECH_STYLES), "話し方", "敬語/タメ口/混在"),
    f("speech_notes", Category::Personality, Kind::Single, None, "話し方の要約", "出典つきで確かめた話し方の要約文"),
    // --- career ---
    f("hobbies", Category::Career, Kind::Multi, None, "趣味", ""),
    f("talents", Category::Career, Kind::Multi, None, "特技", ""),
    f("past_jobs", Category::Career, Kind::Multi, None, "アイドルになる前の職業", "").taggable(),
    f("club", Category::Career, Kind::Multi, None, "部活・サークル", "").taggable(),
    f("education", Category::Career, Kind::Single, None, "学歴", ""),
    f("achievements", Category::Career, Kind::Multi, None, "実績", "総選挙の順位など").taggable(),
    f("debut_route", Category::Career, Kind::Single, Some(DEBUT_ROUTES), "アイドルになった経緯", "スカウト/オーディションなど"),
    f("debut_date", Category::Career, Kind::Single, None, "デビュー日", ""),
    // --- likes ---
    f("favorite_foods", Category::Likes, Kind::Multi, None, "好きな食べ物", "").taggable(),
    f("favorite_things", Category::Likes, Kind::Multi, None, "好きなもの", "").taggable(),
    f("dislikes", Category::Likes, Kind::Multi, None, "苦手なもの", "").taggable(),
    // --- relations ---
    f("brand", Category::Relations, Kind::Single, None, "ブランド", "値はブランド名。extra に id と短縮名"),
    f("agency", Category::Relations, Kind::Single, None, "所属事務所・学園", "ブランドから自動").auto(Auto::Exact),
    f("unit_count", Category::Relations, Kind::Number, None, "ユニットの数", "").unit("組"),
    f("representative_units", Category::Relations, Kind::Multi, None, "代表的なユニット", "恒常ユニットを優先して最大 5"),
    f("units", Category::Relations, Kind::Multi, None, "所属ユニット (全件)", "照合用。質問にユニット名が出たときの突き合わせに使う").full_of("representative_units"),
    f("frequent_costars", Category::Relations, Kind::Multi, None, "よく共演する人", "同じ公演に出た回数が多い順に最大 5"),
    f("family", Category::Relations, Kind::Multi, None, "家族", "").taggable(),
    f("roommates", Category::Relations, Kind::Multi, None, "ルームメイト", "").taggable(),
    // --- works ---
    f("voice_actor", Category::Works, Kind::Single, None, "声優", "現在の担当"),
    f("solo_song_count", Category::Works, Kind::Number, None, "ソロ曲の数", "その人ひとりの持ち歌").unit("曲"),
    f("unit_song_count", Category::Works, Kind::Number, None, "ユニット曲・合唱曲の数", "持ち歌のうちソロでないもの + 所属ユニットの曲").unit("曲"),
    f("representative_songs", Category::Works, Kind::Multi, None, "代表曲", "ライブで歌った回数が多い順に最大 5 (回数は extra)"),
    f("songs", Category::Works, Kind::Multi, None, "持ち歌 (全件)", "照合用。質問に曲名が出たときの突き合わせに使う").full_of("representative_songs"),
    f("performed_songs", Category::Works, Kind::Multi, None, "ライブで歌った曲 (全件)", "照合用").full_of("representative_songs"),
    f("show_count", Category::Works, Kind::Number, None, "出演公演数", "").unit("公演"),
    f("first_show", Category::Works, Kind::Single, None, "初出演の公演", "「日付 ライブ名」"),
    f("latest_show", Category::Works, Kind::Single, None, "直近の出演公演", "「日付 ライブ名」"),
    f("appeared_events", Category::Works, Kind::Multi, None, "出演したライブ (全件)", "照合用。ライブ名が質問に出たときの突き合わせに使う").full_of("latest_show"),
];

pub fn facet_def(key: &str) -> Option<&'static FacetDef> {
    FACETS.iter().find(|d| d.key == key)
}

/// 定義の JSON (`imas-core/facets.json`)。タグ側・Python ツールが読む。
pub fn definitions_json() -> Value {
    let facets: Vec<Value> = FACETS
        .iter()
        .map(|d| {
            let mut o = Map::new();
            o.insert("key".into(), d.key.into());
            o.insert("category".into(), d.category.key().into());
            o.insert("kind".into(), d.kind.key().into());
            o.insert("label".into(), d.label.into());
            if let Some(v) = d.vocab {
                o.insert("vocab".into(), json!(v));
            }
            if !d.jev_hint.is_empty() {
                o.insert("jev_hint".into(), d.jev_hint.into());
            }
            o.insert("jev".into(), d.jev.into());
            o.insert("auto".into(), match d.auto {
                Auto::No => "no",
                Auto::Exact => "exact",
                Auto::Estimate => "estimate",
            }.into());
            o.insert("store".into(), if d.hairstyle { "idol_hairstyles" } else if d.auto == Auto::Exact || d.bulk_full_of.is_some() { "computed" } else { "idol_facets" }.into());
            o.insert("taggable".into(), d.taggable.into());
            if let Some(s) = d.bulk_full_of {
                o.insert("full_of".into(), s.into());
            }
            if let Some(u) = d.unit {
                o.insert("unit".into(), u.into());
            }
            Value::Object(o)
        })
        .collect();
    json!({
        "schema_version": DEFINITIONS_SCHEMA_VERSION,
        "_note": "項目の定義の唯一の正は imas-core/src/domain/idol_facets.rs。このファイルはその書き出し (cargo test が一致を固定。更新は UPDATE_FACETS_JSON=1 cargo test idol_facets)。",
        "categories": Category::ALL.iter().map(|c| json!({"key": c.key(), "label": c.label()})).collect::<Vec<_>>(),
        "hairstyle_fields": { "hair_color": "hair_color", "hair_color_secondary": "hair_color_secondary", "hair_length": "hair_length", "hair_style": "styles", "bangs": "bangs", "hair_accessory": "accessories" },
        "main_hairstyle_label": MAIN_HAIRSTYLE_LABEL,
        "sources": ["official", "promoted", "tag"],
        "facets": facets,
    })
}

// ---------------------------------------------------------------------------
// 自動で決まる項目
// ---------------------------------------------------------------------------

/// 年齢 → 年齢帯。
pub fn age_band(age: i64) -> Option<&'static str> {
    match age {
        i64::MIN..=-1 => None,
        0..=9 => Some("10歳未満"),
        10..=19 => Some("10代"),
        20..=29 => Some("20代"),
        30..=39 => Some("30代"),
        _ => Some("40代以上"),
    }
}

/// 年齢 → 学校の段階 (推定)。6〜12 小学生 / 13〜15 中学生 / 16〜18 高校生 / 23 以上 社会人。
/// 19〜22 は大学生か社会人か決められないので `None` (公式の値があればそちら)。
/// 12 歳は中学 1 年のこともあるが、本編で12歳が小学生の子が多いため小学生に寄せている。
pub fn school_stage_from_age(age: i64) -> Option<&'static str> {
    match age {
        6..=12 => Some("小学生"),
        13..=15 => Some("中学生"),
        16..=18 => Some("高校生"),
        23.. => Some("社会人"),
        _ => None,
    }
}

/// 身長 (cm) → 身長帯。
pub fn height_band(cm: f64) -> Option<&'static str> {
    if !cm.is_finite() || cm <= 0.0 {
        return None;
    }
    Some(if cm < 140.0 {
        "140cm未満"
    } else if cm < 150.0 {
        "140cm台"
    } else if cm < 160.0 {
        "150cm台"
    } else if cm < 170.0 {
        "160cm台"
    } else {
        "170cm以上"
    })
}

/// `"--04-03"` → 4。
pub fn birth_month(birthday: &str) -> Option<i64> {
    let m: i64 = birthday.strip_prefix("--")?.split('-').next()?.parse().ok()?;
    (1..=12).contains(&m).then_some(m)
}

const PREFECTURES: &[(&str, &str)] = &[
    ("北海道", "北海道"),
    ("青森", "東北"), ("岩手", "東北"), ("宮城", "東北"), ("秋田", "東北"), ("山形", "東北"), ("福島", "東北"),
    ("茨城", "関東"), ("栃木", "関東"), ("群馬", "関東"), ("埼玉", "関東"), ("千葉", "関東"), ("東京", "関東"), ("神奈川", "関東"),
    ("新潟", "中部"), ("富山", "中部"), ("石川", "中部"), ("福井", "中部"), ("山梨", "中部"), ("長野", "中部"), ("岐阜", "中部"), ("静岡", "中部"), ("愛知", "中部"),
    ("三重", "近畿"), ("滋賀", "近畿"), ("京都", "近畿"), ("大阪", "近畿"), ("兵庫", "近畿"), ("奈良", "近畿"), ("和歌山", "近畿"),
    ("鳥取", "中国"), ("島根", "中国"), ("岡山", "中国"), ("広島", "中国"), ("山口", "中国"),
    ("徳島", "四国"), ("香川", "四国"), ("愛媛", "四国"), ("高知", "四国"),
    ("福岡", "九州・沖縄"), ("佐賀", "九州・沖縄"), ("長崎", "九州・沖縄"), ("熊本", "九州・沖縄"), ("大分", "九州・沖縄"), ("宮崎", "九州・沖縄"), ("鹿児島", "九州・沖縄"), ("沖縄", "九州・沖縄"),
];

/// 市の名前などで書かれた出身地 → 都道府県。
const CITY_TO_PREFECTURE: &[(&str, &str)] = &[
    ("名古屋", "愛知"), ("鎌倉", "神奈川"), ("湘南", "神奈川"), ("横須賀", "神奈川"), ("神戸", "兵庫"),
    ("淡路島", "兵庫"), ("札幌", "北海道"), ("仙台", "宮城"),
];

/// 海外とみなす出身地。
const OVERSEAS: &[&str] = &["イギリス", "香港", "ブラジル", "リオ・デ・ジャネイロ", "ベルリン", "パリ", "洪川郡", "海外"];

/// 出身地の原文 → (正規化した出身地, 地方)。
///
/// 都道府県は「県/府/都」を落として揃える。「京都？」のような注記は落とす。市の名前は都道府県に、
/// 海外は原文のまま地方 `海外` に。どれにも当たらない (「海の向こう」のような曖昧なもの) は `None`。
pub fn normalize_birthplace(raw: &str) -> Option<(String, &'static str)> {
    let t = raw.trim().trim_end_matches(['？', '?']).trim();
    let t = t.strip_suffix('県').or_else(|| t.strip_suffix('府')).unwrap_or(t);
    let t = if t == "東京都" { "東京" } else { t };
    if let Some((p, r)) = PREFECTURES.iter().find(|(p, _)| *p == t) {
        return Some((p.to_string(), r));
    }
    if let Some((_, p)) = CITY_TO_PREFECTURE.iter().find(|(c, _)| *c == t) {
        let region = PREFECTURES.iter().find(|(q, _)| q == p).map(|(_, r)| *r)?;
        return Some((p.to_string(), region));
    }
    if OVERSEAS.iter().any(|o| t.contains(o)) {
        return Some((t.to_string(), "海外"));
    }
    None
}

/// 星座の原文 → 12 星座のどれか (「花も恥じらう乙女座」→「乙女座」)。
pub fn normalize_constellation(raw: &str) -> Option<&'static str> {
    CONSTELLATIONS.iter().copied().find(|c| raw.contains(c))
}

/// ブランド → 所属 (事務所・学園)。
pub fn agency_of_brand(brand_id: &str) -> Option<&'static str> {
    Some(match brand_id {
        "765as" | "ml" => "765プロダクション",
        "cg" => "346プロダクション",
        "sidem" => "315プロダクション",
        "sc" => "283プロダクション",
        "gakuen" => "初星学園",
        "876" => "876プロダクション",
        "961" => "961プロダクション",
        _ => return None,
    })
}

// ---------------------------------------------------------------------------
// 入力と出力
// ---------------------------------------------------------------------------

/// 値の出どころ。小さいほど強い。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Source {
    Official,
    Promoted,
    Tag,
}

impl Source {
    pub fn key(self) -> &'static str {
        match self {
            Source::Official => "official",
            Source::Promoted => "promoted",
            Source::Tag => "tag",
        }
    }
}

/// タグの票の写し (`imas-live-api` から同期で取り込む想定)。1 アイドル 1 タグ 1 行。
///
/// `facet` / `facet_value` は `idol_tag_master` の列。`facet` が無いタグは、`category` が
/// `personality` なら `traits`、そうでなければ `free_tags` に入る。
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub struct TagFacetInput {
    /// タグの名前。
    pub tag: String,
    #[serde(default)]
    pub facet: Option<String>,
    #[serde(default)]
    pub facet_value: Option<String>,
    /// タグのカテゴリ (`idol_tag_master.category`)。
    #[serde(default)]
    pub category: Option<String>,
    /// そのアイドルに付いた票数。
    pub votes: i64,
}

/// 話し方 (agent::tools::speech の出力を項目の形にしたもの)。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct PersonaInput {
    pub first_person: Vec<String>,
    pub producer_call: Vec<String>,
    pub catchphrases: Vec<String>,
    pub sentence_endings: Vec<String>,
    /// 「混在：…」「丁寧語…」などの自由文。
    pub politeness: Option<String>,
    pub tone_notes: Option<String>,
}

/// 話し方の `politeness` 自由文 → 語彙。判断できなければ `None`。
pub fn speech_style_from(politeness: &str) -> Option<&'static str> {
    let p = politeness.trim();
    if p.starts_with("混在") {
        Some("敬語とタメ口の混在")
    } else if p.starts_with("丁寧") || p.starts_with("敬語") {
        Some("敬語")
    } else if p.starts_with("タメ") || p.starts_with("くだけ") || p.starts_with("カジュアル") {
        Some("タメ口")
    } else {
        None
    }
}

/// 候補 1 件 (まだ採否が決まっていない値)。
#[derive(Debug, Clone)]
struct Cand {
    facet: &'static str,
    value: Value,
    source: Source,
    /// 同じ出どころの中での強さ (小さいほど強い)。推定は大きくして、他の値に負ける。
    rank: u8,
    derived: bool,
    votes: Option<i64>,
    extra: Option<Value>,
}

fn cand(facet: &'static str, value: impl Into<Value>) -> Cand {
    Cand {
        facet,
        value: value.into(),
        source: Source::Official,
        rank: 0,
        derived: false,
        votes: None,
        extra: None,
    }
}

impl Cand {
    fn derived(mut self) -> Self {
        self.derived = true;
        self
    }
    fn extra(mut self, e: Value) -> Self {
        self.extra = Some(e);
        self
    }
    fn estimate(mut self) -> Self {
        self.rank = 9;
        self.derived = true;
        self
    }
}

fn split_list(text: &str) -> Vec<String> {
    text.split(['、', '，', ',', '/', '／'])
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect()
}

fn num(f: f64) -> Value {
    if f.fract() == 0.0 { json!(f as i64) } else { json!(f) }
}

fn json_key(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        other => other.to_string(),
    }
}

/// `idol_facets` の行 1 件を型に合わせて値にする。語彙や型に合わなければ `None`。
fn row_value(def: &FacetDef, raw: &str) -> Option<Value> {
    match def.kind {
        Kind::Single | Kind::Multi => {
            if let Some(v) = def.vocab {
                if !v.contains(&raw) {
                    return None;
                }
            }
            Some(Value::String(raw.to_string()))
        }
        Kind::Number => raw.parse::<f64>().ok().filter(|f| f.is_finite()).map(num),
        Kind::Bool => match raw {
            "true" | "1" => Some(json!(true)),
            "false" | "0" => Some(json!(false)),
            _ => None,
        },
        Kind::Color => {
            let ok = raw.len() == 7 && raw.starts_with('#') && raw[1..].chars().all(|c| c.is_ascii_hexdigit());
            ok.then(|| color_value(raw))
        }
    }
}

fn color_value(hex: &str) -> Value {
    let hex = hex.to_uppercase();
    let name = crate::domain::color_names::color_name(Some(&hex));
    json!({ "hex": hex, "name": name })
}

/// `idol_facets` の行 ID の元の文字列。単一値は (アイドル, 項目)、複数値は値まで含めて決める。
/// Python の `tools/apply_data.py` も同じ式で作る (`sha1` の先頭 20 桁、接頭辞 `if_`)。
pub fn facet_row_key(idol_id: &str, facet: &str, value: &str, multi: bool) -> String {
    let mut s = format!("{idol_id}|{facet}");
    if multi {
        s.push('|');
        s.push_str(value);
    }
    s
}

/// `idol_hairstyles` の行 ID の元の文字列 (接頭辞 `ih_` + sha1 の先頭 20 桁は Python と共通)。
pub fn hairstyle_row_key(idol_id: &str, label: &str) -> String {
    format!("{idol_id}|{label}")
}

/// 髪型の行 1 件の語彙・形の検査。問題の説明を返す (空なら妥当)。
/// `apply_data.py --check` も同じ規則を `facets.json` から実装している。
pub fn hairstyle_row_problems(r: &IdolHairstyleRow) -> Vec<String> {
    let mut p = Vec::new();
    let one = |name: &str, v: &Option<String>, vocab: &[&str], p: &mut Vec<String>| {
        if let Some(v) = v {
            if !vocab.contains(&v.as_str()) {
                p.push(format!("{name} '{v}' が語彙に無い"));
            }
        }
    };
    one("hair_color", &r.hair_color, HAIR_COLORS, &mut p);
    one("hair_color_secondary", &r.hair_color_secondary, HAIR_COLORS, &mut p);
    one("hair_length", &r.hair_length, HAIR_LENGTHS, &mut p);
    one("bangs", &r.bangs, BANGS, &mut p);
    for s in &r.styles {
        if !HAIR_STYLES.contains(&s.as_str()) {
            p.push(format!("styles '{s}' が語彙に無い"));
        }
    }
    for a in &r.accessories {
        if !HAIR_ACCESSORIES.contains(&a.as_str()) {
            p.push(format!("accessories '{a}' が語彙に無い"));
        }
    }
    if r.label.trim().is_empty() {
        p.push("label が空".into());
    }
    p
}

/// 1 人ぶんの髪型の組の検査: 髪型が 1 つ以上あるなら is_main はちょうど 1 つ、label は重複しない。
pub fn hairstyle_set_problems(idol_id: &str, rows: &[&IdolHairstyleRow]) -> Vec<String> {
    let mut p = Vec::new();
    if rows.is_empty() {
        return p;
    }
    let mains = rows.iter().filter(|r| r.is_main).count();
    if mains != 1 {
        p.push(format!("{idol_id}: is_main の髪型が {mains} 個 (ちょうど 1 個にする)"));
    }
    let labels: BTreeSet<&str> = rows.iter().map(|r| r.label.as_str()).collect();
    if labels.len() != rows.len() {
        p.push(format!("{idol_id}: 髪型の label が重複している"));
    }
    p
}

// ---------------------------------------------------------------------------
// 組み立て
// ---------------------------------------------------------------------------

/// アイドル 1 人の項目の束 (`GET /v1/idols/:id/facts` の文書)。いないアイドルは `None`。
///
/// 入力: マスタの列 (`Snapshot`)・`idol_facets` の行 (`Snapshot::idol_facets`)・話し方・
/// タグの票の写し。`tags` は空でよい (MCP・アプリ内トークはマスタだけで組む)。
pub fn build_idol_facts(snap: &Snapshot, idol_id: &str, persona: &PersonaInput, tags: &[TagFacetInput]) -> Option<Value> {
    let &ii = snap.idol_index_by_id.get(idol_id)?;
    let idol = &snap.idols[ii as usize];
    let mut c: Vec<Cand> = Vec::new();

    // --- profile ---
    match idol.gender.as_deref() {
        Some("female") => c.push(cand("gender", "女性")),
        Some("male") => c.push(cand("gender", "男性")),
        _ => {}
    }
    if let Some(age) = idol.age {
        c.push(cand("age", age));
        if let Some(b) = age_band(age) {
            c.push(cand("age_band", b).derived());
        }
        if let Some(s) = school_stage_from_age(age) {
            c.push(cand("school_stage", s).estimate());
        }
    }
    if let Some(bd) = idol.birthday.as_deref() {
        if let Some(d) = idols::birthday_display(Some(bd)) {
            c.push(cand("birthday", d));
        }
        if let Some(m) = birth_month(bd) {
            c.push(cand("birth_month", m).derived());
        }
    }
    if let Some(k) = idol.constellation.as_deref().and_then(normalize_constellation) {
        c.push(cand("constellation", k));
    }
    if let Some(h) = idol.height.filter(|h| *h > 0.0) {
        c.push(cand("height_cm", num(h)));
        if let Some(b) = height_band(h) {
            c.push(cand("height_band", b).derived());
        }
    }
    if let Some(b) = idol.blood_type.as_deref().filter(|b| BLOOD_TYPES.contains(b)) {
        c.push(cand("blood_type", b));
    }
    match idol.handedness.as_deref() {
        Some("right") => c.push(cand("handedness", "右利き")),
        Some("left") => c.push(cand("handedness", "左利き")),
        Some("both") => c.push(cand("handedness", "両利き")),
        _ => {}
    }
    if let Some((place, region)) = idol.birth_place.as_deref().and_then(normalize_birthplace) {
        c.push(cand("birthplace", place));
        c.push(cand("birthplace_region", region).derived());
    }
    let brand_id = idol.brand_id.as_deref();
    if brand_id == Some("gakuen") {
        c.push(cand("school", "初星学園").derived());
    }
    if let Some(grade) = idol.attribute.as_deref().filter(|a| a.ends_with('年') && a.chars().next().is_some_and(|ch| ch.is_ascii_digit())) {
        c.push(cand("grade", grade));
        if brand_id == Some("gakuen") {
            // 初星学園は高等部。学年が分かっていれば推定ではなく確定。
            c.push(cand("school_stage", "高校生").derived());
        }
    }

    // --- appearance ---
    if let Some(hex) = idol.color.as_deref().filter(|h| !h.is_empty()) {
        if hex.len() == 7 && hex.starts_with('#') {
            c.push(cand("image_color", color_value(hex)));
        }
    }

    // --- personality (話し方は公式) ---
    for (facet, list) in [
        ("first_person", &persona.first_person),
        ("producer_call", &persona.producer_call),
        ("catchphrases", &persona.catchphrases),
        ("sentence_endings", &persona.sentence_endings),
    ] {
        for v in list {
            c.push(cand(facet, v.as_str()));
        }
    }
    if let Some(s) = persona.politeness.as_deref().and_then(speech_style_from) {
        c.push(cand("speech_style", s));
    }
    if let Some(t) = persona.tone_notes.as_deref().filter(|t| !t.is_empty()) {
        c.push(cand("speech_notes", t));
    }

    // --- career ---
    for v in idol.hobbies.as_deref().map(split_list).unwrap_or_default() {
        c.push(cand("hobbies", v));
    }
    for v in idol.talents.as_deref().map(split_list).unwrap_or_default() {
        c.push(cand("talents", v));
    }
    if let Some(d) = idol.debut_date.as_deref().filter(|d| !d.is_empty()) {
        c.push(cand("debut_date", d));
    }

    // --- relations ---
    if let Some(b) = brand_id.and_then(|id| snap.brand(id)) {
        c.push(cand("brand", b.name.as_str()).extra(json!({ "id": b.id, "short_name": b.short_name })));
    }
    if let Some(a) = brand_id.and_then(agency_of_brand) {
        c.push(cand("agency", a).derived());
    }
    let units = idols::idol_units(snap, idol_id);
    c.push(cand("unit_count", units.len()));
    for u in &units {
        c.push(cand("units", u.name.as_str()).extra(json!({ "id": u.id, "is_permanent": u.is_permanent })));
    }
    let mut rep: Vec<&idols::IdolUnitRecord> = units.iter().collect();
    rep.sort_by_key(|u| !u.is_permanent);
    for u in rep.into_iter().take(REPRESENTATIVE_LIMIT) {
        c.push(cand("representative_units", u.name.as_str()).extra(json!({ "id": u.id, "is_permanent": u.is_permanent })));
    }
    for (name, n) in frequent_costars(snap, ii).into_iter().take(REPRESENTATIVE_LIMIT) {
        c.push(cand("frequent_costars", name.0.as_str()).extra(json!({ "id": name.1, "shared_shows": n })));
    }

    // --- works ---
    if let Some(va) = snap.current_voice_actor(ii) {
        c.push(cand("voice_actor", va.name.as_str()));
    }
    let originals = idol_songs::idol_songs(snap, idol_id, Some("original"));
    let solo_ids: BTreeSet<&str> = originals
        .iter()
        .filter(|r| snap.song_index_by_id.get(&r.song_id).is_some_and(|&si| is_solo(snap, si)))
        .map(|r| r.song_id.as_str())
        .collect();
    let mut owned: BTreeMap<String, String> = BTreeMap::new(); // id → title (重複なし)
    for r in &originals {
        owned.insert(r.song_id.clone(), r.title.clone());
    }
    let mut unit_song_ids: BTreeSet<String> = originals
        .iter()
        .filter(|r| !solo_ids.contains(r.song_id.as_str()))
        .map(|r| r.song_id.clone())
        .collect();
    for id in idol_songs::idol_unit_song_ids(snap, idol_id) {
        if let Some(&si) = snap.song_index_by_id.get(&id) {
            owned.insert(id.clone(), snap.songs[si as usize].title.clone());
        }
        unit_song_ids.insert(id);
    }
    c.push(cand("solo_song_count", solo_ids.len()));
    c.push(cand("unit_song_count", unit_song_ids.len()));
    for (id, title) in &owned {
        c.push(cand("songs", title.as_str()).extra(json!({ "id": id })));
    }
    let performed = idol_songs::idol_performed_songs(snap, idol_id);
    for (n, s) in performed.iter().enumerate() {
        let e = json!({ "id": s.song_id, "performed_count": s.perform_count });
        if n < REPRESENTATIVE_LIMIT {
            c.push(cand("representative_songs", s.title.as_str()).extra(e.clone()));
        }
        c.push(cand("performed_songs", s.title.as_str()).extra(e));
    }
    let shows = idols::idol_shows(snap, idol_id);
    c.push(cand("show_count", shows.len()));
    let show_text = |s: &idols::IdolShowRecord| format!("{} {}", s.date, s.event_name);
    if let Some(s) = shows.last() {
        c.push(cand("first_show", show_text(s)).extra(json!({ "show_id": s.show_id, "event_id": s.event_id })));
    }
    if let Some(s) = shows.first() {
        c.push(cand("latest_show", show_text(s)).extra(json!({ "show_id": s.show_id, "event_id": s.event_id })));
    }
    let mut seen_events: BTreeSet<&str> = BTreeSet::new();
    for s in &shows {
        if seen_events.insert(s.event_id.as_str()) {
            c.push(cand("appeared_events", s.event_name.as_str()).extra(json!({ "id": s.event_id, "date": s.date })));
        }
    }

    // --- idol_facets の行 (official / promoted) ---
    for &ri in &snap.idol_facets_by_idol[ii as usize] {
        let row = &snap.idol_facets[ri as usize];
        let Some(def) = facet_def(&row.facet) else { continue };
        if def.auto == Auto::Exact || def.full_of_is_set() {
            continue; // 自動の項目・全件側は行で上書きしない
        }
        if def.hairstyle {
            continue; // 髪は idol_hairstyles にだけ保存する
        }
        let Some(value) = row_value(def, &row.value) else { continue };
        c.push(Cand {
            facet: def.key,
            value,
            source: if row.origin == "promoted" { Source::Promoted } else { Source::Official },
            rank: if row.origin == "promoted" { 0 } else { 1 }, // 列の値 (rank 0) が行より先
            derived: false,
            votes: None,
            extra: row.source_note.as_ref().map(|n| json!({ "note": n })),
        });
    }

    // --- 髪型 (main が hair_* の値になる。残りは other_hairstyles) ---
    let hairstyles: Vec<&IdolHairstyleRow> =
        snap.idol_hairstyles_by_idol[ii as usize].iter().map(|&i| &snap.idol_hairstyles[i as usize]).collect();
    let valid_hair: Vec<&IdolHairstyleRow> =
        hairstyles.iter().copied().filter(|r| hairstyle_row_problems(r).is_empty()).collect();
    // main は sort_order の早い is_main。壊れたデータ (main が無い・複数) でも決定的に動くよう、
    // main が無ければ先頭を main とみなす (テストと --check が壊れたデータを弾く)。
    let main_hair = valid_hair.iter().copied().find(|r| r.is_main).or_else(|| valid_hair.first().copied());
    if let Some(m) = main_hair {
        let src = if m.origin == "promoted" { Source::Promoted } else { Source::Official };
        let note = m.source_note.as_ref().map(|n| json!({ "note": n }));
        for (facet, v) in [
            ("hair_color", m.hair_color.clone()),
            ("hair_color_secondary", m.hair_color_secondary.clone()),
            ("hair_length", m.hair_length.clone()),
            ("bangs", m.bangs.clone()),
        ] {
            if let Some(v) = v {
                let mut x = cand(facet, v);
                x.source = src;
                x.extra = note.clone();
                c.push(x);
            }
        }
        for (facet, list) in [("hair_style", &m.styles), ("hair_accessory", &m.accessories)] {
            for v in list {
                let mut x = cand(facet, v.as_str());
                x.source = src;
                x.extra = note.clone();
                c.push(x);
            }
        }
    }

    // --- タグの票 ---
    let mut free_tags: Vec<(String, i64)> = Vec::new();
    for t in tags.iter().filter(|t| t.votes >= MIN_TAG_VOTES) {
        let target = match (t.facet.as_deref(), t.facet_value.as_deref()) {
            (Some(f), Some(v)) => facet_def(f).filter(|d| d.taggable).and_then(|d| row_value(d, v).map(|v| (d, v))),
            (None, _) if t.category.as_deref() == Some("personality") => {
                facet_def("traits").map(|d| (d, Value::String(t.tag.clone())))
            }
            _ => None,
        };
        match target {
            Some((def, value)) => c.push(Cand {
                facet: def.key,
                value,
                source: Source::Tag,
                rank: 0,
                derived: false,
                votes: Some(t.votes),
                extra: None,
            }),
            None if t.facet.is_none() => free_tags.push((t.tag.clone(), t.votes)),
            None => {} // 知らない項目・語彙に無い値のタグは捨てる (定義が唯一の正)
        }
    }
    free_tags.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));

    // --- 束ねる ---
    let mut categories: Map<String, Value> =
        Category::ALL.iter().map(|c| (c.key().to_string(), Value::Object(Map::new()))).collect();
    for def in FACETS {
        let mine: Vec<&Cand> = c.iter().filter(|x| x.facet == def.key).collect();
        let Some(entry) = merge_group(def, &mine) else { continue };
        if let Some(m) = categories.get_mut(def.category.key()).and_then(Value::as_object_mut) {
            m.insert(def.key.to_string(), entry);
        }
    }
    if let Some(m) = main_hair {
        let others: Vec<Value> = valid_hair
            .iter()
            .filter(|r| r.id != m.id)
            .map(|r| hairstyle_json(r))
            .collect();
        if let Some(app) = categories.get_mut("appearance").and_then(Value::as_object_mut) {
            app.insert("main_hairstyle_label".into(), m.label.clone().into());
            if !others.is_empty() {
                app.insert("other_hairstyles".into(), Value::Array(others));
            }
        }
    }

    let mut doc = Map::new();
    doc.insert("schema_version".into(), FACTS_SCHEMA_VERSION.into());
    doc.insert("id".into(), idol.id.clone().into());
    doc.insert("name".into(), idol.name.clone().into());
    doc.insert("categories".into(), Value::Object(categories));
    if let Some(d) = idol.description.as_deref().filter(|d| !d.is_empty()) {
        doc.insert("summary".into(), json!({ "value": d, "source": "official" }));
    }
    if !free_tags.is_empty() {
        doc.insert(
            "free_tags".into(),
            Value::Array(free_tags.into_iter().map(|(t, v)| json!({ "value": t, "source": "tag", "votes": v })).collect()),
        );
    }
    Some(Value::Object(doc))
}

impl FacetDef {
    fn full_of_is_set(&self) -> bool {
        self.bulk_full_of.is_some()
    }
}

/// main 以外の髪型 1 つ。項目と同じ形 (`{value, source}`) で、label がつく。
fn hairstyle_json(r: &IdolHairstyleRow) -> Value {
    let src = if r.origin == "promoted" { "promoted" } else { "official" };
    let one = |v: &Option<String>| v.as_ref().map(|v| json!({ "value": v, "source": src }));
    let many = |v: &Vec<String>| {
        (!v.is_empty()).then(|| json!({ "values": v.iter().map(|x| json!({ "value": x, "source": src })).collect::<Vec<_>>() }))
    };
    let mut o = Map::new();
    o.insert("label".into(), r.label.clone().into());
    for (k, v) in [
        ("hair_color", one(&r.hair_color)),
        ("hair_color_secondary", one(&r.hair_color_secondary)),
        ("hair_length", one(&r.hair_length)),
        ("hair_style", many(&r.styles)),
        ("bangs", one(&r.bangs)),
        ("hair_accessory", many(&r.accessories)),
    ] {
        if let Some(v) = v {
            o.insert(k.into(), v);
        }
    }
    Value::Object(o)
}

fn is_solo(snap: &Snapshot, song: u32) -> bool {
    crate::domain::song_list_queries::is_solo_song(snap, song)
        && !crate::domain::song_list_queries::is_hidden_variant(&snap.songs[song as usize])
}

/// 同じ公演に出た回数が多い順の共演者 ((名前, id), 公演数)。
fn frequent_costars(snap: &Snapshot, ii: u32) -> Vec<((String, String), usize)> {
    let mut counts: HashMap<u32, usize> = HashMap::new();
    for &si in &snap.cast_shows_by_idol[ii as usize] {
        for link in &snap.cast_by_show[si as usize] {
            if link.idol != ii {
                *counts.entry(link.idol).or_default() += 1;
            }
        }
    }
    let mut v: Vec<(u32, usize)> = counts.into_iter().collect();
    v.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
    v.into_iter()
        .map(|(i, n)| {
            let o = &snap.idols[i as usize];
            ((o.name.clone(), o.id.clone()), n)
        })
        .collect()
}

fn entry_value(def: &FacetDef, c: &Cand) -> Value {
    let mut o = Map::new();
    o.insert("value".into(), c.value.clone());
    o.insert("source".into(), c.source.key().into());
    if c.derived {
        o.insert("derived".into(), true.into());
    }
    if let Some(v) = c.votes {
        o.insert("votes".into(), v.into());
    }
    if let Some(e) = &c.extra {
        o.insert("extra".into(), e.clone());
    }
    let _ = def;
    Value::Object(o)
}

/// 1 つの項目 (の 1 つの版) の候補を束ねる。優先は official > promoted > tag、
/// 同じ出どころの中では rank (列 → 行 → 推定)。
fn merge_group(def: &FacetDef, group: &[&Cand]) -> Option<Value> {
    if group.is_empty() {
        return None;
    }
    match def.kind {
        Kind::Multi => {
            // 公式・昇格の値が 1 つでもあれば、それが全部 (タグの値は足さない)。
            let best_source = group.iter().map(|c| c.source).min()?;
            let mut seen: BTreeSet<String> = BTreeSet::new();
            let mut items: Vec<Value> = Vec::new();
            let mut sorted: Vec<&&Cand> = group.iter().filter(|c| c.source == best_source).collect();
            if best_source == Source::Tag {
                sorted.sort_by(|a, b| b.votes.cmp(&a.votes));
            }
            for c in sorted {
                if seen.insert(json_key(&c.value)) {
                    items.push(entry_value(def, c));
                }
            }
            Some(json!({ "values": items }))
        }
        _ => {
            let best = group.iter().min_by(|a, b| (a.source, a.rank).cmp(&(b.source, b.rank)).then_with(|| {
                b.votes.cmp(&a.votes)
            }))?;
            Some(entry_value(def, best))
        }
    }
}

// ---------------------------------------------------------------------------
// Jev に渡す文面
// ---------------------------------------------------------------------------

fn value_text(v: &Value) -> String {
    match v {
        Value::String(s) => s.clone(),
        Value::Bool(b) => if *b { "はい".into() } else { "いいえ".into() },
        Value::Object(o) => o.get("name").and_then(Value::as_str).map(|n| {
            format!("{n} ({})", o.get("hex").and_then(Value::as_str).unwrap_or(""))
        }).unwrap_or_else(|| v.to_string()),
        other => other.to_string(),
    }
}

fn entry_text(def: &FacetDef, e: &Value) -> Option<String> {
    let unit = def.unit.unwrap_or("");
    let mark = |item: &Value| -> String {
        let mut s = format!("{}{}", value_text(&item["value"]), if item["value"].is_number() { unit } else { "" });
        match item["source"].as_str() {
            Some("tag") => s.push_str(&format!("（ファン投票 {}票）", item["votes"].as_i64().unwrap_or(0))),
            _ => {}
        }
        if item["derived"] == json!(true) && def.auto == Auto::Estimate {
            s.push_str("（推定）");
        }
        s
    };
    if let Some(items) = e.get("values").and_then(Value::as_array) {
        let parts: Vec<String> = items.iter().map(mark).collect();
        (!parts.is_empty()).then(|| parts.join("、"))
    } else {
        Some(mark(e))
    }
}

/// 髪型 1 つぶん (`appearance` か `other_hairstyles` の 1 件) の短い文。「金色のロング（ウェーブ、アホ毛、リボン）」。
fn hair_text(h: &Value) -> Option<String> {
    let single = |k: &str| h.get(k).and_then(|e| e["value"].as_str()).map(String::from);
    let many = |k: &str| -> Vec<String> {
        h.get(k)
            .and_then(|e| e["values"].as_array())
            .map(|a| a.iter().filter_map(|v| v["value"].as_str().map(String::from)).collect())
            .unwrap_or_default()
    };
    let mut head = String::new();
    if let Some(c) = single("hair_color") {
        head.push_str(&c);
        head.push_str(if c.ends_with('色') { "の" } else { "色の" });
    }
    if let Some(c) = single("hair_color_secondary") {
        head.push_str(&format!("（2色目 {c}）"));
    }
    if let Some(l) = single("hair_length") {
        head.push_str(&l);
    }
    let mut details = many("hair_style");
    if let Some(b) = single("bangs") {
        details.push(format!("前髪 {b}"));
    }
    details.extend(many("hair_accessory"));
    if !details.is_empty() {
        head.push_str(&format!("（{}）", details.join("、")));
    }
    (!head.is_empty()).then_some(head)
}

/// `/facts` の文書を Jev に渡す文面にする。カテゴリごとに「見出し: 値」の行。
///
/// 照合専用の項目 (`jev: false`) は入れない。髪は main の髪型を先に「髪: 金色のロング（…） (基本)」、
/// ほかの髪型を「覚醒後: 茶色のショート」のように短く添える。
pub fn jev_lines(doc: &Value) -> String {
    let mut out = String::new();
    let cats = &doc["categories"];
    for cat in Category::ALL {
        let mut lines: Vec<String> = Vec::new();
        if cat == Category::Appearance {
            let app = &cats["appearance"];
            if let Some(main) = hair_text(app) {
                let label = app["main_hairstyle_label"].as_str().unwrap_or(MAIN_HAIRSTYLE_LABEL);
                let mut line = format!("髪: {main} ({label})");
                if let Some(others) = app["other_hairstyles"].as_array() {
                    for o in others {
                        if let Some(t) = hair_text(o) {
                            line.push_str(&format!("。{}: {t}", o["label"].as_str().unwrap_or("別の髪型")));
                        }
                    }
                }
                lines.push(line);
            }
        }
        for def in FACETS.iter().filter(|d| d.category == cat && d.jev && !d.hairstyle) {
            if let Some(t) = cats[cat.key()].get(def.key).and_then(|e| entry_text(def, e)) {
                lines.push(format!("{}: {}", def.label, t));
            }
        }
        if !lines.is_empty() {
            out.push_str(&format!("## {}\n{}\n", cat.label(), lines.join("\n")));
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::snapshot::{IdolFacetRow, IdolHairstyleRow};
    use crate::test_support::bundle_snapshot;

    fn row(idol: &str, facet: &str, value: &str, origin: &str) -> IdolFacetRow {
        IdolFacetRow {
            id: format!("{idol}{facet}{value}"),
            idol_id: idol.into(),
            facet: facet.into(),
            value: value.into(),
            origin: origin.into(),
            source_note: None,
            sort_order: 0,
        }
    }

    fn hair(idol: &str, label: &str, main: bool, color: &str, length: &str, styles: &[&str]) -> IdolHairstyleRow {
        IdolHairstyleRow {
            id: format!("{idol}{label}"),
            idol_id: idol.into(),
            label: label.into(),
            is_main: main,
            hair_color: Some(color.into()),
            hair_length: Some(length.into()),
            styles: styles.iter().map(|s| s.to_string()).collect(),
            origin: "official".into(),
            ..Default::default()
        }
    }

    /// 実データの snapshot に idol_facets / idol_hairstyles の行だけ足したもの。
    fn with_rows(rows: Vec<IdolFacetRow>) -> Snapshot {
        with_all(rows, vec![])
    }

    fn with_all(rows: Vec<IdolFacetRow>, hairs: Vec<IdolHairstyleRow>) -> Snapshot {
        let mut raw = crate::outbound::sqlite_loader::load_raw_tables(crate::test_support::bundle_path()).unwrap();
        raw.idol_facets = rows;
        raw.idol_hairstyles = hairs;
        crate::domain::snapshot_build::build(raw)
    }

    fn tag(tag: &str, facet: Option<&str>, value: Option<&str>, votes: i64) -> TagFacetInput {
        TagFacetInput {
            tag: tag.into(),
            facet: facet.map(String::from),
            facet_value: value.map(String::from),
            category: None,
            votes,
        }
    }

    fn facts(snap: &Snapshot, id: &str, tags: &[TagFacetInput]) -> Value {
        build_idol_facts(snap, id, &PersonaInput::default(), tags).unwrap()
    }

    #[test]
    fn 定義のキーは重複せず_語彙も重複しない() {
        let mut keys = BTreeSet::new();
        for d in FACETS {
            assert!(keys.insert(d.key), "項目キーが重複: {}", d.key);
            assert!(!["main_hairstyle_label", "other_hairstyles"].contains(&d.key), "予約語");
            if let Some(v) = d.vocab {
                let set: BTreeSet<_> = v.iter().collect();
                assert_eq!(set.len(), v.len(), "{} の語彙が重複", d.key);
                assert!(v.iter().all(|s| !s.is_empty() && s.trim() == *s), "{} の語彙", d.key);
                assert!(matches!(d.kind, Kind::Single | Kind::Multi), "{}", d.key);
            }
            if let Some(s) = d.bulk_full_of {
                assert!(!d.jev, "{} は照合専用", d.key);
                let summary = facet_def(s).unwrap_or_else(|| panic!("{} のまとめ側 {s} が無い", d.key));
                assert!(summary.jev, "{} のまとめ側は Jev に渡す", d.key);
            }
            if d.hairstyle {
                assert_eq!(d.category, Category::Appearance, "{}", d.key);
            }
            if d.taggable {
                assert!(d.auto == Auto::No && d.bulk_full_of.is_none() && !d.hairstyle, "{}", d.key);
            }
            assert!(!d.label.is_empty());
        }
    }

    #[test]
    fn 定義の_json_は_facets_json_と一致する() {
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("facets.json");
        let text = serde_json::to_string_pretty(&definitions_json()).unwrap() + "\n";
        if std::env::var("UPDATE_FACETS_JSON").is_ok() {
            std::fs::write(&path, &text).unwrap();
        }
        let on_disk = std::fs::read_to_string(&path).expect("imas-core/facets.json が無い (UPDATE_FACETS_JSON=1 cargo test idol_facets)");
        assert!(on_disk == text, "facets.json が定義とずれている。UPDATE_FACETS_JSON=1 cargo test idol_facets で書き直す");
    }

    #[test]
    fn 年齢帯と学校の段階の境目() {
        assert_eq!(age_band(9), Some("10歳未満"));
        assert_eq!(age_band(10), Some("10代"));
        assert_eq!(age_band(19), Some("10代"));
        assert_eq!(age_band(20), Some("20代"));
        assert_eq!(age_band(39), Some("30代"));
        assert_eq!(age_band(40), Some("40代以上"));
        assert_eq!(school_stage_from_age(12), Some("小学生"));
        assert_eq!(school_stage_from_age(13), Some("中学生"));
        assert_eq!(school_stage_from_age(15), Some("中学生"));
        assert_eq!(school_stage_from_age(16), Some("高校生"));
        assert_eq!(school_stage_from_age(18), Some("高校生"));
        assert_eq!(school_stage_from_age(19), None);
        assert_eq!(school_stage_from_age(22), None);
        assert_eq!(school_stage_from_age(23), Some("社会人"));
        assert_eq!(height_band(139.9), Some("140cm未満"));
        assert_eq!(height_band(140.0), Some("140cm台"));
        assert_eq!(height_band(169.0), Some("160cm台"));
        assert_eq!(height_band(170.0), Some("170cm以上"));
        assert_eq!(birth_month("--01-18"), Some(1));
        assert_eq!(birth_month("--13-01"), None);
    }

    #[test]
    fn 出身地の正規化と地方() {
        assert_eq!(normalize_birthplace("兵庫"), Some(("兵庫".into(), "近畿")));
        assert_eq!(normalize_birthplace("神奈川県"), Some(("神奈川".into(), "関東")));
        assert_eq!(normalize_birthplace("京都？"), Some(("京都".into(), "近畿")));
        assert_eq!(normalize_birthplace("名古屋"), Some(("愛知".into(), "中部")));
        assert_eq!(normalize_birthplace("札幌"), Some(("北海道".into(), "北海道")));
        assert_eq!(normalize_birthplace("沖縄"), Some(("沖縄".into(), "九州・沖縄")));
        assert_eq!(normalize_birthplace("イギリス"), Some(("イギリス".into(), "海外")));
        assert_eq!(normalize_birthplace("海の向こう"), None);
        assert_eq!(normalize_constellation("花も恥じらう乙女座"), Some("乙女座"));
        for (p, r) in PREFECTURES {
            assert!(REGIONS.contains(r), "{p}");
        }
    }

    #[test]
    fn 全アイドルで束が組めて_値は語彙に収まり_禁止値が出ない() {
        let snap = bundle_snapshot();
        let banned: Vec<&str> = snap
            .songs
            .iter()
            .flat_map(|s| [s.lyrics_url.as_deref(), s.preview_url.as_deref()])
            .flatten()
            .filter(|v| !v.is_empty())
            .collect();
        for idol in &snap.idols {
            let doc = facts(snap, &idol.id, &[]);
            let text = doc.to_string();
            for key in ["lyrics_url", "preview_url", "weight", "three_size", "bust", "waist"] {
                assert!(!text.contains(&format!("\"{key}\"")), "{key}");
            }
            for v in &banned {
                assert!(!text.contains(v));
            }
            assert!(text.len() < 80_000, "{} の束が大きすぎる: {}", idol.id, text.len());
            for (ckey, cat) in doc["categories"].as_object().unwrap() {
                for (fkey, e) in cat.as_object().unwrap() {
                    if fkey == "main_hairstyle_label" || fkey == "other_hairstyles" {
                        continue;
                    }
                    let def = facet_def(fkey).unwrap_or_else(|| panic!("定義に無い項目 {fkey}"));
                    assert_eq!(def.category.key(), ckey);
                    let items: Vec<&Value> = match def.kind {
                        Kind::Multi => e["values"].as_array().unwrap().iter().collect(),
                        _ => vec![e],
                    };
                    for it in items {
                        assert!(matches!(it["source"].as_str(), Some("official" | "promoted" | "tag")));
                        if let (Some(v), Some(s)) = (def.vocab, it["value"].as_str()) {
                            assert!(v.contains(&s), "{} の値 {s} が語彙に無い", fkey);
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn 有村麻央の公式の項目と自動の項目() {
        let snap = bundle_snapshot();
        let d = facts(snap, "gakuen_有村麻央", &[]);
        let p = &d["categories"]["profile"];
        assert_eq!(p["age"]["value"], 17);
        assert_eq!(p["age_band"]["value"], "10代");
        assert_eq!(p["age_band"]["derived"], true);
        assert_eq!(p["school_stage"]["value"], "高校生");
        assert_eq!(p["birth_month"]["value"], 1);
        assert_eq!(p["birthplace"]["value"], "兵庫");
        assert_eq!(p["birthplace_region"]["value"], "近畿");
        assert_eq!(p["grade"]["value"], "1年");
        assert_eq!(p["height_band"]["value"], "150cm台");
        assert_eq!(d["categories"]["appearance"]["image_color"]["value"]["hex"], "#A453A6");
        assert!(d["categories"]["appearance"]["image_color"]["value"]["name"].as_str().unwrap().len() > 0);
        assert_eq!(d["categories"]["relations"]["agency"]["value"], "初星学園");
        assert!(d["summary"]["value"].as_str().unwrap().contains("カッコいい"));
    }

    #[test]
    fn 小宮果穂は小学生_桜庭薫は社会人() {
        let snap = bundle_snapshot();
        let k = facts(snap, "sc_小宮果穂", &[]);
        assert_eq!(k["categories"]["profile"]["age"]["value"], 12);
        assert_eq!(k["categories"]["profile"]["school_stage"]["value"], "小学生");
        assert_eq!(k["categories"]["profile"]["school_stage"]["derived"], true);
        assert_eq!(k["categories"]["profile"]["age_band"]["value"], "10代");
        let s = facts(snap, "sidem_桜庭薫", &[]);
        assert_eq!(s["categories"]["profile"]["school_stage"]["value"], "社会人");
        assert_eq!(s["categories"]["profile"]["age_band"]["value"], "20代");
    }

    #[test]
    fn 出どころの優先は_公式_昇格_タグ() {
        let id = "765as_天海春香";
        let snap = with_all(
            vec![
                row(id, "dialect", "関西弁", "promoted"),
                row(id, "school_stage", "高校生", "official"),
            ],
            vec![hair(id, "基本", true, "茶", "ボブ〜ミディアム", &[])],
        );
        let tags = [
            tag("黒髪", Some("hair_color"), Some("黒"), 50), // 髪はタグから足せない
            tag("方言", Some("dialect"), Some("博多弁"), 30),
            tag("優しい", None, None, 10),
            tag("天然", Some("traits"), Some("天然"), 8),
            tag("少ない", Some("traits"), Some("少ない"), 1), // 足切り
            tag("好きな食べ物", Some("favorite_foods"), Some("ケーキ"), 4),
        ];
        let d = facts(&snap, id, &tags);
        let a = &d["categories"]["appearance"];
        assert_eq!(a["hair_color"]["value"], "茶");
        assert_eq!(a["hair_color"]["source"], "official");
        // 昇格の値がタグの票に勝つ。
        assert_eq!(d["categories"]["personality"]["dialect"]["value"], "関西弁");
        assert_eq!(d["categories"]["personality"]["dialect"]["source"], "promoted");
        // 推定の学校の段階は公式の行に負ける (年齢 17 → 高校生と同じでも出どころは official)。
        let ss = &d["categories"]["profile"]["school_stage"];
        assert_eq!(ss["source"], "official");
        assert!(ss.get("derived").is_none());
        // タグだけの項目は source:tag と票数。
        let f = &d["categories"]["likes"]["favorite_foods"]["values"][0];
        assert_eq!((f["value"].as_str(), f["source"].as_str(), f["votes"].as_i64()), (Some("ケーキ"), Some("tag"), Some(4)));
        let traits = d["categories"]["personality"]["traits"]["values"].as_array().unwrap();
        assert_eq!(traits.len(), 1);
        // facet の無いタグは free_tags、足切りのタグは出ない。
        assert_eq!(d["free_tags"][0]["value"], "優しい");
        assert!(!d.to_string().contains("少ない"));
    }

    #[test]
    fn 公式の複数値があればタグの値は足さない() {
        let id = "765as_天海春香";
        let snap = with_rows(vec![row(id, "favorite_foods", "お菓子", "official")]);
        let d = facts(&snap, id, &[tag("x", Some("favorite_foods"), Some("ケーキ"), 9)]);
        let v = d["categories"]["likes"]["favorite_foods"]["values"].as_array().unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0]["value"], "お菓子");
    }

    #[test]
    fn 語彙に無い値と自動の項目への行と髪の行は捨てる() {
        let id = "765as_天海春香";
        let snap = with_all(
            vec![
                row(id, "eye_color", "ラメ入りの虹色", "official"),
                row(id, "age_band", "30代", "official"),
                row(id, "hair_color", "金", "official"), // 髪は idol_hairstyles にだけ
            ],
            vec![],
        );
        let d = facts(&snap, id, &[]);
        assert!(d["categories"]["appearance"].get("eye_color").is_none());
        assert!(d["categories"]["appearance"].get("hair_color").is_none());
        assert_eq!(d["categories"]["profile"]["age_band"]["value"], "10代");
    }

    #[test]
    fn 髪以外の容姿は項目で持つ() {
        let id = "sidem_桜庭薫";
        let snap = with_rows(vec![
            row(id, "glasses", "true", "official"),
            row(id, "eye_color", "青", "official"),
            row(id, "features", "泣きぼくろ", "official"),
        ]);
        let a = &facts(&snap, id, &[])["categories"]["appearance"];
        assert_eq!(a["glasses"]["value"], true);
        assert_eq!(a["eye_color"]["value"], "青");
        assert_eq!(a["features"]["values"][0]["value"], "泣きぼくろ");
        assert_eq!(a["image_color"]["value"]["hex"].as_str().map(|h| h.len()), Some(7));
        assert!(a.get("main_hairstyle_label").is_none(), "髪型が無ければ髪の欄は出ない");
    }

    #[test]
    fn 美希は基本の髪型と覚醒後の髪型を持つ() {
        let id = "765as_星井美希";
        let snap = with_all(
            vec![],
            vec![
                hair(id, "基本", true, "金", "ロング", &["ウェーブ", "アホ毛"]),
                hair(id, "覚醒後", false, "茶", "ショート", &[]),
            ],
        );
        let d = facts(&snap, id, &[]);
        let a = &d["categories"]["appearance"];
        // main の髪型が hair_* の値になる。
        assert_eq!(a["hair_color"]["value"], "金");
        assert_eq!(a["hair_length"]["value"], "ロング");
        assert_eq!(a["hair_style"]["values"].as_array().unwrap().len(), 2);
        assert_eq!(a["main_hairstyle_label"], "基本");
        // ほかの髪型は label つき。
        let o = &a["other_hairstyles"][0];
        assert_eq!(o["label"], "覚醒後");
        assert_eq!(o["hair_color"]["value"], "茶");
        assert_eq!(o["hair_length"]["value"], "ショート");
        // Jev へは main が先、ほかが後。
        let text = jev_lines(&d);
        assert!(text.contains("髪: 金色のロング（ウェーブ、アホ毛） (基本)。覚醒後: 茶色のショート"), "{text}");
    }

    #[test]
    fn セカンドヘアのある子の髪型は_ポニーテールを別の髪型として持つ() {
        // 例示用の仮の値 (デレステのセカンドヘアの実データの調査は別。docs/ARCHITECTURE-facets.md)。
        let id = "cg_島村卯月";
        let snap = with_all(
            vec![],
            vec![
                hair(id, "セカンドヘア", false, "茶", "ロング", &["ポニーテール"]),
                hair(id, "基本", true, "茶", "ロング", &["ストレート"]),
            ],
        );
        let d = facts(&snap, id, &[]);
        let a = &d["categories"]["appearance"];
        assert_eq!(a["hair_style"]["values"][0]["value"], "ストレート");
        assert_eq!(a["other_hairstyles"][0]["label"], "セカンドヘア");
        assert_eq!(a["other_hairstyles"][0]["hair_style"]["values"][0]["value"], "ポニーテール");
        assert!(jev_lines(&d).contains("セカンドヘア: 茶色のロング（ポニーテール）"));
    }

    #[test]
    fn 髪型の_main_はちょうど_1_つで_語彙と重複を検査する() {
        let id = "i";
        let a = hair(id, "基本", true, "金", "ロング", &[]);
        let b = hair(id, "覚醒後", false, "茶", "ショート", &[]);
        assert!(hairstyle_set_problems(id, &[&a, &b]).is_empty());
        assert!(hairstyle_set_problems(id, &[]).is_empty(), "髪型が無い人は検査しない");
        let none = hair(id, "基本", false, "金", "ロング", &[]);
        assert_eq!(hairstyle_set_problems(id, &[&none, &b]).len(), 1);
        let two = hair(id, "別", true, "金", "ロング", &[]);
        assert_eq!(hairstyle_set_problems(id, &[&a, &two]).len(), 1);
        let dup = hair(id, "基本", false, "茶", "ショート", &[]);
        assert!(!hairstyle_set_problems(id, &[&a, &dup]).is_empty());
        let bad = hair(id, "基本", true, "虹", "ロング", &["ツインテール"]);
        assert_eq!(hairstyle_row_problems(&bad).len(), 1);
        // 語彙に無い髪型の行は束に出ない。
        let id = "765as_天海春香";
        let snap = with_all(vec![], vec![hair(id, "基本", true, "虹", "ロング", &[])]);
        assert!(facts(&snap, id, &[])["categories"]["appearance"].get("hair_color").is_none());
    }

    #[test]
    fn 数が多い項目はまとめと全件の両方を持つ() {
        let snap = bundle_snapshot();
        let d = facts(snap, "765as_天海春香", &[]);
        let w = &d["categories"]["works"];
        let rep = w["representative_songs"]["values"].as_array().unwrap();
        let all = w["performed_songs"]["values"].as_array().unwrap();
        assert!(rep.len() <= REPRESENTATIVE_LIMIT && rep.len() >= 1);
        assert!(all.len() >= rep.len());
        assert_eq!(rep[0]["value"], all[0]["value"]);
        assert!(w["songs"]["values"].as_array().unwrap().len() >= 1);
        assert!(w["show_count"]["value"].as_i64().unwrap() >= 1);
        assert!(w["latest_show"]["value"].as_str().unwrap().len() > 8);
        let rel = &d["categories"]["relations"];
        assert!(rel["units"]["values"].as_array().unwrap().len() >= rel["representative_units"]["values"].as_array().unwrap().len());
        assert!(rel["frequent_costars"]["values"].as_array().unwrap().len() <= REPRESENTATIVE_LIMIT);
        // 照合専用の全件は Jev の文面に出ない。
        let jev = jev_lines(&d);
        assert!(jev.contains("代表曲") && !jev.contains("持ち歌 (全件)") && !jev.contains("ライブで歌った曲 (全件)"));
    }

    #[test]
    fn 話し方は人格の公式の項目になる() {
        let snap = bundle_snapshot();
        let p = PersonaInput {
            first_person: vec!["私".into()],
            producer_call: vec!["プロデューサーさん".into()],
            catchphrases: vec!["○○ですよ、○○！".into()],
            sentence_endings: vec!["〜ですよ".into()],
            politeness: Some("混在：プロデューサーには丁寧語寄り".into()),
            tone_notes: Some("前向き".into()),
        };
        let d = build_idol_facts(snap, "765as_天海春香", &p, &[]).unwrap();
        let pe = &d["categories"]["personality"];
        assert_eq!(pe["first_person"]["values"][0]["value"], "私");
        assert_eq!(pe["speech_style"]["value"], "敬語とタメ口の混在");
        assert_eq!(speech_style_from("丁寧語"), Some("敬語"));
        assert_eq!(speech_style_from("不明"), None);
    }

    #[test]
    fn 行の_id_は単一値で項目まで_複数値で値まで決まる() {
        let a = facet_row_key("i", "dialect", "関西弁", false);
        assert_eq!(a, facet_row_key("i", "dialect", "博多弁", false));
        assert_ne!(facet_row_key("i", "favorite_foods", "A", true), facet_row_key("i", "favorite_foods", "B", true));
        assert_ne!(hairstyle_row_key("i", "基本"), hairstyle_row_key("i", "覚醒後"));
    }
}
