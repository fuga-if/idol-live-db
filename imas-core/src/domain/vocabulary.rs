//! 画面に出す語彙: DB の生値 → 日本語。面ごとの**短い形**と**正式な形**の両方を持つ。
//!
//! 同じ生値が画面ごとに別の日本語で出ていた — 曲種別の「ソロ」と「ソロ曲」、催しの
//! 「リリイベ」と「リリースイベント」、チケットの「チケット発売 / 抽選発表」と
//! 「受付開始 / 当落発表」(アプリの詳細は「申込期限」)。どちらの形をどの面で使うかは
//! 画面が選ぶが、**語そのものはここにしか書かない** (Q-08f / Q-08g)。
//!
//! - `short_label`: チップ・絞り込み・行の札など、幅の狭い所
//! - `label`: 見出し・詳細・Web の表など、正式な形
//!
//! 未知の生値の扱いは語彙ごとに違うので、引く関数の doc に書いた
//! (曲種別は出さない、催しの種別は「その他」、など)。

/// 1 つの生値の言い方 (静的な表の 1 行)。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Term {
    /// DB の生値 (`solo` / `release_event` 等)。
    pub value: &'static str,
    /// 幅の狭い所に出す短い形 (`ソロ` / `リリイベ`)。
    pub short_label: &'static str,
    /// 正式な形 (`ソロ曲` / `リリースイベント`)。
    pub label: &'static str,
}

const fn term(value: &'static str, short_label: &'static str, label: &'static str) -> Term {
    Term { value, short_label, label }
}

/// 曲種別 (`songs.song_type`)。並びはアプリの絞り込みの並び (ソロ → ユニット → 全体曲) に、
/// 残りの 2 つを続けたもの。
pub const SONG_TYPES: [Term; 5] = [
    term("solo", "ソロ", "ソロ曲"),
    term("unit", "ユニット", "ユニット曲"),
    term("all", "全体曲", "全体曲"),
    term("cover", "カバー", "カバー"),
    term("tie_in", "タイアップ", "タイアップ"),
];

/// 古い端末 DB に残っている曲種別 (今のマスタには無い)。アプリの表示を変えないために引ける
/// ようにしてあるが、選択肢には出さない。
const LEGACY_SONG_TYPES: [Term; 2] = [
    term("original", "オリジナル", "オリジナル"),
    term("unknown", "不明", "不明"),
];

/// 催しの種別 (`events.kind`)。
pub const EVENT_KINDS: [Term; 6] = [
    term("live", "ライブ", "ライブ"),
    term("festival", "フェス", "フェス"),
    term("release_event", "リリイベ", "リリースイベント"),
    term("radio", "ラジオ", "ラジオ"),
    term("stream", "配信", "配信"),
    term("other", "その他", "その他"),
];

/// 催しの性格 (`events.event_type`)。未分類 (空文字) は語彙に無い。
pub const EVENT_TYPES: [Term; 7] = [
    term("anniversary", "周年", "周年"),
    term("orchestra", "オーケストラ", "オーケストラ"),
    term("external_event", "外部イベント", "外部イベント"),
    term("birthday", "バースデー", "バースデー"),
    term("release_event", "リリイベ", "リリースイベント"),
    term("broadcast", "番組・配信", "番組・配信"),
    term("live", "ライブ", "ライブ"),
];

/// 参加形態 (`user_marks` の attended の `text_value`)。券の形態 (`show_tickets.kind`) も同じ語。
pub const ATTENDANCE_TYPES: [Term; 3] = [
    term("live", "現地", "現地"),
    term("stream", "配信", "配信"),
    term("live_viewing", "LV", "ライブビューイング"),
];

/// チケットの日程 (`events` の 3 列)。語は Q-08g で「受付開始 / 申込締切 / 当落発表」に決めた。
pub const TICKET_DATES: [Term; 3] = [
    term("ticket_open_date", "受付開始", "受付開始"),
    term("ticket_deadline", "申込締切", "申込締切"),
    term("ticket_lottery_date", "当落発表", "当落発表"),
];

/// 受付開始 → 申込締切 の期間の呼び名 (カレンダーの帯)。
pub const TICKET_PERIOD_LABEL: &str = "受付期間";

/// コミュニティのタグのカテゴリ。曲・アイドル・ユニットで語彙が別。
pub const SONG_TAG_CATEGORIES: [Term; 4] = [
    term("mood", "ムード", "ムード"),
    term("scene", "シーン", "シーン"),
    term("special", "特別", "特別"),
    term("free", "フリー", "フリー"),
];
pub const IDOL_TAG_CATEGORIES: [Term; 4] = [
    term("personality", "性格", "性格"),
    term("charm", "魅力・外見", "魅力・外見"),
    term("talent", "特技", "特技"),
    term("free", "フリー", "フリー"),
];
pub const UNIT_TAG_CATEGORIES: [Term; 4] = [
    term("concept", "コンセプト", "コンセプト"),
    term("mood", "雰囲気", "雰囲気"),
    term("charm", "魅力", "魅力"),
    term("free", "フリー", "フリー"),
];

/// タグのカテゴリを付けないときの選択肢の言葉 (値は空文字)。
pub const TAG_CATEGORY_NONE_LABEL: &str = "なし";

fn find(table: &'static [Term], value: &str) -> Option<&'static Term> {
    table.iter().find(|t| t.value == value)
}

/// 曲種別。知らない値は `None` (捏造せず、受け手は出さない)。古い端末 DB の `group` は
/// ユニットとして読む。
pub fn song_type(value: &str) -> Option<&'static Term> {
    match value {
        "group" => Some(&SONG_TYPES[1]),
        _ => find(&SONG_TYPES, value).or_else(|| find(&LEGACY_SONG_TYPES, value)),
    }
}

/// 催しの種別。知らない値は「その他」(一覧から消さずに出す。Q-08l)。
pub fn event_kind(value: &str) -> &'static Term {
    find(&EVENT_KINDS, value).unwrap_or(&EVENT_KINDS[5])
}

/// 催しの性格。未分類 (空文字) と知らない値は `None` (種別を出さない)。
pub fn event_type(value: &str) -> Option<&'static Term> {
    find(&EVENT_TYPES, value)
}

/// 参加形態。知らない値は `None` (形態の無い古いマークを現地とみなすのは
/// [`crate::domain::collection_gap`] の規則で、語彙の側では決めない)。
pub fn attendance_type(value: &str) -> Option<&'static Term> {
    find(&ATTENDANCE_TYPES, value)
}

// ---------------------------------------------------------------------------
// FFI で渡す形 (アプリは起動時に 1 回引いて持っておく)
// ---------------------------------------------------------------------------

/// 1 つの生値の言い方。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct VocabularyTerm {
    pub value: String,
    pub short_label: String,
    pub label: String,
}

impl From<&Term> for VocabularyTerm {
    fn from(t: &Term) -> Self {
        Self {
            value: t.value.to_string(),
            short_label: t.short_label.to_string(),
            label: t.label.to_string(),
        }
    }
}

/// 語彙の一式。並びは選択肢として出す並び。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct Vocabulary {
    /// 曲種別 5 種 (solo / unit / all / cover / tie_in)。
    pub song_types: Vec<VocabularyTerm>,
    /// 催しの種別 6 種 (最後が `other` = その他)。
    pub event_kinds: Vec<VocabularyTerm>,
    /// 催しの性格 7 種。
    pub event_types: Vec<VocabularyTerm>,
    /// 参加形態 3 種 (券の形態も同じ語)。
    pub attendance_types: Vec<VocabularyTerm>,
    /// チケットの日程 3 つ (value は `events` の列名)。
    pub ticket_dates: Vec<VocabularyTerm>,
    pub ticket_period_label: String,
    pub song_tag_categories: Vec<VocabularyTerm>,
    pub idol_tag_categories: Vec<VocabularyTerm>,
    pub unit_tag_categories: Vec<VocabularyTerm>,
    pub tag_category_none_label: String,
}

fn terms(table: &[Term]) -> Vec<VocabularyTerm> {
    table.iter().map(VocabularyTerm::from).collect()
}

pub fn vocabulary() -> Vocabulary {
    Vocabulary {
        song_types: terms(&SONG_TYPES),
        event_kinds: terms(&EVENT_KINDS),
        event_types: terms(&EVENT_TYPES),
        attendance_types: terms(&ATTENDANCE_TYPES),
        ticket_dates: terms(&TICKET_DATES),
        ticket_period_label: TICKET_PERIOD_LABEL.to_string(),
        song_tag_categories: terms(&SONG_TAG_CATEGORIES),
        idol_tag_categories: terms(&IDOL_TAG_CATEGORIES),
        unit_tag_categories: terms(&UNIT_TAG_CATEGORIES),
        tag_category_none_label: TAG_CATEGORY_NONE_LABEL.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    /// アプリのチップ・絞り込みが出していた短い形と同じであること。
    #[test]
    fn short_labels_match_what_the_apps_show() {
        let short = |v: &str| song_type(v).map(|t| t.short_label);
        assert_eq!(short("solo"), Some("ソロ"));
        assert_eq!(short("unit"), Some("ユニット"));
        assert_eq!(short("group"), Some("ユニット"), "古い端末 DB の group");
        assert_eq!(short("original"), Some("オリジナル"));
        assert_eq!(event_kind("release_event").short_label, "リリイベ");
        assert_eq!(event_type("broadcast").map(|t| t.short_label), Some("番組・配信"));
        assert_eq!(attendance_type("live_viewing").map(|t| t.short_label), Some("LV"));
        assert_eq!(attendance_type("live").map(|t| t.short_label), Some("現地"));
    }

    #[test]
    fn unknown_values_follow_each_vocabulary_rule() {
        assert_eq!(song_type("medley"), None, "曲種別は捏造しない");
        assert_eq!(event_kind("mystery").value, "other", "催しの種別はその他");
        assert_eq!(event_kind("mystery").label, "その他");
        assert_eq!(event_type(""), None, "未分類は種別を出さない");
        assert_eq!(attendance_type(""), None);
    }

    /// 選択肢に出す語彙は値が重複しない (重複すると選択肢が 2 つ並ぶ)。
    #[test]
    fn values_are_unique_within_each_vocabulary() {
        let v = vocabulary();
        for (name, list) in [
            ("song_types", &v.song_types),
            ("event_kinds", &v.event_kinds),
            ("event_types", &v.event_types),
            ("attendance_types", &v.attendance_types),
            ("ticket_dates", &v.ticket_dates),
            ("song_tag_categories", &v.song_tag_categories),
            ("idol_tag_categories", &v.idol_tag_categories),
            ("unit_tag_categories", &v.unit_tag_categories),
        ] {
            let values: HashSet<&str> = list.iter().map(|t| t.value.as_str()).collect();
            assert_eq!(values.len(), list.len(), "{name}");
            assert!(list.iter().all(|t| !t.short_label.is_empty() && !t.label.is_empty()), "{name}");
        }
        assert_eq!(v.song_types.len(), 5, "Web の曲種別は 5 種すべて出す (Q-08f)");
    }

    /// マスタに入っている曲種別・催しの種別・性格は、どれも語彙で引ける。
    #[test]
    fn every_value_in_the_master_has_a_word() {
        let snap = crate::test_support::bundle_snapshot();
        for song in &snap.songs {
            let Some(t) = song.song_type.as_deref() else { continue };
            assert!(song_type(t).is_some(), "{} の {t}", song.id);
        }
        for event in &snap.events {
            assert_ne!(event_kind(&event.kind).value, "other", "{} の {}", event.id, event.kind);
            if !event.event_type.is_empty() {
                assert!(event_type(&event.event_type).is_some(), "{} の {}", event.id, event.event_type);
            }
        }
    }
}
