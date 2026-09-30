//! ティアー表: 曲・アイドルを S / A / B / C / D の段に振り分ける。
//!
//! 振り分けそのものは利用者が手で行う (好みの判断を機械に任せない)。コアが持つのは
//! - 段の並び (名前と数) … iOS / Android で段が食い違わないように 1 か所に置く
//! - ソートメーカーの順位表からの「たたき台」… 順位を段へ割り当てる規則
//! だけ。たたき台はあくまで初期値で、画面で自由に動かせる。
//!
//! ## 順位 → 段の割り当て
//!
//! 上から S 10% / A 20% / B 30% / C 25% / D 15% を目安に切る (上ほど狭い)。
//! - 同順位 (引き分け) は同じ段に入れる。境目にかかったら上の段へまとめる。
//! - S には必ず 1 件以上入れる。
//! - 件数が段数より少ないときは上から 1 件ずつ (空の段が下に残る)。

/// 段の名前 (上から)。
pub const TIER_LABELS: [&str; 5] = ["S", "A", "B", "C", "D"];

/// 段の色の種 (hex)。見慣れたティアー表の配色 (赤→橙→黄→緑→青)。
/// 画面ではこれをテーマエンジンに通して明暗に合わせる。
pub const TIER_COLOR_SEEDS: [&str; 5] = ["#FF5A5F", "#FF9F43", "#F6C744", "#2BC48A", "#4C8DFF"];

/// 各段の取り分の目安 (百分率、合計 100)。
const TIER_SHARES: [u32; 5] = [10, 20, 30, 25, 15];

/// 上位から並んだ順位列 (`ranks[i]` は i 番目の順位。同順位は同じ値) を段の添字列にする。
/// 戻り値は `ranks` と同じ長さで、0 = S。
pub fn assign_from_ranking(ranks: &[u32]) -> Vec<u32> {
    let n = ranks.len();
    if n == 0 {
        return Vec::new();
    }
    // 各段の下端 (累積件数)。最低でも「その段までで 段番号+1 件」を確保する。
    let mut bounds = Vec::with_capacity(TIER_SHARES.len());
    let mut acc = 0u32;
    for (t, share) in TIER_SHARES.iter().enumerate() {
        acc += share;
        let by_share = ((n as u64 * acc as u64 + 50) / 100) as usize;
        bounds.push(by_share.max(t + 1).min(n));
    }
    let mut out = Vec::with_capacity(n);
    let mut tier = 0usize;
    for i in 0..n {
        // 同順位の続きは前と同じ段 (境目を越えていても上の段にまとめる)。
        if i > 0 && ranks[i] == ranks[i - 1] {
            out.push(out[i - 1]);
            continue;
        }
        while tier + 1 < bounds.len() && i >= bounds[tier] {
            tier += 1;
        }
        out.push(tier as u32);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn distinct(n: u32) -> Vec<u32> {
        (1..=n).collect()
    }

    fn counts(tiers: &[u32]) -> Vec<usize> {
        (0..TIER_LABELS.len() as u32).map(|t| tiers.iter().filter(|&&x| x == t).count()).collect()
    }

    #[test]
    fn hundred_items_follow_the_shares() {
        assert_eq!(counts(&assign_from_ranking(&distinct(100))), vec![10, 20, 30, 25, 15]);
    }

    #[test]
    fn ten_items_keep_every_tier_and_top_is_narrow() {
        let c = counts(&assign_from_ranking(&distinct(10)));
        assert_eq!(c.iter().sum::<usize>(), 10);
        assert_eq!(c[0], 1);
        assert!(c.iter().all(|&x| x >= 1), "{c:?}");
    }

    #[test]
    fn fewer_items_than_tiers_go_one_per_tier_from_the_top() {
        assert_eq!(assign_from_ranking(&distinct(3)), vec![0, 1, 2]);
        assert_eq!(assign_from_ranking(&[1]), vec![0]);
        assert!(assign_from_ranking(&[]).is_empty());
    }

    #[test]
    fn ties_are_never_split_and_stay_in_the_upper_tier() {
        // 10 件: S の枠は 1 件だが 1 位が 3 件並んでいる → 3 件とも S。
        let ranks = vec![1, 1, 1, 4, 5, 6, 7, 8, 9, 10];
        let t = assign_from_ranking(&ranks);
        assert_eq!(&t[..3], &[0, 0, 0]);
        assert!(t[3] >= 1);
        // 単調 (下の順位が上の段に来ない)。
        assert!(t.windows(2).all(|w| w[0] <= w[1]));
    }

    #[test]
    fn all_tied_is_all_s() {
        assert_eq!(assign_from_ranking(&[1, 1, 1, 1]), vec![0, 0, 0, 0]);
    }
}
