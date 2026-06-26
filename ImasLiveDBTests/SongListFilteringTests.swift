import XCTest
@testable import ImasLiveDB

/// `applySongMarkFilters` (純粋ロジック) の単体テスト。DB に依存しない。
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

    func testAllPassesThrough() {
        let ctx = SongMarkFilterContext(collectFilter: .all)
        XCTAssertEqual(applySongMarkFilters(songs(), ctx).map(\.id), all)
    }

    func testCollectedKeepsOnlyCollected() {
        var ctx = SongMarkFilterContext(collectFilter: .collected)
        ctx.collectedIds = ["a", "c"]
        XCTAssertEqual(applySongMarkFilters(songs(), ctx).map(\.id), ["a", "c"])
    }

    func testUncollectedExcludesCollected() {
        var ctx = SongMarkFilterContext(collectFilter: .uncollected)
        ctx.collectedIds = ["a", "c"]
        XCTAssertEqual(applySongMarkFilters(songs(), ctx).map(\.id), ["b"])
    }

    func testFavoriteAndNoteAreAndConditions() {
        var ctx = SongMarkFilterContext(collectFilter: .all)
        ctx.requireFavorite = true
        ctx.favoriteIds = ["a", "b"]
        ctx.requireNote = true
        ctx.noteIds = ["b", "c"]
        // AND: a∈fav かつ b∈note の積 → b のみ
        XCTAssertEqual(applySongMarkFilters(songs(), ctx).map(\.id), ["b"])
    }

    func testMyPickFilter() {
        var ctx = SongMarkFilterContext(collectFilter: .all)
        ctx.requireMyPick = true
        ctx.myPickSongIds = ["c"]
        XCTAssertEqual(applySongMarkFilters(songs(), ctx).map(\.id), ["c"])
    }

    func testTagFilterRestrictsToTagSet() {
        var ctx = SongMarkFilterContext(collectFilter: .all)
        ctx.tagSongIds = ["a", "c"]
        XCTAssertEqual(applySongMarkFilters(songs(), ctx).map(\.id), ["a", "c"])
    }

    func testTagRankingSortsByVotesThenKana() {
        let input = [makeSWA("a", titleKana: "あ"), makeSWA("b", titleKana: "い"), makeSWA("c", titleKana: "う")]
        var ctx = SongMarkFilterContext(collectFilter: .all)
        ctx.tagSongIds = ["a", "b", "c"]
        ctx.rankByTagVotes = true
        ctx.tagVoteCounts = ["a": 1, "b": 5, "c": 5]
        // 票数降順 (b,c=5 → a=1)、同票は 50 音 (b=い < c=う)。
        XCTAssertEqual(applySongMarkFilters(input, ctx).map(\.id), ["b", "c", "a"])
    }

    func testTagRankingNotAppliedWhenFlagFalse() {
        let input = [makeSWA("a"), makeSWA("b")]
        var ctx = SongMarkFilterContext(collectFilter: .all)
        ctx.tagSongIds = ["a", "b"]
        ctx.rankByTagVotes = false
        ctx.tagVoteCounts = ["a": 1, "b": 99]
        // 並べ替えなし → 入力順維持。
        XCTAssertEqual(applySongMarkFilters(input, ctx).map(\.id), ["a", "b"])
    }
}
