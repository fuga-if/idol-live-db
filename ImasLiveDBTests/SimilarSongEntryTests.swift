import XCTest
@testable import ImasLiveDB

/// `SimilarSongEntry` のデコードと抽選重みのテスト。
///
/// アプリと Worker は別々に配信されるので、**新しいアプリが旧サーバに当たる**期間が
/// ありうる (審査待ちなど)。その時に `score` が返ってこなくても、おすすめが空に
/// ならないことを保証する。
final class SimilarSongEntryTests: XCTestCase {

    private func decode(_ json: String) throws -> SimilarSongsResponse {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SimilarSongsResponse.self, from: Data(json.utf8))
    }

    /// 新サーバ: score を重みに使う。
    func testUsesScoreWhenPresent() throws {
        let res = try decode("""
        {"song_id":"a","songs":[{"song_id":"b","shared_tags":7,"vote_score":35,"score":0.41}]}
        """)
        XCTAssertEqual(res.songs.first?.score, 0.41)
        XCTAssertEqual(res.songs.first?.pickWeight, 0.41)
    }

    /// 旧サーバ: score が無くてもデコードでき、共有タグ数を重みに代用する。
    func testFallsBackToSharedTagsWhenScoreMissing() throws {
        let res = try decode("""
        {"song_id":"a","songs":[{"song_id":"b","shared_tags":3}]}
        """)
        XCTAssertNil(res.songs.first?.score)
        XCTAssertEqual(res.songs.first?.pickWeight, 3)
    }

    /// 旧サーバ応答でも抽選が空にならない (重み 0 だけになると穴埋めしか出ない)。
    func testLegacyResponseStillYieldsRecommendations() throws {
        let res = try decode("""
        {"song_id":"a","songs":[
          {"song_id":"b","shared_tags":3},
          {"song_id":"c","shared_tags":2},
          {"song_id":"d","shared_tags":1}]}
        """)
        let picked = WeightedSampling.pick(res.songs, count: 2, weight: \.pickWeight)
        XCTAssertEqual(picked.count, 2)
        XCTAssertEqual(Set(picked.map(\.songId)).count, 2)
    }
}
