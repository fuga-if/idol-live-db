//! みんなの投票の結果画像の FFI 面。ロジックは domain::poll_result_card。

use crate::domain::poll_result_card::{self, PollResultCard, PollResultCardInput};

/// 結果画像に載せる中身 (見出し・順位・表彰台と下の行)。画像を作る時点で 1 回呼ぶ。
#[uniffi::export]
pub fn poll_result_card(input: PollResultCardInput) -> PollResultCard {
    poll_result_card::poll_result_card(&input)
}

/// 票の多い順の票数から順位を付ける (同票は同順位: 1, 2, 2, 4)。
#[uniffi::export]
pub fn poll_competition_ranks(votes: Vec<u32>) -> Vec<u32> {
    poll_result_card::competition_ranks(&votes)
}
