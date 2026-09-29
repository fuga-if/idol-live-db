import XCTest
@testable import ImasLiveDB

/// `IntroQuizChoices` (imas-core 委譲) の単体テスト。
///
/// 規則そのもの (タイトルでのユニーク化・不正解候補が pool 順を保つこと等) は
/// imas-core の `domain/intro_quiz_choices.rs` の Rust テストが担う。ここでは
/// Swift ラッパ (射影とシード調達) を通しても核心が成り立つことを見る。核心は
/// 「同名異曲が pool にあっても、正解と同じタイトルが不正解として並ばない」こと
/// (並ぶと正しい答えを選んでも不正解になる)。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class IntroQuizChoicesTests: XCTestCase {

    /// 固定乱数 (SplitMix64)。シード調達を決定論にするため。
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

    private func makeSong(_ id: String, _ title: String) -> Song {
        Song(
            id: id, title: title, titleKana: nil, brandId: nil, songType: "original",
            releaseDate: nil, durationSec: nil, composer: nil, lyricist: nil, arranger: nil,
            cdSeries: nil, cdTitle: nil, artworkUrl: nil, previewUrl: nil, appleMusicId: nil,
            appleMusicAlbumId: nil, isrc: nil, lyricsUrl: nil, parentSongId: nil,
            singerLabel: nil, unitName: nil, unitId: nil)
    }

    /// 1 問だけのバッチで選択肢を引く (規則検証の便宜用)。
    private func makeChoices(for answer: Song, pool: [Song], seed: UInt64 = 42) -> [String] {
        var gen = SeededGenerator(state: seed)
        return IntroQuizChoices.makeAll(for: [answer], pool: pool, using: &gen).first ?? []
    }

    // MARK: - タイトルユニーク化の規則

    // MARK: - 出題される 4 択

    // MARK: - バッチ (1 ゲーム = 1 呼び出し)

    /// 出題と同順・同数で返り、各問に自分の正解が入る。
    func testMakeAllReturnsChoicesPerAnswerInOrder() {
        var gen = SeededGenerator(state: 42)
        let pool = (1...10).map { makeSong("s\($0)", "曲\($0)") }
        let answers = [pool[0], pool[4], pool[9]]

        let all = IntroQuizChoices.makeAll(for: answers, pool: pool, using: &gen)

        XCTAssertEqual(all.count, answers.count)
        for (answer, choices) in zip(answers, all) {
            XCTAssertEqual(choices.count, 4)
            XCTAssertTrue(choices.contains(answer.title), "\(answer.title) が自分の設問の選択肢にない")
            XCTAssertEqual(Set(choices).count, choices.count, "重複した選択肢: \(choices)")
        }
    }
}
