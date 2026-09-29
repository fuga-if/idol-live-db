//! メンバーカラー 4 択の FFI 面。ロジックは domain::color_quiz。
//!
//! | 画面の操作 | 呼ぶもの |
//! |---|---|
//! | 「はじめる」 | [`color_quiz_start_game`] (全問まとめて生成) |
//! | 出題 / ヒントを開く / 解答 | [`color_quiz_hint_state`] |
//! | 色をタップ | [`color_quiz_answer`] |
//! | 結果画面 | [`color_quiz_session_result`] |

use crate::domain::color_match::{ColorMatchDifficulty, ColorMatchIdol};
use crate::domain::color_quiz::{
    self as cq, ColorQuizHintKind, ColorQuizHintState, ColorQuizQuestion, COLOR_QUIZ_BASE_POINTS,
};
use crate::domain::prng::SplitMix64;
use crate::domain::quiz_generation::{
    quiz_session_result, QuizAnswerOutcome, QuizSessionResult, QuizTally,
};

/// 1 ゲームぶん (全 `question_count` 問) の出題をまとめて生成する。
/// `pool` は [`crate::inbound::color_match::color_match_effective_pool`] の結果。4 人未満なら空。
#[uniffi::export]
pub fn color_quiz_start_game(
    pool: Vec<ColorMatchIdol>,
    difficulty: ColorMatchDifficulty,
    question_count: u32,
    seed: u64,
) -> Vec<ColorQuizQuestion> {
    cq::make_questions(&pool, difficulty, question_count, &mut SplitMix64(seed))
}

/// いまの獲得点・色の系統・2 択で消す選択肢・まだ開けるヒント。
#[uniffi::export]
pub fn color_quiz_hint_state(
    question: ColorQuizQuestion,
    opened: Vec<ColorQuizHintKind>,
    answered: bool,
) -> ColorQuizHintState {
    cq::hint_state(&question, &opened, answered)
}

/// 色をタップしたときの正誤判定・加点・集計。
#[uniffi::export]
pub fn color_quiz_answer(
    question: ColorQuizQuestion,
    opened: Vec<ColorQuizHintKind>,
    picked_hex: String,
    before: QuizTally,
    question_count: u32,
) -> QuizAnswerOutcome {
    cq::answer(&question, &opened, &picked_hex, &before, question_count)
}

/// セッション終了時のリザルト。
#[uniffi::export]
pub fn color_quiz_session_result(tally: QuizTally, question_count: u32) -> QuizSessionResult {
    quiz_session_result(&tally, COLOR_QUIZ_BASE_POINTS, question_count)
}
