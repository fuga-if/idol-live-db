import XCTest
@testable import ImasLiveDB

/// `SongListViewModel` のコールガイド絞り込み解決の単体テスト。
/// フェイクは `CallGuideDashboardViewModelTests.swift` の `Stub*` を共有する。
@MainActor
final class SongListViewModelTests: XCTestCase {

    private func summary(_ id: String) -> CallGuideSongSummary {
        CallGuideSongSummary(songId: id, callLines: 4, callCount: 10, updatedAt: 0, updatedBy: "匿名")
    }

    private func makeVM(_ ids: [String]) -> (SongListViewModel, StubCallGuideDashboardReading) {
        let port = StubCallGuideDashboardReading()
        port.dashboardToReturn = CallGuideDashboard(
            generatedAt: 0, songsWithCalls: ids.map(summary), recentEdits: [],
            taggedWithoutCalls: [], callTag: nil)
        return (SongListViewModel(songReading: StubSongReading(), callGuideDashboard: port), port)
    }

    /// I6: 有効化で `songsWithCalls` の id 集合になる。
    func testResolveEnabledBuildsIdSet() async {
        let (vm, port) = makeVM(["s1", "s2"])

        await vm.resolveCallGuideFilter(true)

        XCTAssertEqual(vm.callGuideSongIds, ["s1", "s2"])
        XCTAssertFalse(vm.callGuideFilterError)
        XCTAssertFalse(vm.callGuideFilterTruncated)
        XCTAssertEqual(port.callCount, 1)
    }

    /// H-1: 集合がサーバ上限 (200) に達していたら打ち切りとして画面で断れるようにする。
    func testTruncatedSetRaisesFlag() async {
        let (vm, _) = makeVM((0 ..< 200).map { "s\($0)" })

        await vm.resolveCallGuideFilter(true)

        XCTAssertTrue(vm.callGuideFilterTruncated)
        XCTAssertEqual(vm.callGuideSongIds?.count, 200)
    }

    /// M-1: 通信中にトグルが OFF に戻ったら、遅れて届いた成功応答で絞り込みを復活させない。
    func testStaleResolveDoesNotRestoreClearedFilter() async {
        let port = StubCallGuideDashboardReading()
        port.dashboardToReturn = CallGuideDashboard(
            generatedAt: 0, songsWithCalls: [summary("s1")], recentEdits: [],
            taggedWithoutCalls: [], callTag: nil)
        let vm = SongListViewModel(songReading: StubSongReading(), callGuideDashboard: port)
        // 応答を返す前にトグルが OFF に戻る (解除は通信しないので世代だけが進む)。
        port.beforeReturn[1] = { [weak vm] in await vm?.resolveCallGuideFilter(false) }

        await vm.resolveCallGuideFilter(true)

        XCTAssertNil(vm.callGuideSongIds, "解除したはずの絞り込みが遅れて復活してはいけない")
        XCTAssertFalse(vm.callGuideFilterError)
    }

    /// I7: 無効化で nil に戻る (絞り込み解除)。通信もしない。
    func testResolveDisabledClearsSet() async {
        let (vm, port) = makeVM(["s1"])
        await vm.resolveCallGuideFilter(true)

        await vm.resolveCallGuideFilter(false)

        XCTAssertNil(vm.callGuideSongIds)
        XCTAssertFalse(vm.callGuideFilterError)
        XCTAssertFalse(vm.callGuideFilterTruncated)
        XCTAssertEqual(port.callCount, 1, "解除で通信してはいけない")
    }

    /// I8: 失敗時はフラグだけ立て、既存の集合を変更しない
    /// (オフラインで一覧を誤って空にしないため。タグ絞り込みと同じ失敗規約)。
    func testResolveFailureKeepsPreviousSet() async {
        let (vm, port) = makeVM(["s1"])
        await vm.resolveCallGuideFilter(true)
        port.shouldThrow = true

        await vm.resolveCallGuideFilter(true)

        XCTAssertTrue(vm.callGuideFilterError)
        XCTAssertEqual(vm.callGuideSongIds, ["s1"])
    }

    /// 一度失敗したあとに成功したらフラグは下りる。
    func testResolveRecoversAfterFailure() async {
        let (vm, port) = makeVM(["s1"])
        port.shouldThrow = true
        await vm.resolveCallGuideFilter(true)
        XCTAssertTrue(vm.callGuideFilterError)

        port.shouldThrow = false
        await vm.resolveCallGuideFilter(true)

        XCTAssertFalse(vm.callGuideFilterError)
        XCTAssertEqual(vm.callGuideSongIds, ["s1"])
    }
}
