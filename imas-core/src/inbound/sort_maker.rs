//! ソートメーカーの FFI 面。ロジックは domain::sort_maker。
//!
//! 各 OS は「対象の id 列・シード・答えの列」を持って 1 操作 1 呼び出しする。
//! 答えるたびに `sort_maker_replay` を呼び直し、返ってきた対戦・順位表をそのまま描く。

use crate::domain::share_text;
use crate::domain::sort_maker::{self, SortMakerChoice, SortMakerConfig, SortMakerState};

/// 答えを頭から再生して、次の対戦・進み具合・順位表を返す。
/// `top_k` = 0 は全順位。「1 つ戻る」は `answers` の末尾を落として呼ぶだけ。
#[uniffi::export]
pub fn sort_maker_replay(
    item_count: u32,
    top_k: u32,
    seed: u64,
    answers: Vec<SortMakerChoice>,
) -> SortMakerState {
    sort_maker::replay(SortMakerConfig { item_count, top_k, seed }, &answers)
}

/// 始める前の対戦数の見積り (設定画面の「約 N 戦」)。
#[uniffi::export]
pub fn sort_maker_estimate_total(item_count: u32, top_k: u32) -> u32 {
    sort_maker::estimate_total(item_count, top_k)
}

/// 共有文の 1 行 (順位と表示名)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct SortMakerShareRow {
    pub rank: u32,
    pub name: String,
}

/// 結果のシェア文。`rows` は上位から (11 位以降は載らない)。
#[uniffi::export]
pub fn sort_maker_share_text(title: String, scope_label: String, rows: Vec<SortMakerShareRow>) -> String {
    let ranked: Vec<(u32, String)> = rows.into_iter().map(|r| (r.rank, r.name)).collect();
    share_text::sort_maker_share_text(&title, &scope_label, &ranked)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replay_delegates_and_undo_round_trips() {
        let first = sort_maker_replay(3, 0, 1, vec![]);
        assert!(first.pair.is_some());
        let one = sort_maker_replay(3, 0, 1, vec![SortMakerChoice::Tie]);
        assert_eq!(one.answered, 1);
        assert_eq!(sort_maker_replay(3, 0, 1, vec![]), first);
        assert_eq!(sort_maker_estimate_total(3, 0), first.estimated_remaining);
    }

    #[test]
    fn share_text_delegates() {
        let text = sort_maker_share_text(
            "好きなアイドルソート".into(),
            "".into(),
            vec![SortMakerShareRow { rank: 1, name: "天海春香".into() }],
        );
        assert!(text.starts_with("好きなアイドルソートの結果\n1位 天海春香\n"));
    }
}
