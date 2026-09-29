import XCTest
@testable import ImasLiveDB

/// `applySongMarkFilters` (純粋ロジック) の単体テスト。DB に依存しない。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class SongListFilteringTests: XCTestCase {

    private func makeSWA(_ id: String, titleKana: String? = nil) -> SongWithArtists {
        let song = Song(
            id: id, title: "曲\(id)", titleKana: titleKana, brandId: nil, songType: "original",
            releaseDate: nil, durationSec: nil, composer: nil, lyricist: nil, arranger: nil,
            cdSeries: nil, cdTitle: nil, artworkUrl: nil, previewUrl: nil, appleMusicId: nil,
            appleMusicAlbumId: nil, isrc: nil, lyricsUrl: nil, parentSongId: nil,
            singerLabel: nil, unitName: nil, unitId: nil)
        return SongWithArtists(song: song, artistNames: "")
    }

    private let all = ["a", "b", "c"]
    private func songs() -> [SongWithArtists] { all.map { makeSWA($0) } }

    func testUncollectedExcludesCollected() {
        var ctx = SongMarkFilterContext(collectFilter: .uncollected)
        ctx.collectedIds = ["a", "c"]
        XCTAssertEqual(applySongMarkFilters(songs(), ctx).map(\.id), ["b"])
    }

    // MARK: - コールガイド絞り込み

    /// I11: タグ集合との併用は AND。タグ票数ソートの並びも壊れない。
    func testCallGuideAndsWithTagsAndKeepsVoteRanking() {
        let input = [makeSWA("a", titleKana: "あ"), makeSWA("b", titleKana: "い"), makeSWA("c", titleKana: "う")]
        var ctx = SongMarkFilterContext(collectFilter: .all)
        ctx.tagSongIds = ["a", "b", "c"]
        ctx.callGuideSongIds = ["b", "c"]
        ctx.rankByTagVotes = true
        ctx.tagVoteCounts = ["a": 99, "b": 1, "c": 5]
        // AND で a が落ち、残った集合に対して票数降順 (c=5 → b=1)。
        XCTAssertEqual(applySongMarkFilters(input, ctx).map(\.id), ["c", "b"])
    }
}
