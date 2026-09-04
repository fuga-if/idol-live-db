import XCTest
@testable import ImasLiveDB


/// `CallGuideDashboardReading` のスタブ。アプリ側の `FakeCallGuideDashboardReading`
/// (DEBUG の見た目確認用・曲マスタを読みに行く) とは別物なので名前を分けてある。
final class StubCallGuideDashboardReading: CallGuideDashboardReading, @unchecked Sendable {
    var dashboardToReturn = CallGuideDashboard(
        generatedAt: 0, songsWithCalls: [], recentEdits: [], taggedWithoutCalls: [], callTag: nil)
    var shouldThrow = false
    private(set) var callCount = 0

    enum StubError: Error { case boom }

    func callGuideDashboard() async throws -> CallGuideDashboard {
        callCount += 1
        if shouldThrow { throw StubError.boom }
        return dashboardToReturn
    }
}

/// `SongReading` のスタブ。コールガイド系のテストで使うのは `listableSongs(ids:)` だけ
/// (3 セクションぶんを 1 回で解決していることの確認に呼び出し回数も数える)。
final class StubSongReading: SongReading, @unchecked Sendable {
    /// 「ローカル master にある曲」。ここに無い id は解決できない = 行が落ちる。
    var known: [String: Song] = [:]
    private(set) var listableCallCount = 0
    private(set) var lastListableIds: [String] = []

    func listableSongs(ids: [String]) async throws -> [Song] {
        listableCallCount += 1
        lastListableIds = ids
        return ids.compactMap { known[$0] }
    }

    // MARK: - 未使用 (プロトコル充足のためのスタブ)

    func songs(filter: SongSearchFilter, sortOrder: SongSortOrder, ascending: Bool?) async throws -> [SongWithArtists] { [] }
    func song(id: String) async throws -> Song? { known[id] }
    func songs(ids: [String]) async throws -> [Song] { ids.compactMap { known[$0] } }
    func songIdsWithAnyArtist(idolIds: Set<String>) async throws -> Set<String> { [] }
    func songPerformerIdolsMap(songIds: [String]) async throws -> [String: [Idol]] { [:] }
    func songCollectedCounts() async throws -> [String: Int] { [:] }
    func songPerformanceCounts() async throws -> [String: Int] { [:] }
    func searchSongs(query: String, limit: Int) async throws -> [Song] { [] }
    func songSpellings() async throws -> [SongSpelling] { [] }
    func songPerformanceHistory(songId: String) async throws -> [PerformanceHistoryRow] { [] }
    func songArtists(songId: String, role: String?) async throws -> [Idol] { [] }
    func relatedSongs(to song: Song, limit: Int) async throws -> [Song] { [] }
    func variantSongs(of song: Song) async throws -> [Song] { [] }
    func collectedShows(for songId: String) async throws -> [ShowWithEventName] { [] }
    func songs(criterion: SongFilterCriterion) async throws -> [SongWithArtists] { [] }
    func songsByCreator(_ name: String) async throws -> [SongWithRoles] { [] }
    func allSongsForPicker() async throws -> [PickedSong] { [] }
    func albums(brandIds: Set<String>, query: String?) async throws -> [AlbumSummary] { [] }
    func series(brandIds: Set<String>, query: String?) async throws -> [SeriesSummary] { [] }
    func cdSeriesList() async throws -> [String] { [] }
    func seriesGroups(brandIds: Set<String>) async throws -> [String] { [] }
    func songIds(brandId: String, includeCovers: Bool, excludeRemixes: Bool) async throws -> [String] { [] }
    func originalSongIds(forShowCastOf showId: String) async throws -> Set<String> { [] }
    func brandedSongIds() async throws -> Set<String> { [] }
    func songCalls(songId: String) async throws -> [SongCall] { [] }
    func songVideos(songId: String) async throws -> [SongVideo] { [] }
}

/// テスト用の最小 `Song`。
func makeStubSong(_ id: String) -> Song {
    Song(
        id: id, title: "曲\(id)", titleKana: nil, brandId: nil, songType: "original",
        releaseDate: nil, durationSec: nil, composer: nil, lyricist: nil, arranger: nil,
        cdSeries: nil, cdTitle: nil, artworkUrl: nil, previewUrl: nil, appleMusicId: nil,
        appleMusicAlbumId: nil, isrc: nil, lyricsUrl: nil, parentSongId: nil,
        singerLabel: nil, unitName: nil, unitId: nil)
}

// MARK: - テスト

/// `CallGuideDashboardViewModel` の組み立てロジックの単体テスト。
/// 「1 リクエスト取得 → ローカル解決 1 回 → 3 セクション化」という規約そのものを検証する。
@MainActor
final class CallGuideDashboardViewModelTests: XCTestCase {

    private func summary(_ id: String, lines: Int = 4, count: Int = 10,
                         at: Int? = 1_756_900_000, by: String = "f***") -> CallGuideSongSummary {
        CallGuideSongSummary(songId: id, callLines: lines, callCount: count, updatedAt: at, updatedBy: by)
    }

    private func edit(_ id: Int, song: String, before: Int, after: Int,
                      linesAfter: Int = 9) -> CallGuideEditEntry {
        CallGuideEditEntry(
            id: id, songId: song, at: 1_756_900_000, by: "p***",
            callLinesBefore: before == 0 ? 0 : 5, callLinesAfter: linesAfter,
            callCountBefore: before, callCountAfter: after)
    }

    private func makeVM(_ dashboard: CallGuideDashboard, known: [String])
        -> (CallGuideDashboardViewModel, StubCallGuideDashboardReading, StubSongReading) {
        let port = StubCallGuideDashboardReading()
        port.dashboardToReturn = dashboard
        let songs = StubSongReading()
        songs.known = Dictionary(known.map { ($0, makeStubSong($0)) }, uniquingKeysWith: { a, _ in a })
        return (CallGuideDashboardViewModel(dashboard: port, songReading: songs), port, songs)
    }

    /// I1: 成功で 3 セクションがサーバの並びのまま埋まる。
    func testLoadFillsThreeSectionsInServerOrder() async {
        let dashboard = CallGuideDashboard(
            generatedAt: 1,
            songsWithCalls: [summary("s2"), summary("s1")],
            recentEdits: [edit(2, song: "s1", before: 0, after: 12), edit(1, song: "s2", before: 3, after: 8)],
            taggedWithoutCalls: ["s3", "s4"],
            callTag: CallGuideTagStatus(tagId: "t", tagName: "コール曲", tagged: 291, withCalls: 2, withoutLyrics: 46))
        let (vm, _, _) = makeVM(dashboard, known: ["s1", "s2", "s3", "s4"])

        await vm.load()

        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.loadError)
        XCTAssertEqual(vm.withCalls.map(\.id), ["s2", "s1"])
        XCTAssertEqual(vm.recentEdits.map(\.id), [2, 1])
        XCTAssertEqual(vm.wanted.map(\.id), ["s3", "s4"])
        XCTAssertEqual(vm.tag?.tagged, 291)
        // 未整備の件数は「タグ数 − ガイドあり − 歌詞なし」。一覧の行数とは一致しない。
        XCTAssertEqual(vm.tag?.writable, 243)
        XCTAssertFalse(vm.wantedTruncated)
    }

    /// I2: ローカル master に無い song_id の行は落ち、残りは出る。
    func testUnknownSongIdsAreDropped() async {
        let dashboard = CallGuideDashboard(
            generatedAt: 1,
            songsWithCalls: [summary("gone"), summary("s1")],
            recentEdits: [edit(1, song: "gone", before: 0, after: 5)],
            taggedWithoutCalls: ["s2", "gone2"],
            callTag: nil)
        let (vm, _, _) = makeVM(dashboard, known: ["s1", "s2"])

        await vm.load()

        XCTAssertEqual(vm.withCalls.map(\.id), ["s1"])
        XCTAssertTrue(vm.recentEdits.isEmpty)
        XCTAssertEqual(vm.wanted.map(\.id), ["s2"])
    }

    /// I3: ポートが throw したら `loadError` が入り、`isLoading` が戻る。
    func testLoadErrorSetsMessage() async {
        let (vm, port, _) = makeVM(
            CallGuideDashboard(generatedAt: 0, songsWithCalls: [], recentEdits: [],
                               taggedWithoutCalls: [], callTag: nil),
            known: [])
        port.shouldThrow = true

        await vm.load()

        XCTAssertNotNil(vm.loadError)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.withCalls.isEmpty)
    }

    /// I4: `CallGuideEditRow.label` の 3 パターン (付けた / 更新 / 削除)。
    func testEditRowLabelVariants() async {
        let dashboard = CallGuideDashboard(
            generatedAt: 1, songsWithCalls: [],
            recentEdits: [
                edit(1, song: "s1", before: 0, after: 42, linesAfter: 18),
                edit(2, song: "s1", before: 42, after: 50),
                edit(3, song: "s1", before: 42, after: 0),
            ],
            taggedWithoutCalls: [], callTag: nil)
        let (vm, _, _) = makeVM(dashboard, known: ["s1"])

        await vm.load()

        XCTAssertEqual(vm.recentEdits.map(\.label), [
            "コールを付けた (42件・18行)",
            "コールを更新 (42→50件)",
            "コールを削除した (42件→0)",
        ])
    }

    /// I5: 曲の解決は 3 セクションぶんまとめて 1 回だけ。
    func testResolvesSongsInASingleCall() async {
        let dashboard = CallGuideDashboard(
            generatedAt: 1,
            songsWithCalls: [summary("s1")],
            recentEdits: [edit(1, song: "s2", before: 0, after: 3)],
            taggedWithoutCalls: ["s3", "s1"],
            callTag: nil)
        let (vm, _, songs) = makeVM(dashboard, known: ["s1", "s2", "s3"])

        await vm.load()

        XCTAssertEqual(songs.listableCallCount, 1)
        // 重複はまとめて渡す (s1 は 2 セクションに出てくる)。
        XCTAssertEqual(Set(songs.lastListableIds), ["s1", "s2", "s3"])
        XCTAssertEqual(songs.lastListableIds.count, 3)
    }

    /// 未整備一覧がサーバ上限に達していたら「上位 100 件」と断れるようフラグを立てる。
    func testWantedTruncatedFlagAtServerLimit() async {
        let ids = (0 ..< 100).map { "w\($0)" }
        let dashboard = CallGuideDashboard(
            generatedAt: 1, songsWithCalls: [], recentEdits: [],
            taggedWithoutCalls: ids, callTag: nil)
        let (vm, _, _) = makeVM(dashboard, known: ids)

        await vm.load()

        XCTAssertTrue(vm.wantedTruncated)
        XCTAssertEqual(vm.wanted.count, 100)
    }
}
