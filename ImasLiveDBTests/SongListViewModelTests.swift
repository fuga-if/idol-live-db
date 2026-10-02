import XCTest
@testable import ImasLiveDB

/// 端末に覚えた印のスタブ。
final class StubLyricAnnotations: LyricAnnotationProviding, @unchecked Sendable {
    var calls: Set<String> = []
    var timings: Set<String> = []
    var shouldThrow = false
    /// n 回目の呼び出しが応答を返す直前に走るフック (世代ガードの検証用)。
    var beforeReturn: [Int: @MainActor () async -> Void] = [:]
    private(set) var callCount = 0

    enum StubError: Error { case boom }

    func songIds(_ kind: LyricAnnotationKind) async throws -> Set<String> {
        callCount += 1
        let call = callCount
        if let hook = beforeReturn[call] { await hook() }
        if shouldThrow { throw StubError.boom }
        return kind == .calls ? calls : timings
    }
}

/// `SongListViewModel` のコールガイド・タイミング絞り込み解決の単体テスト。
@MainActor
final class SongListViewModelTests: XCTestCase {

    private func makeVM(calls: Set<String> = [], timings: Set<String> = []) -> (SongListViewModel, StubLyricAnnotations) {
        let port = StubLyricAnnotations()
        port.calls = calls
        port.timings = timings
        return (SongListViewModel(songReading: StubSongReading(), annotations: port), port)
    }

    func testResolveEnabledBuildsIdSet() async {
        let (vm, port) = makeVM(calls: ["s1", "s2"])
        await vm.resolveCallGuideFilter(true)
        XCTAssertEqual(vm.callGuideSongIds, ["s1", "s2"])
        XCTAssertFalse(vm.callGuideFilterError)
        XCTAssertEqual(port.callCount, 1)
    }

    func testTimingFilterUsesTimingSet() async {
        let (vm, _) = makeVM(calls: ["s1"], timings: ["s9"])
        await vm.resolveLyricTimingFilter(true)
        XCTAssertEqual(vm.lyricTimingSongIds, ["s9"])
    }

    /// 取得中にトグルが OFF に戻ったら、遅れて届いた応答で絞り込みを復活させない。
    func testStaleResolveDoesNotRestoreClearedFilter() async {
        let (vm, port) = makeVM(calls: ["s1"])
        port.beforeReturn[1] = { [weak vm] in await vm?.resolveCallGuideFilter(false) }
        await vm.resolveCallGuideFilter(true)
        XCTAssertNil(vm.callGuideSongIds, "解除したはずの絞り込みが遅れて復活してはいけない")
        XCTAssertFalse(vm.callGuideFilterError)
    }

    func testResolveDisabledClearsSetWithoutFetching() async {
        let (vm, port) = makeVM(calls: ["s1"])
        await vm.resolveCallGuideFilter(true)
        await vm.resolveCallGuideFilter(false)
        XCTAssertNil(vm.callGuideSongIds)
        XCTAssertEqual(port.callCount, 1, "解除で取りに行ってはいけない")
    }

    /// 失敗時はフラグだけ立て、既存の集合を変更しない (オフラインで一覧を誤って空にしない)。
    func testResolveFailureKeepsPreviousSet() async {
        let (vm, port) = makeVM(calls: ["s1"])
        await vm.resolveCallGuideFilter(true)
        port.shouldThrow = true
        await vm.resolveCallGuideFilter(true)
        XCTAssertTrue(vm.callGuideFilterError)
        XCTAssertEqual(vm.callGuideSongIds, ["s1"])
    }
}

/// ページを返すスタブ。
final class StubAnnotationReader: LyricAnnotationReading, @unchecked Sendable {
    var pages: [String: LyricAnnotationsPage] = [:]
    var shouldThrow = false
    private(set) var requests: [String?] = []

    func lyricAnnotations(after: String?, limit: Int) async throws -> LyricAnnotationsPage {
        requests.append(after)
        if shouldThrow { throw StubLyricAnnotations.StubError.boom }
        return pages[after ?? ""] ?? LyricAnnotationsPage(songs: [], next: nil)
    }
}

/// `LyricAnnotationStore`: 全ページを辿って覚え、古くなるまでは取りに行かない。
final class LyricAnnotationStoreTests: XCTestCase {
    private func defaults() -> String { "test_\(UUID().uuidString)" }

    func testFetchesAllPagesAndCaches() async throws {
        let reader = StubAnnotationReader()
        reader.pages[""] = LyricAnnotationsPage(
            songs: [.init(songId: "a", calls: true, timings: false)], next: "a")
        reader.pages["a"] = LyricAnnotationsPage(
            songs: [.init(songId: "b", calls: true, timings: true)], next: nil)
        let store = LyricAnnotationStore(reader: reader, suiteName: defaults(), key: "k")

        let calls = try await store.songIds(.calls)
        let timings = try await store.songIds(.timings)

        XCTAssertEqual(calls, ["a", "b"])
        XCTAssertEqual(timings, ["b"])
        XCTAssertEqual(reader.requests, [nil, "a"], "2 回目は覚えた分を使い、取りに行かない")
    }

    func testFallsBackToCacheWhenRefreshFails() async throws {
        let reader = StubAnnotationReader()
        reader.pages[""] = LyricAnnotationsPage(songs: [.init(songId: "a", calls: true, timings: false)], next: nil)
        let d = defaults()
        _ = try await LyricAnnotationStore(reader: reader, suiteName: d, key: "k").songIds(.calls)
        // 古くなった扱い (maxAge 0) で取り直しに失敗しても、覚えた分で答える。
        reader.shouldThrow = true
        let stale = LyricAnnotationStore(reader: reader, suiteName: d, key: "k", maxAge: 0)
        let calls = try await stale.songIds(.calls)
        XCTAssertEqual(calls, ["a"])
    }

    func testMarkAddsWithoutRefetch() async throws {
        let reader = StubAnnotationReader()
        let store = LyricAnnotationStore(reader: reader, suiteName: defaults(), key: "k")
        _ = try await store.songIds(.timings)
        await store.mark(songId: "z", .timings, true)
        let timings = try await store.songIds(.timings)
        XCTAssertEqual(timings, ["z"])
    }
}
