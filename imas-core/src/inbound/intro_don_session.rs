//! イントロドンの 1 ゲームの規則の FFI 面。規則は [`crate::domain::intro_don_session`]。

use crate::domain::intro_don_session::{self as domain, IntroScore, IntroSessionKind};

/// 何問出すか。候補が 4 曲に満たなければ nil (始めない)。
#[uniffi::export]
pub fn intro_question_count(kind: IntroSessionKind, pool_size: u32, requested: u32) -> Option<u32> {
    domain::question_count(kind, pool_size, requested)
}

/// 1 問答えた (飛ばした) 後の点とコンボ。
#[uniffi::export]
pub fn intro_score_after_answer(current: IntroScore, correct: bool) -> IntroScore {
    domain::score_after_answer(current, correct)
}

/// 自己ベストの点を更新するか (前より多いときだけ)。
#[uniffi::export]
pub fn intro_is_new_best_score(score: u32, previous_best: u32) -> bool {
    domain::is_new_best_score(score, previous_best)
}

/// 全曲チャレンジの自己ベストのタイムを更新するか (記録が無いか、前より速い)。
#[uniffi::export]
pub fn intro_is_new_best_time(elapsed: f64, previous_best: f64) -> bool {
    domain::is_new_best_time(elapsed, previous_best)
}
