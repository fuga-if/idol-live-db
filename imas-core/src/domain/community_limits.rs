//! コミュニティ投稿の上限: 入力欄の文字数と、1 人あたりの票数。
//!
//! 同じ数 (タグ名 30・説明 300・表示名 40・お題 80 / 280・票 3) が両 OS の画面に
//! 直書きされていて、数え方も割れていた (iOS は書記素、Android は UTF-16 か切り詰め無し)。
//! **数え方はサーバに揃える** — 表示名はコードポイント (Q-08o)、それ以外はサーバが
//! JavaScript の `.length` で見ているので UTF-16 の単位。サーバより緩く数えると、
//! 画面では入ったのに送ると弾かれる。
//!
//! 画面は、入力のたびに [`clamp_input`] を通し、送信の可否を [`input_is_acceptable`] で、
//! 数の表示を [`input_length`] で出す。

/// 上限のある入力欄。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq)]
pub enum InputField {
    /// タグ名 (前後の空白を除いて 1〜30)。
    TagName,
    /// タグの説明 (任意・300 まで)。
    TagDescription,
    /// 表示名 (前後の空白を除いて 1〜40。**コードポイント**で数える)。
    DisplayName,
    /// お題のタイトル (前後の空白を除いて 1〜80)。
    PollTitle,
    /// お題の説明 (任意・280 まで)。
    PollDescription,
}

/// 何で数えるか。
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Unit {
    /// UTF-16 の単位 (サーバの `.length`)。
    Utf16,
    /// Unicode のコードポイント (サーバの `[...s].length`)。
    CodePoint,
}

struct Rule {
    max: u32,
    unit: Unit,
    /// サーバが前後の空白を除いて数え、空を弾く欄か。
    trimmed_and_required: bool,
}

fn rule(field: InputField) -> Rule {
    let (max, unit, trimmed_and_required) = match field {
        InputField::TagName => (30, Unit::Utf16, true),
        InputField::TagDescription => (300, Unit::Utf16, false),
        InputField::DisplayName => (40, Unit::CodePoint, true),
        InputField::PollTitle => (80, Unit::Utf16, true),
        InputField::PollDescription => (280, Unit::Utf16, false),
    };
    Rule { max, unit, trimmed_and_required }
}

fn units(c: char, unit: Unit) -> u32 {
    match unit {
        Unit::Utf16 => c.len_utf16() as u32,
        Unit::CodePoint => 1,
    }
}

fn measure(text: &str, unit: Unit) -> u32 {
    text.chars().map(|c| units(c, unit)).sum()
}

/// サーバ (Worker) の `String.prototype.trim()` と同じ集合で前後を落とす。
///
/// Rust の `str::trim` (Unicode の White_Space) とは 2 文字違う: JS は U+FEFF (BOM) を
/// 落とし、U+0085 (NEL) を落とさない。`str::trim` のままだと BOM だけの名前が
/// 画面では送れて、サーバで「空」として弾かれる。
fn js_trim(text: &str) -> &str {
    text.trim_matches(|c: char| c == '\u{feff}' || (c.is_whitespace() && c != '\u{85}'))
}

/// その欄の上限。
pub fn input_max(field: InputField) -> u32 {
    rule(field).max
}

/// 画面の「N / 上限」に出す N。サーバが数えるのと同じもの (空白を除く欄は除いてから)。
pub fn input_length(field: InputField, text: &str) -> u32 {
    let r = rule(field);
    let counted = if r.trimmed_and_required { js_trim(text) } else { text };
    measure(counted, r.unit)
}

/// 入力を上限で切る (入力のたびに通す)。文字の途中では切らない — サロゲートペアの片割れを
/// 残すと送れない文字列になる。上限に収まっていればそのまま返す。
pub fn clamp_input(field: InputField, text: &str) -> String {
    let r = rule(field);
    let mut used = 0u32;
    let mut end = 0usize;
    for (at, c) in text.char_indices() {
        let next = used + units(c, r.unit);
        if next > r.max {
            break;
        }
        used = next;
        end = at + c.len_utf8();
    }
    text[..end].to_string()
}

/// サーバが受け付けるか (送信ボタンを押せるか)。
pub fn input_is_acceptable(field: InputField, text: &str) -> bool {
    let r = rule(field);
    let length = input_length(field, text);
    let non_empty = !r.trimmed_and_required || !js_trim(text).is_empty();
    non_empty && length <= r.max
}

// ---------------------------------------------------------------------------
// 票
// ---------------------------------------------------------------------------

/// 1 人が 1 つの対象 (お題 1 件・公演 1 件のセトリ予想) に入れられる票数。
/// サーバ (`rate_limit.ts` の VOTE_LIMIT) と同じ値。
pub const VOTE_LIMIT_PER_TARGET: u32 = 3;

/// 残りの票数。上限を入れる前に 3 票を超えて入れていた人は 0 に丸める。
pub fn votes_remaining(my_vote_count: u32) -> u32 {
    VOTE_LIMIT_PER_TARGET.saturating_sub(my_vote_count)
}

/// 選び直した結果から、投票・取り消しを決めたもの。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct VoteSelectionPlan {
    /// 新しく入れる対象 (選択肢の並び順で、残りの票数ぶんだけ)。
    pub to_vote: Vec<String>,
    /// 取り消す対象 (入れていたのに選択から外したもの)。
    pub to_unvote: Vec<String>,
    /// 残りの票数を超えて入れられなかった数。0 でなければ画面で知らせる。
    pub overflow: u32,
}

/// 選択肢で選ばれた対象 (`selected_in_order`、選択肢の並び順) と、入れ済みの対象から、
/// 何を入れて何を取り消すかを決める。
///
/// - 入れ済みの対象は票を使わない (もう一度入れない)。
/// - 新しい対象は並び順の先頭から、残りの票数ぶんだけ。溢れた数は `overflow`。
///   残りの票数は**取り消しの前**の数で見る (取り消しと同時に入れ替える操作は、
///   取り消しが済んでからもう一度選んでもらう — 両 OS の今の振る舞い)。
/// - `unvote_deselected` が真なら、入れ済みなのに選ばれていない対象を取り消す
///   (選択状態を見せる選択肢。曲の選択肢のように「足すだけ」の画面は偽)。
pub fn plan_vote_selection(
    already_voted: &[String],
    selected_in_order: &[String],
    my_vote_count: u32,
    unvote_deselected: bool,
) -> VoteSelectionPlan {
    let fresh: Vec<&String> = {
        let mut seen = std::collections::HashSet::new();
        selected_in_order
            .iter()
            .filter(|id| !already_voted.contains(id) && seen.insert(id.as_str()))
            .collect()
    };
    let remaining = votes_remaining(my_vote_count) as usize;
    let to_vote: Vec<String> = fresh.iter().take(remaining).map(|id| id.to_string()).collect();
    let to_unvote = if unvote_deselected {
        already_voted.iter().filter(|id| !selected_in_order.contains(id)).cloned().collect()
    } else {
        Vec::new()
    };
    VoteSelectionPlan { overflow: (fresh.len() - to_vote.len()) as u32, to_vote, to_unvote }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// JS の `trim()` が落とす文字 (node で全 BMP を舐めて得た一覧) とちょうど同じ。
    #[test]
    fn js_trim_matches_the_worker_trim_set() {
        const JS_TRIMMED: &[u32] = &[
            0x9, 0xa, 0xb, 0xc, 0xd, 0x20, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004,
            0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000,
            0xfeff,
        ];
        let trimmed: Vec<u32> = (0u32..0x10000)
            .filter_map(char::from_u32)
            .filter(|&c| js_trim(&format!("a{c}")) == "a")
            .map(u32::from)
            .collect();
        assert_eq!(trimmed, JS_TRIMMED);
        // BOM だけの名前はサーバで空として弾かれるので、画面でも送れない。
        assert!(!input_is_acceptable(InputField::DisplayName, "\u{feff}"));
        // NEL はサーバが落とさないので 1 文字として数える。
        assert_eq!(input_length(InputField::TagName, "\u{85}"), 1);
    }

    fn ids(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    #[test]
    fn limits_are_the_server_ones() {
        assert_eq!(input_max(InputField::TagName), 30);
        assert_eq!(input_max(InputField::TagDescription), 300);
        assert_eq!(input_max(InputField::DisplayName), 40);
        assert_eq!(input_max(InputField::PollTitle), 80);
        assert_eq!(input_max(InputField::PollDescription), 280);
        assert_eq!(VOTE_LIMIT_PER_TARGET, 3);
    }

    /// 表示名はコードポイントで数える (Q-08o)。絵文字 1 つは 1。
    #[test]
    fn display_name_counts_code_points() {
        let forty_emoji = "🎤".repeat(40);
        assert_eq!(input_length(InputField::DisplayName, &forty_emoji), 40);
        assert!(input_is_acceptable(InputField::DisplayName, &forty_emoji));
        let forty_one = "🎤".repeat(41);
        assert_eq!(clamp_input(InputField::DisplayName, &forty_one), forty_emoji);
        assert!(!input_is_acceptable(InputField::DisplayName, "   "));
        assert_eq!(input_length(InputField::DisplayName, "  あい  "), 2, "前後の空白は数えない");
    }

    /// タグ名・お題はサーバの `.length` (UTF-16) で数える。BMP 外の文字は 2。
    #[test]
    fn tag_and_poll_fields_count_utf16_units() {
        assert_eq!(input_length(InputField::TagName, "🎤"), 2);
        let thirty = "あ".repeat(30);
        assert!(input_is_acceptable(InputField::TagName, &thirty));
        assert!(!input_is_acceptable(InputField::TagName, &format!("{thirty}い")));
        assert!(!input_is_acceptable(InputField::TagName, " "));
        assert!(input_is_acceptable(InputField::TagDescription, ""), "説明は任意");
        assert!(!input_is_acceptable(InputField::PollTitle, "\u{3000}"), "全角空白だけも空");
    }

    /// 切り詰めは文字の途中で切らない (サロゲートペアを割らない)。
    #[test]
    fn clamping_never_splits_a_character() {
        let text = format!("{}🎤", "あ".repeat(29)); // 29 + 2 = 31 単位
        assert_eq!(clamp_input(InputField::TagName, &text), "あ".repeat(29));
        let fits = "あ".repeat(30);
        assert_eq!(clamp_input(InputField::TagName, &fits), fits);
        assert_eq!(clamp_input(InputField::PollDescription, ""), "");
        let long = "x".repeat(400);
        assert_eq!(clamp_input(InputField::TagDescription, &long).len(), 300);
    }

    #[test]
    fn remaining_votes_never_go_negative() {
        assert_eq!(votes_remaining(0), 3);
        assert_eq!(votes_remaining(2), 1);
        assert_eq!(votes_remaining(3), 0);
        assert_eq!(votes_remaining(5), 0, "上限導入前の 3 票超え");
    }

    /// 足すだけの選択肢 (曲): 入れ済みは票を使わず、残りの票数ぶんだけ並び順に入れる。
    #[test]
    fn add_only_selection_spends_only_the_remaining_votes() {
        let plan = plan_vote_selection(&ids(&["a"]), &ids(&["a", "b", "c", "d"]), 1, false);
        assert_eq!(plan.to_vote, ids(&["b", "c"]));
        assert!(plan.to_unvote.is_empty());
        assert_eq!(plan.overflow, 1);
    }

    /// 選択状態を見せる選択肢 (アイドル・ユニット): 外したものは取り消す。
    #[test]
    fn toggle_selection_unvotes_what_was_deselected() {
        let plan = plan_vote_selection(&ids(&["a", "b"]), &ids(&["b", "x"]), 2, true);
        assert_eq!(plan.to_unvote, ids(&["a"]));
        assert_eq!(plan.to_vote, ids(&["x"]));
        assert_eq!(plan.overflow, 0);
        // 3 票使い切り: 取り消しの前の残りで見るので、同時の入れ替えは入らない。
        let full = plan_vote_selection(&ids(&["a", "b", "c"]), &ids(&["b", "c", "x"]), 3, true);
        assert_eq!(full.to_unvote, ids(&["a"]));
        assert!(full.to_vote.is_empty());
        assert_eq!(full.overflow, 1);
    }

    #[test]
    fn duplicate_selection_counts_once() {
        let plan = plan_vote_selection(&[], &ids(&["x", "x", "y"]), 0, false);
        assert_eq!(plan.to_vote, ids(&["x", "y"]));
        assert_eq!(plan.overflow, 0);
    }
}
