import Foundation

/// 重み付きのランダム抽出 (非復元)。
///
/// 「タグが似ている曲」のおすすめで使う。サーバは候補を近い順に返すだけで、
/// そこから実際に何を見せるかは毎回ここで引き直す。上位固定にしないのは、
/// - 同じ曲を開くたびに同じ並びだと発見がない
/// - 少しだけ被っている曲もたまには顔を出してほしい
/// という理由。重みが大きいほど選ばれやすいので、近い曲が中心に出つつ
/// 遠い曲もときどき混ざる。
enum WeightedSampling {
    /// 重みに比例した確率で `count` 件を非復元抽出する。
    ///
    /// Efraimidis–Spirakis 法: 各要素に `U^(1/w)` の鍵を振り、大きい順に取る。
    /// 1 パスで「重み付き非復元抽出」になり、結果の並びもそのまま重み付きの
    /// ランダム順になる (先頭ほど重い要素が来やすい)。
    ///
    /// - 重みが 0 以下の要素は、候補が足りないときの穴埋めとしてのみ使う。
    /// - `count` が候補数以上なら全件を (ランダム順で) 返す。
    /// - Parameter generator: テストから固定乱数を差せるようにするための乱数源。
    static func pick<T, G: RandomNumberGenerator>(
        _ items: [T],
        count: Int,
        weight: (T) -> Double,
        using generator: inout G
    ) -> [T] {
        guard count > 0 else { return [] }
        let keyed = items.map { item -> (item: T, key: Double) in
            let w = weight(item)
            guard w > 0 else { return (item, 0) }
            // u は (0, 1]。0 を避けるのは log(0) = -inf を踏まないため。
            let u = Double.random(in: 0.0..<1.0, using: &generator).nextUp
            return (item, pow(u, 1.0 / w))
        }
        return keyed.sorted { $0.key > $1.key }.prefix(count).map(\.item)
    }

    /// 実行時用 (システム乱数)。
    static func pick<T>(_ items: [T], count: Int, weight: (T) -> Double) -> [T] {
        var generator = SystemRandomNumberGenerator()
        return pick(items, count: count, weight: weight, using: &generator)
    }
}
