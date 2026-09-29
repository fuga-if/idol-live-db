import XCTest
@testable import ImasLiveDB

/// `WeightedSampling` の単体テスト。
///
/// 「おすすめが毎回同じにならない」「近い曲が中心に出る」「遠い曲もたまに出る」の
/// 3 つが同時に成り立つことを見る。1 つでも欠けると機能として意味が変わる。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class WeightedSamplingTests: XCTestCase {

    /// 固定乱数 (SplitMix64)。分布を決定論的に検証するため。
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private struct Candidate {
        let id: String
        let score: Double
    }

    /// 実データを模した候補: 近い曲 1、中くらい 2、少しだけ被っている曲 3。
    private let pool = [
        Candidate(id: "core", score: 0.33),
        Candidate(id: "pop", score: 0.20),
        Candidate(id: "mid", score: 0.15),
        Candidate(id: "minor", score: 0.12),
        Candidate(id: "graze1", score: 0.08),
        Candidate(id: "graze2", score: 0.07),
    ]

    private func draw(seed: UInt64, count: Int = 3) -> [String] {
        var gen = SeededGenerator(state: seed)
        return WeightedSampling.pick(pool, count: count, weight: \.score, using: &gen).map(\.id)
    }

    // MARK: - 基本の性質

    // MARK: - 「毎回同じにならない」

    // MARK: - 「近い曲が中心」かつ「遠い曲もたまに出る」

    // MARK: - 重み 0 / 負の扱い

    /// 重み 0 は、正の重みの候補が足りているうちは選ばれない。
    func testZeroWeightIsNotPickedWhilePositivesRemain() {
        let items = [Candidate(id: "a", score: 1), Candidate(id: "b", score: 1), Candidate(id: "zero", score: 0)]
        for seed in 0..<40 {
            var gen = SeededGenerator(state: UInt64(seed))
            let picked = WeightedSampling.pick(items, count: 2, weight: \.score, using: &gen).map(\.id)
            XCTAssertFalse(picked.contains("zero"), "重み 0 が選ばれた: \(picked)")
        }
    }
}
