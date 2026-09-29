//! コミュニティ投稿の上限の FFI 面。規則は [`crate::domain::community_limits`]。

use crate::domain::community_limits::{self as domain, InputField, VoteSelectionPlan};

/// その入力欄の上限 (タグ名 30・タグの説明 300・表示名 40・お題 80・お題の説明 280)。
#[uniffi::export]
pub fn input_limit_max(field: InputField) -> u32 {
    domain::input_max(field)
}

/// 「N / 上限」の N。サーバと同じ数え方 (表示名はコードポイント、ほかは UTF-16)。
#[uniffi::export]
pub fn input_length(field: InputField, text: String) -> u32 {
    domain::input_length(field, &text)
}

/// 入力を上限で切る。入力が変わるたびに通す (文字の途中では切らない)。
#[uniffi::export]
pub fn input_clamp(field: InputField, text: String) -> String {
    domain::clamp_input(field, &text)
}

/// サーバが受け付けるか (送信ボタンを押せるか)。
#[uniffi::export]
pub fn input_is_acceptable(field: InputField, text: String) -> bool {
    domain::input_is_acceptable(field, &text)
}

/// 1 人が 1 つの対象に入れられる票数 (3)。
#[uniffi::export]
pub fn vote_limit_per_target() -> u32 {
    domain::VOTE_LIMIT_PER_TARGET
}

/// 残りの票数 (上限を超えて入れていた人は 0)。
#[uniffi::export]
pub fn votes_remaining(my_vote_count: u32) -> u32 {
    domain::votes_remaining(my_vote_count)
}

/// 選択肢で選んだ結果から、入れる対象・取り消す対象・溢れた数を決める。
/// `selected_in_order` は選択肢の並び順で渡す。
#[uniffi::export]
pub fn plan_vote_selection(
    already_voted: Vec<String>,
    selected_in_order: Vec<String>,
    my_vote_count: u32,
    unvote_deselected: bool,
) -> VoteSelectionPlan {
    domain::plan_vote_selection(&already_voted, &selected_in_order, my_vote_count, unvote_deselected)
}
