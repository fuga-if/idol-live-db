import XCTest
@testable import ImasLiveDB

/// `IntroQuizChoices` の単体テスト。
///
/// 1 人用と対戦で同じ選択肢生成を使うための共通規則。核心は
/// 「同名異曲が pool にあっても、正解と同じタイトルが不正解として並ばない」こと
/// (並ぶと正しい答えを選んでも不正解になる)。
final class IntroQuizChoicesTests: XCTestCase {

    /// 固定乱数 (SplitMix64)。シャッフルを含む経路を決定論的に検証するため。
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

    // MARK: - wrongCandidates (規則そのもの)

    /// 正解と同じタイトルの別バージョンは不正解候補にしない。
    /// ここが壊れると「正解を選んだのに不正解」になる。
    func testExcludesSameTitleDifferentSong() {
        let answer = makeSong("s1", "READY!!")
        let pool = [answer, makeSong("s2", "READY!! (M@STER VERSION)"), makeSong("s3", "READY!!")]
        let titles = IntroQuizChoices.wrongCandidates(for: answer, pool: pool).map(\.title)
        XCTAssertFalse(titles.contains("READY!!"))
        XCTAssertEqual(titles, ["READY!! (M@STER VERSION)"])
    }

    /// 正解そのもの (同じ id) は候補から外す。
    func testExcludesAnswerItself() {
        let answer = makeSong("s1", "GO MY WAY!!")
        let ids = IntroQuizChoices.wrongCandidates(for: answer, pool: [answer, makeSong("s2", "蒼い鳥")])
            .map(\.id)
        XCTAssertEqual(ids, ["s2"])
    }

    /// 不正解どうしのタイトル重複も落とす (同じ選択肢が 2 つ並ばない)。
    func testDeduplicatesAmongWrongCandidates() {
        let answer = makeSong("s1", "自転車")
        let pool = [makeSong("s2", "隣に…"), makeSong("s3", "隣に…"), makeSong("s4", "オーバーマスター")]
        let titles = IntroQuizChoices.wrongCandidates(for: answer, pool: pool).map(\.title)
        XCTAssertEqual(titles, ["隣に…", "オーバーマスター"])
    }

    /// 順序は pool のまま (シャッフルは make 側の責務)。
    func testWrongCandidatesKeepPoolOrder() {
        let answer = makeSong("s0", "答え")
        let pool = (1...5).map { makeSong("s\($0)", "曲\($0)") }
        XCTAssertEqual(
            IntroQuizChoices.wrongCandidates(for: answer, pool: pool).map(\.id),
            ["s1", "s2", "s3", "s4", "s5"])
    }

    func testEmptyPoolYieldsNoCandidates() {
        XCTAssertTrue(IntroQuizChoices.wrongCandidates(for: makeSong("s1", "答え"), pool: []).isEmpty)
    }

    // MARK: - make (出題される 4 択)

    func testMakeReturnsFourUniqueChoicesIncludingAnswer() {
        var gen = SeededGenerator(state: 42)
        let answer = makeSong("s0", "答え")
        let pool = (1...10).map { makeSong("s\($0)", "曲\($0)") }

        let choices = IntroQuizChoices.make(for: answer, pool: pool, using: &gen)

        XCTAssertEqual(choices.count, 4)
        XCTAssertEqual(Set(choices).count, 4, "同じ選択肢が 2 つ並んではいけない")
        XCTAssertTrue(choices.contains("答え"), "正解は必ず選択肢に入る")
    }

    /// 候補が足りなくても落ちず、正解は必ず残る (ブランド曲数が少ない設定への備え)。
    func testMakeWithTooFewCandidates() {
        var gen = SeededGenerator(state: 7)
        let answer = makeSong("s0", "答え")
        let choices = IntroQuizChoices.make(for: answer, pool: [makeSong("s1", "曲1")], using: &gen)
        XCTAssertEqual(choices.sorted(), ["曲1", "答え"].sorted())
    }

    /// pool が空でも正解 1 つは返る。
    func testMakeWithEmptyPool() {
        var gen = SeededGenerator(state: 7)
        XCTAssertEqual(IntroQuizChoices.make(for: makeSong("s0", "答え"), pool: [], using: &gen), ["答え"])
    }

    /// 正解の位置が固定されない (常に末尾なら位置で当てられてしまう)。
    func testAnswerPositionVaries() {
        let answer = makeSong("s0", "答え")
        let pool = (1...10).map { makeSong("s\($0)", "曲\($0)") }
        var positions: Set<Int> = []
        for seed in 0..<40 {
            var gen = SeededGenerator(state: UInt64(seed))
            let choices = IntroQuizChoices.make(for: answer, pool: pool, using: &gen)
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
            var gen = SeededGenerator(state: UInt64(seed))
            let choices = IntroQuizChoices.make(for: answer, pool: pool, using: &gen)
            XCTAssertEqual(Set(choices).count, choices.count, "重複した選択肢: \(choices)")
            XCTAssertTrue(choices.contains("READY!!"))
        }
    }
}
