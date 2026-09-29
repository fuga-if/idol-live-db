import XCTest
@testable import ImasLiveDB

/// セトリ予想の画面の「機械予測」の節 (`SetlistForecastViewModel`) の単体テスト。
///
/// 点数・順位・理由の規則はコア (`setlist_forecast.rs` の `#[test]`) が持つので、ここでは見ない。
/// 見るのは、みんなの予想に入っている曲を隠すこと・格上げ・失敗したときに節を出さないこと。
@MainActor
final class SetlistForecastViewModelTests: XCTestCase {

    private enum FakeError: Error { case boom }

    // MARK: - Fakes

    private struct FakeForecastReading: SetlistForecastReading {
        var record: SetlistForecastRecord?
        var fail = false

        func setlistForecast(showId: String, limit: Int) async throws -> SetlistForecastRecord? {
            if fail { throw FakeError.boom }
            return record
        }
    }

    @MainActor
    private final class FakeVoting: SetlistPredictionVoting {
        var fail = false
        private(set) var votedSongIds: [String] = []

        func vote(showId: String, songId: String) async throws -> PredictionVoteResult {
            if fail { throw FakeError.boom }
            votedSongIds.append(songId)
            return PredictionVoteResult(songId: songId, voteCount: 1, alreadyVoted: false)
        }
    }

    private func song(_ id: String, rank: UInt32) -> ForecastSongRecord {
        ForecastSongRecord(
            rank: rank, songId: id, title: "曲\(id)", score: 0.5,
            reasons: [ForecastReasonRecord(reason: .frequentlyPerformed, label: "よく歌われている")])
    }

    private func record(songIds: [String], flags: [ForecastShowFlagRecord] = []) -> SetlistForecastRecord {
        SetlistForecastRecord(
            showId: "show1",
            songs: songIds.enumerated().map { song($1, rank: UInt32($0 + 1)) },
            flags: flags,
            trainingShowCount: 100)
    }

    private func makeModel(
        reading: FakeForecastReading, voting: FakeVoting = FakeVoting()
    ) -> SetlistForecastViewModel {
        SetlistForecastViewModel(showId: "show1", reading: reading, voting: voting)
    }

    // MARK: - みんなの予想に入っている曲を隠す

    func testHidesSongsAlreadyInPredictions() async {
        let model = makeModel(reading: FakeForecastReading(record: record(songIds: ["a", "b", "c"])))
        await model.load()

        let visible = model.visibleSongs(predictedSongIds: ["b"])

        XCTAssertEqual(visible.map(\.songId), ["a", "c"])
        // 順位はコアの答えのまま (詰め直さない)。
        XCTAssertEqual(visible.map(\.rank), [1, 3])
    }

    // MARK: - 格上げ

    func testPromoteSuccessRemovesSongFromForecast() async throws {
        let voting = FakeVoting()
        let model = makeModel(reading: FakeForecastReading(record: record(songIds: ["a", "b"])), voting: voting)
        await model.load()

        try await model.promote(songId: "a")

        XCTAssertEqual(voting.votedSongIds, ["a"])
        XCTAssertEqual(model.visibleSongs(predictedSongIds: []).map(\.songId), ["b"])
        XCTAssertNil(model.promotingSongId)
    }

    func testPromoteFailureKeepsSongAndThrows() async {
        let voting = FakeVoting()
        voting.fail = true
        let model = makeModel(reading: FakeForecastReading(record: record(songIds: ["a", "b"])), voting: voting)
        await model.load()

        do {
            try await model.promote(songId: "a")
            XCTFail("投票の失敗は呼び出し側 (画面の既存のエラー表示) に渡す")
        } catch {}

        XCTAssertEqual(model.visibleSongs(predictedSongIds: []).map(\.songId), ["a", "b"])
        XCTAssertNil(model.promotingSongId)
    }

    // MARK: - 失敗・対象外は節を出さない

    func testLoadFailureHidesSection() async {
        let model = makeModel(reading: FakeForecastReading(fail: true))
        await model.load()

        guard case .unavailable = model.phase else { return XCTFail("失敗したら節を出さない") }
        XCTAssertTrue(model.visibleSongs(predictedSongIds: []).isEmpty)
    }

    func testNotForecastableShowHidesSection() async {
        let model = makeModel(reading: FakeForecastReading(record: nil))
        await model.load()

        guard case .unavailable = model.phase else { return XCTFail("対象外の公演は節を出さない") }
    }

    // MARK: - 出演者未発表の注記

    func testCastUnannouncedNoteUsesCoreLabel() async {
        let flag = ForecastShowFlagRecord(flag: .castUnannounced, label: "出演者未発表のため精度が低い")
        let model = makeModel(reading: FakeForecastReading(record: record(songIds: ["a"], flags: [flag])))
        await model.load()

        XCTAssertEqual(model.castUnannouncedNote, "出演者未発表のため精度が低い")
    }
}
