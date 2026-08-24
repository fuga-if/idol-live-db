import XCTest
@testable import ImasLiveDB

/// `IntroQuizChoices` (imas-core 委譲) の単体テスト。
///
/// 規則そのもの (タイトルでのユニーク化・不正解候補が pool 順を保つこと等) は
/// imas-core の `domain/intro_quiz_choices.rs` の Rust テストが担う。ここでは
/// Swift ラッパ (射影とシード調達) を通しても核心が成り立つことを見る。核心は
/// 「同名異曲が pool にあっても、正解と同じタイトルが不正解として並ばない」こと
/// (並ぶと正しい答えを選んでも不正解になる)。
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

    /// 正解と同じタイトルの別バージョンは不正解候補にしない。
    /// ここが壊れると「正解を選んだのに不正解」になる。
    func testExcludesSameTitleDifferentSong() {
        let answer = makeSong("s1", "READY!!")
        let pool = [answer, makeSong("s2", "READY!! (M@STER VERSION)"), makeSong("s3", "READY!!")]
        for seed in 0..<40 {
            let choices = makeChoices(for: answer, pool: pool, seed: UInt64(seed))
            XCTAssertEqual(Set(choices), ["READY!!", "READY!! (M@STER VERSION)"])
            XCTAssertEqual(choices.count, 2, "正解と同じタイトルが重複して並んだ: \(choices)")
        }
    }

    /// 正解そのもの (同じ id) は不正解候補から外れる。
    func testExcludesAnswerItself() {
        let answer = makeSong("s1", "GO MY WAY!!")
        let choices = makeChoices(for: answer, pool: [answer, makeSong("s2", "蒼い鳥")])
        XCTAssertEqual(Set(choices), ["GO MY WAY!!", "蒼い鳥"])
        XCTAssertEqual(choices.count, 2)
    }

    /// 不正解どうしのタイトル重複も落とす (同じ選択肢が 2 つ並ばない)。
    func testDeduplicatesAmongWrongCandidates() {
        let answer = makeSong("s1", "自転車")
        let pool = [makeSong("s2", "隣に…"), makeSong("s3", "隣に…"), makeSong("s4", "オーバーマスター")]
        let choices = makeChoices(for: answer, pool: pool)
        XCTAssertEqual(Set(choices), ["自転車", "隣に…", "オーバーマスター"])
        XCTAssertEqual(choices.count, 3, "不正解どうしの重複が残った: \(choices)")
    }

    // MARK: - 出題される 4 択

    func testMakeReturnsFourUniqueChoicesIncludingAnswer() {
        let answer = makeSong("s0", "答え")
        let pool = (1...10).map { makeSong("s\($0)", "曲\($0)") }

        let choices = makeChoices(for: answer, pool: pool)

        XCTAssertEqual(choices.count, 4)
        XCTAssertEqual(Set(choices).count, 4, "同じ選択肢が 2 つ並んではいけない")
        XCTAssertTrue(choices.contains("答え"), "正解は必ず選択肢に入る")
    }

    /// 候補が足りなくても落ちず、正解は必ず残る (ブランド曲数が少ない設定への備え)。
    func testMakeWithTooFewCandidates() {
        let choices = makeChoices(for: makeSong("s0", "答え"), pool: [makeSong("s1", "曲1")], seed: 7)
        XCTAssertEqual(choices.sorted(), ["曲1", "答え"].sorted())
    }

    /// pool が空でも正解 1 つは返る。
    func testMakeWithEmptyPool() {
        XCTAssertEqual(makeChoices(for: makeSong("s0", "答え"), pool: [], seed: 7), ["答え"])
    }

    /// 正解の位置が固定されない (常に末尾なら位置で当てられてしまう)。
    func testAnswerPositionVaries() {
        let answer = makeSong("s0", "答え")
        let pool = (1...10).map { makeSong("s\($0)", "曲\($0)") }
        var positions: Set<Int> = []
        for seed in 0..<40 {
            let choices = makeChoices(for: answer, pool: pool, seed: UInt64(seed))
            positions.insert(choices.firstIndex(of: "答え")!)
        }
        XCTAssertTrue(positions.count > 1, "正解の位置が固定されている: \(positions)")
    }

    /// 同名異曲がある実データ相当の pool でも、選択肢にタイトル重複が出ない。
    func testMakeNeverProducesDuplicateTitles() {
        let answer = makeSong("s0", "READY!!")
        let pool = [
            makeSong("s1", "READY!!"), makeSong("s2", "READY!!"),
            makeSong("s3", "CHANGE!!!!"), makeSong("s4", "CHANGE!!!!"),
            makeSong("s5", "M@STERPIECE"),
        ]
        for seed in 0..<40 {
            let choices = makeChoices(for: answer, pool: pool, seed: UInt64(seed))
            XCTAssertEqual(Set(choices).count, choices.count, "重複した選択肢: \(choices)")
            XCTAssertTrue(choices.contains("READY!!"))
        }
    }

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
