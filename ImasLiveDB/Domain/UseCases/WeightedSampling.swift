import Foundation

/// 重み付きのランダム抽出 (非復元)。
///
/// 抽選本体は imas-core (Rust) の `domain/weighted_sampling.rs` にあり、Android の
/// `WeightedSampling` と同じ実装 (Efraimidis–Spirakis 法) を共有する。
/// なぜ上位固定にしないか・重み 0 の扱いなどの設計意図もそちらに記載。
///
/// ここが担うのは「シードの調達」と「index 列 → Swift 配列の解決」だけ。
/// - 実行時はシステム乱数からシードを引く (毎回顔ぶれが変わる)。
/// - テストは固定シードの generator を差して決定論にする。
/// 重みの射影と index 列だけを FFI に通すので、候補件数によらず 1 呼び出しで済む。
enum WeightedSampling {
    /// 重みに比例した確率で `count` 件を非復元抽出する。
    ///
    /// - Parameter generator: シード調達源。テストから固定乱数を差せるようにするため。
    static func pick<T, G: RandomNumberGenerator>(
        _ items: [T],
        count: Int,
        weight: (T) -> Double,
        using generator: inout G
    ) -> [T] {
        let indices = weightedSampleIndices(
            weights: items.map(weight),
            // 負の count は 0 (空) に丸める。境界の型合わせのみで判定はしない。
            count: UInt32(clamping: count),
            seed: generator.next()
        )
        return indices.map { items[Int($0)] }
    }

    /// 実行時用 (システム乱数でシードを調達)。
    static func pick<T>(_ items: [T], count: Int, weight: (T) -> Double) -> [T] {
        var generator = SystemRandomNumberGenerator()
        return pick(items, count: count, weight: weight, using: &generator)
    }
}
