import XCTest
@testable import ImasLiveDB

@MainActor
final class PollListViewModelTests: XCTestCase {

    private func makePoll(id: String, active: Bool) -> Poll {
        Poll(id: id, title: "お題\(id)", description: nil, targetType: .song,
             createdBy: "u1", createdAt: Date(),
             endsAt: Date().addingTimeInterval(active ? 86400 : -86400),
             status: "active", totalVotes: 0, entryCount: 0,
             candidateScope: .all, scopeBrandIds: nil, scopeEntityIds: nil)
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

    func testLoadPastPopulatesPastList() async {
        let fake = FakeCommunityVoting()
        fake.pollsByStatus["past"] = [makePoll(id: "old", active: false)]
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: false)

        XCTAssertEqual(vm.polls(active: false).map(\.id), ["old"])
        XCTAssertTrue(vm.polls(active: true).isEmpty)
    }

    func testLoadErrorSetsMessage() async {
        let fake = FakeCommunityVoting()
        fake.shouldThrow = true
        let vm = PollListViewModel(voting: fake)

        await vm.load(active: true)

        XCTAssertNotNil(vm.loadError)
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

@MainActor
final class PollHallOfFameViewModelTests: XCTestCase {

    func testLoadPopulatesResults() async {
        let fake = FakeCommunityVoting()
        fake.resultsToReturn = [
            PollResult(pollId: "p1", title: "最強の曲", targetType: .song,
                       endsAt: Date(), entityId: "s1", voteCount: 42)
        ]
        let vm = PollHallOfFameViewModel(voting: fake)

        await vm.load()

        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.loadError)
        XCTAssertEqual(vm.results.map(\.entityId), ["s1"])
    }

    func testLoadErrorSetsMessage() async {
        let fake = FakeCommunityVoting()
        fake.shouldThrow = true
        let vm = PollHallOfFameViewModel(voting: fake)

        await vm.load()

        XCTAssertNotNil(vm.loadError)
        XCTAssertTrue(vm.results.isEmpty)
    }
}
