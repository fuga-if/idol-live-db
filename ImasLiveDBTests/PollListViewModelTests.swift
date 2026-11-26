import XCTest
@testable import ImasLiveDB

@MainActor
final class PollListViewModelTests: XCTestCase {

    private func makePoll(id: String, active: Bool) -> Poll {
        Poll(id: id, title: "お題\(id)", description: nil, targetType: .song,
             createdBy: "u1", createdAt: Date(),
             endsAt: Date().addingTimeInterval(active ? 86400 : -86400),
             status: "active", totalVotes: 0, entryCount: 0,
             candidateScope: .all, scopeBrandIds: nil, scopeEntityIds: nil, topEntityId: nil)
    }

    func testLoadActivePopulatesActiveList() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["active"] = [makePoll(id: "p1", active: true)]
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: true)

        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.loadError)
        XCTAssertEqual(vm.polls(active: true).map(\.id), ["p1"])
        XCTAssertTrue(vm.polls(active: false).isEmpty)
    }

    func testLoadErrorSetsMessage() async {
        let fake = FakeCommunityVoting()
        fake.shouldThrow = true
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: true)

        XCTAssertNotNil(vm.loadError)
    }

    func testPastLoadsNewestMonthThenGoesBackOneMonthAtATime() async {
        let fake = FakeCommunityVoting()
        fake.monthsToReturn = [
            PollMonth(month: "2026-10", label: "2026.10", count: 1),
            PollMonth(month: "2026-09", label: "2026.09", count: 2),
        ]
        fake.pastPollsByMonth = [
            "2026-10": [makePoll(id: "oct", active: false)],
            "2026-09": [makePoll(id: "sep1", active: false), makePoll(id: "sep2", active: false)],
        ]
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: false)
        XCTAssertEqual(vm.polls(active: false).map(\.id), ["oct"])
        XCTAssertTrue(vm.hasMorePast)

        await vm.loadMorePast()
        XCTAssertEqual(vm.pastSections.map(\.id), ["2026-10", "2026-09"])
        XCTAssertEqual(vm.polls(active: false).map(\.id), ["oct", "sep1", "sep2"])
        XCTAssertFalse(vm.hasMorePast)

        // 読み直しても、さかのぼった月は畳まない。
        await vm.load(active: false)
        XCTAssertEqual(vm.pastSections.map(\.id), ["2026-10", "2026-09"])
        XCTAssertEqual(fake.pastPollMonthCalls, ["2026-10", "2026-09", "2026-10", "2026-09"])
    }

    func testActiveLoadsTwentyAtATimeAndKeepsLoadedCountOnReload() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["active"] = (0..<45).map { makePoll(id: "a\($0)", active: true) }
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: true)
        XCTAssertEqual(vm.polls(active: true).count, 20)
        XCTAssertTrue(vm.hasMoreActive)

        await vm.loadMoreActive()
        await vm.loadMoreActive()
        XCTAssertEqual(vm.polls(active: true).map(\.id), (0..<45).map { "a\($0)" })
        XCTAssertFalse(vm.hasMoreActive)

        // 詳細から戻っての読み直しで、読んだところまで畳まない。
        await vm.load(active: true)
        XCTAssertEqual(vm.polls(active: true).count, 45)
        XCTAssertEqual(fake.activePageCalls.map(\.offset), [0, 20, 40, 0])
        XCTAssertEqual(fake.activePageCalls.last?.limit, 45)
    }

    func testDefaultSortIsDeadlineSoonestFirstForActiveAndNewestFirstForPast() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["active"] = [makePoll(id: "p1", active: true)]
        fake.monthsToReturn = [PollMonth(month: "2026-10", label: "2026.10", count: 1)]
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: true)
        await vm.load(active: false)

        XCTAssertEqual(fake.activePageCalls.last?.sort, PollListSort(key: .deadline, ascending: true))
        XCTAssertEqual(fake.pastPollSorts.last, PollListSort(key: .deadline, ascending: false))
    }

    func testChangingSortKeyResetsDirectionAndReadsFromTheTop() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["active"] = (0..<45).map { makePoll(id: "a\($0)", active: true) }
        let vm = PollListViewModel(voting: fake)
        await vm.load(active: true)
        await vm.loadMoreActive()
        XCTAssertEqual(vm.polls(active: true).count, 40)

        // 票数順は多い順から。読み進めた 40 件は捨てて先頭の 20 件から読み直す。
        await vm.changeSortKey(.votes, active: true)
        XCTAssertEqual(vm.sort(active: true), PollListSort(key: .votes, ascending: false))
        XCTAssertEqual(fake.activePageCalls.last?.offset, 0)
        XCTAssertEqual(fake.activePageCalls.last?.limit, PollListViewModel.activePageSize)
        XCTAssertEqual(vm.polls(active: true).count, 20)

        await vm.changeSortAscending(true, active: true)
        XCTAssertEqual(fake.activePageCalls.last?.sort, PollListSort(key: .votes, ascending: true))

        // 続きも今の並びで読む。
        await vm.loadMoreActive()
        XCTAssertEqual(fake.activePageCalls.last?.offset, 20)
        XCTAssertEqual(fake.activePageCalls.last?.sort, PollListSort(key: .votes, ascending: true))

        // 終了タブの並びは別に持つ。
        XCTAssertEqual(vm.sort(active: false), .standard(active: false))
    }

    func testSameSortDoesNotReload() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["active"] = [makePoll(id: "p1", active: true)]
        let vm = PollListViewModel(voting: fake)
        await vm.load(active: true)

        await vm.changeSortKey(.deadline, active: true)
        await vm.changeSortAscending(true, active: true)

        XCTAssertEqual(fake.activePageCalls.count, 1)
    }

    func testPastSortGoesBackToNewestMonthOnly() async {
        let fake = FakeCommunityVoting()
        fake.monthsToReturn = [
            PollMonth(month: "2026-10", label: "2026.10", count: 1),
            PollMonth(month: "2026-09", label: "2026.09", count: 2),
        ]
        let vm = PollListViewModel(voting: fake)
        await vm.load(active: false)
        await vm.loadMorePast()
        XCTAssertEqual(vm.pastSections.count, 2)
        XCTAssertEqual(vm.totalCount(active: false), 3)

        await vm.changeSortKey(.created, active: false)

        XCTAssertEqual(vm.pastSections.map(\.id), ["2026-10"])
        XCTAssertEqual(fake.pastPollSorts.last, PollListSort(key: .created, ascending: false))
    }

    func testActiveTotalCountComesFromServerAndIsNilWhenUnavailable() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["active"] = [makePoll(id: "p1", active: true)]
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: true)
        XCTAssertNil(vm.totalCount(active: true))
        XCTAssertNil(vm.loadError)

        fake.countsToReturn = PollCounts(active: 37, past: 120)
        await vm.load(active: true)
        XCTAssertEqual(vm.totalCount(active: true), 37)

        vm.insertCreated(makePoll(id: "new", active: true))
        XCTAssertEqual(vm.totalCount(active: true), 38)
    }

    func testInsertCreatedPrependsActivePoll() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["active"] = [makePoll(id: "p1", active: true)]
        let vm = PollListViewModel(voting: fake)
        await vm.load(active: true)

        vm.insertCreated(makePoll(id: "new", active: true))

        XCTAssertEqual(vm.polls(active: true).map(\.id), ["new", "p1"])
    }
}
