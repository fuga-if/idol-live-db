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

/// ソートメーカーの順位列 (上位から、同順位は同じ値) → 段の添字列 (0 = S) のたたき台。
#[uniffi::export]
pub fn tier_list_assign_from_ranking(ranks: Vec<u32>) -> Vec<u32> {
    tier_list::assign_from_ranking(&ranks)
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
        let text = tier_list_share_text(
            "t".into(),
            "".into(),
            vec![TierListShareTier { label: "S".into(), names: vec!["x".into()] }],
        );
        assert!(text.starts_with("t\nS: x\n"));
    }
}
