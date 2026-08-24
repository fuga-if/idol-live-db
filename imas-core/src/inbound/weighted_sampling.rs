//! 重み付き抽選の FFI 面。ロジックは domain::weighted_sampling。

/// 重みに比例した確率で `count` 件ぶんの index を非復元抽出して返す。
///
/// 要素そのものは渡さず「重みの射影 → index 列」の 1 呼び出しで済ませ、
/// 呼び出し側が自国の配列を index で引く (FFI 境界の規約)。
/// `seed` の調達 (実行時はシステム乱数、テストでは固定値) はラッパが担う。
#[uniffi::export]
pub fn weighted_sample_indices(weights: Vec<f64>, count: u32, seed: u64) -> Vec<u32> {
    let mut rng = crate::domain::prng::SplitMix64(seed);
    crate::domain::weighted_sampling::pick_indices(&weights, count, &mut rng)
}
