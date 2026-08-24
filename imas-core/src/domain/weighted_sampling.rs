//! 重み付きのランダム抽出 (非復元)。
//!
//! 「タグが似ている曲」のおすすめで使う。サーバは候補を近い順に返すだけで、
//! そこから実際に何を見せるかは毎回ここで引き直す。上位固定にしないのは、
//! - 同じ曲を開くたびに同じ並びだと発見がない
//! - 少しだけ被っている曲もたまには顔を出してほしい
//! という理由。重みが大きいほど選ばれやすいので、近い曲が中心に出つつ
//! 遠い曲もときどき混ざる。
//!
//! FFI 境界では要素そのものは渡さず「重みの射影 → index 列」の形にする
//! (呼び出し側が自国の配列を index で引く)。乱数はシード注入の SplitMix64 で、
//! シードの調達 (実行時はシステム乱数) は各プラットフォームの薄いラッパが担う。

use crate::domain::prng::SplitMix64;

/// 重みに比例した確率で `count` 件ぶんの index を非復元抽出する。
///
/// Efraimidis–Spirakis 法: 各要素に `U^(1/w)` の鍵を振り、大きい順に取る。
/// 1 パスで「重み付き非復元抽出」になり、結果の並びもそのまま重み付きの
/// ランダム順になる (先頭ほど重い要素が来やすい)。
///
/// - 重みが 0 以下 (NaN 含む) の要素は、候補が足りないときの穴埋めとしてのみ使う。
///   穴埋め同士は鍵が同値 (0) なので、安定ソートにより入力順 (サーバの近い順) を保つ。
/// - `count` が候補数以上なら全件を (ランダム順で) 返す。
pub fn pick_indices(weights: &[f64], count: u32, rng: &mut SplitMix64) -> Vec<u32> {
    if count == 0 {
        return Vec::new();
    }
    let mut keyed: Vec<(u32, f64)> = weights
        .iter()
        .enumerate()
        .map(|(i, &w)| {
            let key = if w > 0.0 {
                // u は (0, 1]。0 を避けるのは 0^x で鍵が潰れる (常に最下位になる) のを防ぐため。
                // 53bit を仮数へ落とす定石で [0, 1) を作り、1 から引いて (0, 1] にする。
                let u = 1.0 - (rng.next_u64() >> 11) as f64 * (1.0 / (1u64 << 53) as f64);
                u.powf(1.0 / w)
            } else {
                0.0
            };
            (i as u32, key)
        })
        .collect();
    // 鍵は [0, 1] に収まり NaN にならないので total_cmp で全順序が付く。
    // sort_by は安定ソート: 同鍵 (重み 0 同士) は入力順を保つ。
    keyed.sort_by(|a, b| b.1.total_cmp(&a.1));
    keyed.truncate(count as usize);
    keyed.into_iter().map(|(i, _)| i).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 実データを模した候補: 近い曲 1、中くらい 2、少しだけ被っている曲 3。
    /// (iOS テストの pool と同じ重み。id は index で表す)
    const POOL: [f64; 6] = [0.33, 0.20, 0.15, 0.12, 0.08, 0.07];
    const CORE: u32 = 0; // 最も近い曲
    const MINOR: u32 = 3;
    const GRAZE2: u32 = 5; // 最も遠い曲

    fn draw(seed: u64, count: u32) -> Vec<u32> {
        pick_indices(&POOL, count, &mut SplitMix64(seed))
    }

    // --- 基本の性質 ---

    #[test]
    fn returns_requested_count() {
        assert_eq!(draw(1, 3).len(), 3);
    }

    #[test]
    fn never_repeats_the_same_item() {
        for seed in 0..50 {
            let picked = draw(seed, 3);
            let mut unique = picked.clone();
            unique.sort();
            unique.dedup();
            assert_eq!(unique.len(), picked.len(), "同じ曲が 2 回出た: {picked:?}");
        }
    }

    #[test]
    fn count_larger_than_pool_returns_everything() {
        let mut picked = draw(3, 99);
        picked.sort();
        assert_eq!(picked, vec![0, 1, 2, 3, 4, 5]);
    }

    #[test]
    fn zero_count_returns_empty() {
        assert!(draw(3, 0).is_empty());
    }

    #[test]
    fn empty_pool_returns_empty() {
        assert!(pick_indices(&[], 3, &mut SplitMix64(3)).is_empty());
    }

    #[test]
    fn same_seed_gives_same_result() {
        // シード注入の意味: 同じシードなら (プラットフォームによらず) 同じ抽選。
        assert_eq!(draw(42, 3), draw(42, 3));
    }

    // --- 「毎回同じにならない」 ---

    /// 同じ候補でも引くたびに結果が変わる (上位固定ではない)。
    #[test]
    fn result_varies_across_draws() {
        let results: std::collections::HashSet<Vec<u32>> = (0..40).map(|s| draw(s, 3)).collect();
        assert!(results.len() > 1, "毎回同じ組み合わせしか出ていない");
    }

    // --- 「近い曲が中心」かつ「遠い曲もたまに出る」 ---

    /// 重みの大きい曲ほど採用されやすい。
    #[test]
    fn higher_weight_appears_more_often() {
        let mut counts = [0u32; 6];
        for seed in 0..600 {
            for i in draw(seed, 3) {
                counts[i as usize] += 1;
            }
        }
        assert!(
            counts[CORE as usize] > counts[GRAZE2 as usize],
            "最も近い曲が最も遠い曲より出にくい: {counts:?}"
        );
        assert!(counts[CORE as usize] > counts[MINOR as usize], "{counts:?}");
    }

    /// 少しだけ被っている曲も出る (完全に締め出されない)。
    /// ここが 0 になると「たまに混ざってほしい」という要件が壊れる。
    #[test]
    fn low_weight_items_still_appear() {
        let mut appeared = std::collections::HashSet::new();
        for seed in 0..600 {
            appeared.extend(draw(seed, 3));
        }
        assert!(appeared.contains(&GRAZE2), "最も弱い候補が一度も出ていない");
        assert_eq!(appeared.len(), POOL.len(), "出番のない候補がある: {appeared:?}");
    }

    // --- 重み 0 / 負の扱い ---

    /// 重み 0 は、正の重みの候補が足りているうちは選ばれない。
    #[test]
    fn zero_weight_is_not_picked_while_positives_remain() {
        let items = [1.0, 1.0, 0.0];
        for seed in 0..40 {
            let picked = pick_indices(&items, 2, &mut SplitMix64(seed));
            assert!(!picked.contains(&2), "重み 0 が選ばれた: {picked:?}");
        }
    }

    /// 候補が足りなければ重み 0 でも穴埋めに使う (枠を空にしない)。
    #[test]
    fn zero_weight_fills_when_nothing_else_is_left() {
        let items = [1.0, 0.0];
        let mut picked = pick_indices(&items, 2, &mut SplitMix64(5));
        picked.sort();
        assert_eq!(picked, vec![0, 1]);
    }

    /// 負の重みでもクラッシュしない (サーバが想定外の値を返しても画面を壊さない)。
    #[test]
    fn negative_weight_is_treated_as_zero() {
        let items = [1.0, -3.0];
        assert_eq!(pick_indices(&items, 1, &mut SplitMix64(5)), vec![0]);
    }

    /// NaN も「0 以下」側に倒す (鍵の全順序を壊さない)。
    #[test]
    fn nan_weight_is_treated_as_zero() {
        let items = [1.0, f64::NAN];
        assert_eq!(pick_indices(&items, 1, &mut SplitMix64(5)), vec![0]);
    }

    /// 穴埋め同士 (鍵が同値) は入力順 = サーバの近い順を保つ。
    #[test]
    fn zero_weight_ties_keep_input_order() {
        let items = [0.0, 0.0, 0.0];
        assert_eq!(pick_indices(&items, 3, &mut SplitMix64(9)), vec![0, 1, 2]);
    }
}
