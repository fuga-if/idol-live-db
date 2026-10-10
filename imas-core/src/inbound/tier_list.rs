//! ティアー表の FFI 面。ロジックは domain::tier_list。

use crate::domain::share_text;
use crate::domain::tier_list;

/// 段 1 つ (名前と色の種)。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TierListTier {
    pub label: String,
    pub color_seed: String,
}

/// 段の並び (上から S, A, B, C, D)。
#[uniffi::export]
pub fn tier_list_tiers() -> Vec<TierListTier> {
    tier_list::TIER_LABELS
        .iter()
        .zip(tier_list::TIER_COLOR_SEEDS)
        .map(|(l, c)| TierListTier { label: l.to_string(), color_seed: c.to_string() })
        .collect()
}

/// ティアー表の名前を整える (空なら None = 既定の名前)。上限は domain::tier_list::TITLE_MAX_CHARS。
#[uniffi::export]
pub fn tier_list_normalize_title(input: String) -> Option<String> {
    tier_list::normalize_name(&input, tier_list::TITLE_MAX_CHARS)
}

/// 段の名前を整える (空なら None = S〜D の既定名)。上限は TIER_LABEL_MAX_CHARS。
#[uniffi::export]
pub fn tier_list_normalize_tier_label(input: String) -> Option<String> {
    tier_list::normalize_name(&input, tier_list::TIER_LABEL_MAX_CHARS)
}

/// 名前の入力欄の上限 (入力中に数えて出す用)。
#[uniffi::export]
pub fn tier_list_title_max_chars() -> u32 {
    tier_list::TITLE_MAX_CHARS as u32
}

#[uniffi::export]
pub fn tier_list_tier_label_max_chars() -> u32 {
    tier_list::TIER_LABEL_MAX_CHARS as u32
}

/// 段の数の下限・上限。
#[uniffi::export]
pub fn tier_list_min_tiers() -> u32 {
    tier_list::MIN_TIERS as u32
}

#[uniffi::export]
pub fn tier_list_max_tiers() -> u32 {
    tier_list::MAX_TIERS as u32
}

/// `index` 番目 (0 始まり) に段を足すときの既定の段。色は今の段と被らない候補から選ぶ。
#[uniffi::export]
pub fn tier_list_new_tier(index: u32, existing_color_seeds: Vec<String>) -> TierListTier {
    TierListTier {
        label: tier_list::default_label(index as usize),
        color_seed: tier_list::next_color_for_new_tier(&existing_color_seeds),
    }
}

/// 段の色を次の候補へ (色の札をタップしたとき)。
#[uniffi::export]
pub fn tier_list_cycle_color(current: String) -> String {
    tier_list::cycle_color(&current)
}

/// ソートメーカーの順位列 (上位から、同順位は同じ値) → 段の添字列 (0 = S) のたたき台。
#[uniffi::export]
pub fn tier_list_assign_from_ranking(ranks: Vec<u32>) -> Vec<u32> {
    tier_list::assign_from_ranking(&ranks)
}

/// 段の中の並びを 1 件動かす (ドラッグで札の上に落とした / 段の余白に落とした)。
/// `order` は保存している表全体の並び (空 = 対象の並びのまま)。`before` が別の項目ならその左へ、
/// None なら末尾 (= 落とした段の右端) へ。戻り値をそのまま保存する。
#[uniffi::export]
pub fn tier_list_move_item(
    item_ids: Vec<String>,
    order: Vec<String>,
    item: String,
    before: Option<String>,
) -> Vec<String> {
    tier_list::move_item(&item_ids, &order, &item, before.as_deref())
}

/// 共有文の 1 段。
#[derive(uniffi::Record, Clone, Debug, PartialEq, Eq)]
pub struct TierListShareTier {
    pub label: String,
    pub names: Vec<String>,
}

/// ティアー表のシェア文。空の段は書かない。1 段 5 件まで、残りは「ほかN件」。
#[uniffi::export]
pub fn tier_list_share_text(title: String, scope_label: String, tiers: Vec<TierListShareTier>) -> String {
    let tiers: Vec<(String, Vec<String>)> = tiers.into_iter().map(|t| (t.label, t.names)).collect();
    share_text::tier_list_share_text(&title, &scope_label, &tiers)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn delegates() {
        let labels: Vec<String> = tier_list_tiers().into_iter().map(|t| t.label).collect();
        assert_eq!(labels, vec!["S", "A", "B", "C", "D"]);
        assert_eq!(tier_list_assign_from_ranking(vec![1, 2, 3]), vec![0, 1, 2]);
        let items: Vec<String> = ["a", "b", "c"].iter().map(|s| s.to_string()).collect();
        assert_eq!(tier_list_move_item(items.clone(), vec![], "c".into(), Some("a".into())), vec!["c", "a", "b"]);
        let text = tier_list_share_text(
            "t".into(),
            "".into(),
            vec![TierListShareTier { label: "S".into(), names: vec!["x".into()] }],
        );
        assert!(text.starts_with("t\nS: x\n"));
    }
}
