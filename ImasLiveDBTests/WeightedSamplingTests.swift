import XCTest
@testable import ImasLiveDB

/// `WeightedSampling` の単体テスト。
///
/// 「おすすめが毎回同じにならない」「近い曲が中心に出る」「遠い曲もたまに出る」の
/// 3 つが同時に成り立つことを見る。1 つでも欠けると機能として意味が変わる。
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

    func testReturnsRequestedCount() {
        XCTAssertEqual(draw(seed: 1).count, 3)
    }

    func testNeverRepeatsTheSameItem() {
        for seed in 0..<50 {
            let picked = draw(seed: UInt64(seed))
            XCTAssertEqual(Set(picked).count, picked.count, "同じ曲が 2 回出た: \(picked)")
        }
    }

    func testCountLargerThanPoolReturnsEverything() {
        var gen = SeededGenerator(state: 3)
        let picked = WeightedSampling.pick(pool, count: 99, weight: \.score, using: &gen)
        XCTAssertEqual(Set(picked.map(\.id)), Set(pool.map(\.id)))
    }

    func testZeroCountReturnsEmpty() {
        var gen = SeededGenerator(state: 3)
        XCTAssertTrue(WeightedSampling.pick(pool, count: 0, weight: \.score, using: &gen).isEmpty)
    }

    func testEmptyPoolReturnsEmpty() {
        var gen = SeededGenerator(state: 3)
        XCTAssertTrue(WeightedSampling.pick([Candidate](), count: 3, weight: \.score, using: &gen).isEmpty)
    }

    // MARK: - 「毎回同じにならない」

    /// 同じ候補でも引くたびに結果が変わる (上位固定ではない)。
    func testResultVariesAcrossDraws() {
        let results = Set((0..<40).map { draw(seed: UInt64($0)).joined(separator: ",") })
        XCTAssertGreaterThan(results.count, 1, "毎回同じ組み合わせしか出ていない")
    }

    // MARK: - 「近い曲が中心」かつ「遠い曲もたまに出る」

    /// 重みの大きい曲ほど採用されやすい。
    func testHigherWeightAppearsMoreOften() {
        var counts: [String: Int] = [:]
        for seed in 0..<600 {
            for id in draw(seed: UInt64(seed)) { counts[id, default: 0] += 1 }
        }
        XCTAssertGreaterThan(counts["core", default: 0], counts["graze2", default: 0],
                             "最も近い曲が最も遠い曲より出にくい: \(counts)")
        XCTAssertGreaterThan(counts["core", default: 0], counts["minor", default: 0], "\(counts)")
    }

    /// 少しだけ被っている曲も出る (完全に締め出されない)。
    /// ここが 0 になると「たまに混ざってほしい」という要件が壊れる。
    func testLowWeightItemsStillAppear() {
        var appeared = Set<String>()
        for seed in 0..<600 { appeared.formUnion(draw(seed: UInt64(seed))) }
        XCTAssertTrue(appeared.contains("graze2"), "最も弱い候補が一度も出ていない")
        XCTAssertEqual(appeared.count, pool.count, "出番のない候補がある: \(appeared)")
    }

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

    /// 候補が足りなければ重み 0 でも穴埋めに使う (枠を空にしない)。
    func testZeroWeightFillsWhenNothingElseIsLeft() {
        let items = [Candidate(id: "a", score: 1), Candidate(id: "zero", score: 0)]
        var gen = SeededGenerator(state: 5)
        XCTAssertEqual(
            Set(WeightedSampling.pick(items, count: 2, weight: \.score, using: &gen).map(\.id)),
            ["a", "zero"])
    }

    /// 負の重みでもクラッシュしない (サーバが想定外の値を返しても画面を壊さない)。
    func testNegativeWeightIsTreatedAsZero() {
        let items = [Candidate(id: "a", score: 1), Candidate(id: "neg", score: -3)]
        var gen = SeededGenerator(state: 5)
        XCTAssertEqual(
            WeightedSampling.pick(items, count: 1, weight: \.score, using: &gen).map(\.id), ["a"])
    }
}
