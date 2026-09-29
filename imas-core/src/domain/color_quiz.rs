//! メンバーカラーの 4 択 (名前を見てイメージカラーを 4 色から選ぶ)。
//!
//! 並べるモード ([`crate::domain::color_match`]) と同じ母集団・難易度の規則を使う。
//! 1 問は「答えのアイドル 1 人 + 難易度の規則で選んだ 3 人の色」:
//!
//! - むずい: 答えに色が近い 3 色
//! - やさしい: 互いに離れた 3 色
//! - ふつう: ランダムな 3 色
//!
//! 採点はほかのクイズと同じ加点式 (ノーヒント 10pt、ヒントごとにコストを引き最低 1pt)。

use std::collections::HashSet;

use crate::domain::color_match::{
    companions, hex_to_rgb, normalized_hex, same_color, ColorMatchDifficulty, ColorMatchIdol,
    MIN_POOL_SIZE,
};
use crate::domain::prng::SplitMix64;
use crate::domain::quiz_generation::{quiz_answer, QuizAnswerOutcome, QuizTally};

/// ノーヒント正解の素点。
pub const COLOR_QUIZ_BASE_POINTS: u32 = 10;

/// 1 問の選択肢の数。
pub const COLOR_QUIZ_CHOICES: usize = 4;

/// 1 問ぶんの出題。
#[derive(uniffi::Record, Clone, Debug, PartialEq)]
pub struct ColorQuizQuestion {
    /// 名前を出すアイドル (正解の色も持つ)。
    pub answer: ColorMatchIdol,
    /// 選択肢の色 (メンバーカラーの原文、表示順)。正解の色を 1 つ含む。
    pub choices: Vec<String>,
}

/// ヒントの種類。並び順がそのままタイルの並び。
#[derive(uniffi::Enum, Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum ColorQuizHintKind {
    /// 答えの色の系統 (「青系」など)。
    Family,
    /// 選択肢を 2 つに減らす。
    FiftyFifty,
}

impl ColorQuizHintKind {
    pub const ALL: [ColorQuizHintKind; 2] = [Self::Family, Self::FiftyFifty];

    pub fn cost(self) -> u32 {
        match self {
            Self::Family => 3,
            Self::FiftyFifty => 5,
        }
    }
}

/// まだ開いていないヒント 1 件。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ColorQuizHintOption {
    pub kind: ColorQuizHintKind,
    pub cost: u32,
    /// 開いた後に正解した場合の獲得点。
    pub next_value: u32,
}

/// 出題カードの開示状態。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct ColorQuizHintState {
    pub current_value: u32,
    pub base_value: u32,
    /// 色の系統 (系統ヒントを開いたか解答後だけ)。
    pub family_label: Option<String>,
    /// 2 択ヒントで消した選択肢の位置 (`choices` の index)。
    pub eliminated: Vec<u32>,
    /// まだ開いていないヒント (解答後は空)。
    pub hints: Vec<ColorQuizHintOption>,
}

// ---------------------------------------------------------------------------
// 出題
// ---------------------------------------------------------------------------

/// 1 ゲームぶんの出題をまとめて作る。母集団が 4 人未満なら空。
///
/// 答えになる人は母集団をシャッフルした順に引き、一巡するまで同じ人を出さない。
pub fn make_questions(
    pool: &[ColorMatchIdol],
    difficulty: ColorMatchDifficulty,
    question_count: u32,
    rng: &mut SplitMix64,
) -> Vec<ColorQuizQuestion> {
    if pool.len() < COLOR_QUIZ_CHOICES.max(MIN_POOL_SIZE) {
        return Vec::new();
    }
    let mut order: Vec<usize> = (0..pool.len()).collect();
    rng.shuffle(&mut order);
    (0..question_count as usize)
        .map(|i| {
            let answer = pool[order[i % order.len()]].clone();
            let rest: Vec<ColorMatchIdol> =
                pool.iter().filter(|idol| idol.id != answer.id).cloned().collect();
            let mut choices: Vec<String> = std::iter::once(answer.clone())
                .chain(companions(&answer, rest, COLOR_QUIZ_CHOICES - 1, difficulty, rng))
                .map(|idol| idol.color.unwrap_or_default())
                .collect();
            rng.shuffle(&mut choices);
            ColorQuizQuestion { answer, choices }
        })
        .collect()
}

// ---------------------------------------------------------------------------
// ヒントと採点
// ---------------------------------------------------------------------------

fn opened_set(opened: &[ColorQuizHintKind]) -> HashSet<ColorQuizHintKind> {
    opened.iter().copied().collect()
}

/// いま正解した場合の獲得点 (素点 − 開いたヒントのコスト、最低 1pt)。
pub fn current_value(opened: &[ColorQuizHintKind]) -> u32 {
    let cost: u32 = opened_set(opened).into_iter().map(ColorQuizHintKind::cost).sum();
    COLOR_QUIZ_BASE_POINTS.saturating_sub(cost).max(1)
}

/// 色の系統の呼び名 (色相と彩度・明度で大まかに分ける)。
pub fn color_family(hex: &str) -> String {
    let c = hex_to_rgb(hex);
    let (r, g, b) = (c.r / 255.0, c.g / 255.0, c.b / 255.0);
    let max = r.max(g).max(b);
    let min = r.min(g).min(b);
    let l = (max + min) / 2.0;
    let d = max - min;
    let s = if d == 0.0 { 0.0 } else { d / (1.0 - (2.0 * l - 1.0).abs()) };
    if s < 0.15 || d < 0.08 {
        return if l > 0.8 { "白系" } else if l < 0.2 { "黒系" } else { "グレー系" }.to_string();
    }
    let h = if max == r {
        60.0 * (((g - b) / d).rem_euclid(6.0))
    } else if max == g {
        60.0 * ((b - r) / d + 2.0)
    } else {
        60.0 * ((r - g) / d + 4.0)
    };
    // 赤は明るいとピンクに見える (#EA5B76 など)。
    let red = if l > 0.6 { "ピンク系" } else { "赤系" };
    let name = match h {
        h if h < 15.0 => red,
        h if h < 40.0 => "オレンジ系",
        h if h < 70.0 => "黄色系",
        h if h < 165.0 => "緑系",
        h if h < 200.0 => "水色系",
        h if h < 255.0 => "青系",
        h if h < 290.0 => "紫系",
        h if h < 345.0 => "ピンク系",
        _ => red,
    };
    name.to_string()
}

/// 2 択ヒントで消す選択肢。答えから色が遠い誤答 2 つ (残るのは答えといちばん紛らわしい色)。
fn eliminated_choices(question: &ColorQuizQuestion) -> Vec<u32> {
    let answer = question.answer.color.as_deref();
    let mut wrong: Vec<(f64, u32)> = question
        .choices
        .iter()
        .enumerate()
        .filter(|(_, hex)| !same_color(hex, answer))
        .map(|(i, hex)| (crate::domain::color_match::color_distance(answer, Some(hex)), i as u32))
        .collect();
    // 遠い順 (同じ距離なら前の選択肢から)。
    wrong.sort_by(|a, b| b.0.total_cmp(&a.0).then(a.1.cmp(&b.1)));
    let keep = wrong.len().saturating_sub(COLOR_QUIZ_CHOICES / 2 - 1);
    let mut out: Vec<u32> = wrong.into_iter().take(keep).map(|(_, i)| i).collect();
    out.sort_unstable();
    out
}

pub fn hint_state(
    question: &ColorQuizQuestion,
    opened: &[ColorQuizHintKind],
    answered: bool,
) -> ColorQuizHintState {
    let set = opened_set(opened);
    let value = current_value(opened);
    ColorQuizHintState {
        current_value: value,
        base_value: COLOR_QUIZ_BASE_POINTS,
        family_label: (answered || set.contains(&ColorQuizHintKind::Family))
            .then(|| color_family(question.answer.color.as_deref().unwrap_or(""))),
        eliminated: if !answered && set.contains(&ColorQuizHintKind::FiftyFifty) {
            eliminated_choices(question)
        } else {
            Vec::new()
        },
        hints: if answered {
            Vec::new()
        } else {
            ColorQuizHintKind::ALL
                .into_iter()
                .filter(|k| !set.contains(k))
                .map(|kind| ColorQuizHintOption {
                    kind,
                    cost: kind.cost(),
                    next_value: value.saturating_sub(kind.cost()).max(1),
                })
                .collect()
        },
    }
}

/// 解答。色は表記ゆれを無視して比べる。
pub fn answer(
    question: &ColorQuizQuestion,
    opened: &[ColorQuizHintKind],
    picked_hex: &str,
    before: &QuizTally,
    session_length: u32,
) -> QuizAnswerOutcome {
    let key = |hex: &str| normalized_hex(hex).unwrap_or_default();
    let answer_hex = question.answer.color.as_deref().map(key).unwrap_or_else(|| "-".into());
    quiz_answer(
        current_value(opened),
        opened_set(opened).len() as u32,
        &key(picked_hex),
        &answer_hex,
        before,
        session_length,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    fn idol(id: &str, color: &str) -> ColorMatchIdol {
        ColorMatchIdol { id: id.into(), color: Some(color.into()) }
    }

    fn pool() -> Vec<ColorMatchIdol> {
        vec![
            idol("a", "#E22B30"),
            idol("b", "#E83040"),
            idol("c", "#2743D2"),
            idol("d", "#FED552"),
            idol("e", "#01ADB9"),
            idol("f", "#FFFFFF"),
        ]
    }

    #[test]
    fn questions_hold_the_answer_color_among_four_distinct_choices() {
        let qs = make_questions(&pool(), ColorMatchDifficulty::Normal, 10, &mut SplitMix64(7));
        assert_eq!(qs.len(), 10);
        for q in &qs {
            assert_eq!(q.choices.len(), 4);
            assert!(q.choices.contains(q.answer.color.as_ref().unwrap()));
            let unique: HashSet<&String> = q.choices.iter().collect();
            assert_eq!(unique.len(), 4);
        }
        // 一巡するまで同じ人を答えにしない。
        let first: HashSet<&str> = qs[..6].iter().map(|q| q.answer.id.as_str()).collect();
        assert_eq!(first.len(), 6);
    }

    #[test]
    fn too_small_pool_makes_no_questions() {
        let qs = make_questions(&pool()[..3], ColorMatchDifficulty::Easy, 5, &mut SplitMix64(1));
        assert!(qs.is_empty());
    }

    #[test]
    fn hard_picks_the_nearest_colors() {
        let q = make_questions(&pool(), ColorMatchDifficulty::Hard, 6, &mut SplitMix64(3))
            .into_iter()
            .find(|q| q.answer.id == "a")
            .unwrap();
        assert!(q.choices.contains(&"#E83040".to_string()), "近い赤が並ぶ");
    }

    #[test]
    fn hints_subtract_cost_and_fifty_fifty_keeps_the_answer() {
        let q = ColorQuizQuestion {
            answer: idol("a", "#E22B30"),
            choices: vec!["#2743D2".into(), "#E22B30".into(), "#E83040".into(), "#FED552".into()],
        };
        let s0 = hint_state(&q, &[], false);
        assert_eq!(s0.current_value, 10);
        assert_eq!(s0.family_label, None);
        assert_eq!(s0.hints.len(), 2);

        let s1 = hint_state(&q, &[ColorQuizHintKind::FiftyFifty, ColorQuizHintKind::Family], false);
        assert_eq!(s1.current_value, 2);
        assert_eq!(s1.family_label.as_deref(), Some("赤系"));
        assert_eq!(s1.eliminated, vec![0, 3], "紛らわしい赤だけ残す");
        assert!(s1.hints.is_empty());

        let answered = hint_state(&q, &[], true);
        assert!(answered.family_label.is_some() && answered.eliminated.is_empty());
    }

    #[test]
    fn answer_ignores_hex_notation() {
        let q = ColorQuizQuestion { answer: idol("a", "#E22B30"), choices: vec![] };
        let hit = answer(&q, &[ColorQuizHintKind::Family], "e22b30", &QuizTally::default(), 10);
        assert!(hit.is_correct);
        assert_eq!(hit.earned_points, 7);
        let miss = answer(&q, &[], "#2743D2", &QuizTally::default(), 10);
        assert!(!miss.is_correct);
    }

    #[test]
    fn families_read_naturally() {
        assert_eq!(color_family("#2743D2"), "青系");
        assert_eq!(color_family("#FED552"), "黄色系");
        assert_eq!(color_family("#01ADB9"), "水色系");
        assert_eq!(color_family("#FFFFFF"), "白系");
        assert_eq!(color_family("#EA5B76"), "ピンク系");
        assert_eq!(color_family("#0F0F0F"), "黒系");
        assert_eq!(color_family("#E22B30"), "赤系");
    }
}
