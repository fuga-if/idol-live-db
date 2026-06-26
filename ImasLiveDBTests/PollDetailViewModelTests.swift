import XCTest
@testable import ImasLiveDB

/// `CommunityVoting` のフェイク。注入して ViewModel の投票ロジックを単体検証する。
/// @MainActor にして状態アクセスを直列化 (テストも @MainActor)。
@MainActor
final class FakeCommunityVoting: CommunityVoting {
    var detailToReturn: PollDetail?
    var pollsByStatus: [String: [Poll]] = [:]
    var resultsToReturn: [PollResult] = []
    var voteResultByEntity: [String: PollVoteResult] = [:]
    var unvoteResultByEntity: [String: PollVoteResult] = [:]
    var shouldThrow = false
    private(set) var voteCalls: [String] = []
    private(set) var unvoteCalls: [String] = []

    enum FakeError: Error { case boom }

    func polls(status: String) async throws -> [Poll] {
        if shouldThrow { throw FakeError.boom }
        return pollsByStatus[status] ?? []
    }

    func poll(id: String) async throws -> PollDetail {
        if shouldThrow { throw FakeError.boom }
        guard let d = detailToReturn else { throw FakeError.boom }
        return d
    }

    func pollResults() async throws -> [PollResult] {
        if shouldThrow { throw FakeError.boom }
        return resultsToReturn
    }
    func pollAchievements(entityId: String) async throws -> [PollAchievement] { [] }

    func createPoll(title: String, description: String?, targetType: PollTargetType, days: Int) async throws -> Poll {
        throw FakeError.boom
    }

    func votePoll(pollId: String, entityId: String) async throws -> PollVoteResult {
        if shouldThrow { throw FakeError.boom }
        voteCalls.append(entityId)
        return voteResultByEntity[entityId] ?? PollVoteResult(entityId: entityId, voteCount: 1, myVoteCount: 1)
    }

    func unvotePoll(pollId: String, entityId: String) async throws -> PollVoteResult {
        if shouldThrow { throw FakeError.boom }
        unvoteCalls.append(entityId)
        return unvoteResultByEntity[entityId] ?? PollVoteResult(entityId: entityId, voteCount: 0, myVoteCount: 0)
    }

    func deletePoll(id: String) async throws {
        if shouldThrow { throw FakeError.boom }
    }
}

@MainActor
final class PollDetailViewModelTests: XCTestCase {

    private func makePoll(targetType: PollTargetType = .song) -> Poll {
        Poll(id: "p1", title: "好きな曲", description: nil, targetType: targetType,
             createdBy: "u1", createdAt: Date(), endsAt: Date().addingTimeInterval(86400),
             status: "active", totalVotes: 1, entryCount: 1)
    }

    func testLoadPopulatesDetail() async {
        let fake = FakeCommunityVoting()
        fake.detailToReturn = PollDetail(
            poll: makePoll(),
            entries: [PollEntry(entityId: "s1", voteCount: 1, hasUserVoted: false)],
            myVoteCount: 0)
        let vm = PollDetailViewModel(pollId: "p1", voting: fake)

        await vm.load()

        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.detail?.entries.count, 1)
        XCTAssertEqual(vm.remaining, 3)
    }

    func testVoteAppliesOptimisticUpdate() async {
        let fake = FakeCommunityVoting()
        fake.detailToReturn = PollDetail(
            poll: makePoll(),
            entries: [PollEntry(entityId: "s1", voteCount: 1, hasUserVoted: false)],
            myVoteCount: 0)
        fake.voteResultByEntity["s1"] = PollVoteResult(entityId: "s1", voteCount: 2, myVoteCount: 1)
        let vm = PollDetailViewModel(pollId: "p1", voting: fake)
        await vm.load()

        await vm.vote(entityId: "s1")

        let entry = vm.detail?.entries.first { $0.entityId == "s1" }
        XCTAssertEqual(entry?.voteCount, 2)
        XCTAssertEqual(entry?.hasUserVoted, true)
        XCTAssertEqual(vm.remaining, 2)
        XCTAssertEqual(fake.voteCalls, ["s1"])
        XCTAssertNil(vm.errorMessage)
    }

    func testVoteErrorSetsMessage() async {
        let fake = FakeCommunityVoting()
        fake.detailToReturn = PollDetail(poll: makePoll(), entries: [], myVoteCount: 0)
        let vm = PollDetailViewModel(pollId: "p1", voting: fake)
        await vm.load()

        fake.shouldThrow = true
        await vm.vote(entityId: "s1")

        XCTAssertNotNil(vm.errorMessage)
    }

    func testUnvoteRemovesEntryWhenZero() async {
        let fake = FakeCommunityVoting()
        fake.detailToReturn = PollDetail(
            poll: makePoll(),
            entries: [PollEntry(entityId: "s1", voteCount: 1, hasUserVoted: true)],
            myVoteCount: 1)
        fake.unvoteResultByEntity["s1"] = PollVoteResult(entityId: "s1", voteCount: 0, myVoteCount: 0)
        let vm = PollDetailViewModel(pollId: "p1", voting: fake)
        await vm.load()

        await vm.unvote(entityId: "s1")

        XCTAssertTrue(vm.detail?.entries.isEmpty ?? false)
        XCTAssertEqual(vm.remaining, 3)
        XCTAssertEqual(fake.unvoteCalls, ["s1"])
    }

    func testVoteForEntitiesAppendsAndSortsDescending() async {
        let fake = FakeCommunityVoting()
        fake.detailToReturn = PollDetail(
            poll: makePoll(),
            entries: [PollEntry(entityId: "s1", voteCount: 5, hasUserVoted: false)],
            myVoteCount: 0)
        fake.voteResultByEntity["s2"] = PollVoteResult(entityId: "s2", voteCount: 1, myVoteCount: 1)
        fake.voteResultByEntity["s3"] = PollVoteResult(entityId: "s3", voteCount: 1, myVoteCount: 2)
        let vm = PollDetailViewModel(pollId: "p1", voting: fake)
        await vm.load()

        await vm.voteForEntities(["s2", "s3"])

        XCTAssertEqual(vm.detail?.entries.count, 3)
        // 票数降順なので先頭は 5 票の s1。
        XCTAssertEqual(vm.detail?.entries.first?.entityId, "s1")
        XCTAssertEqual(Set(vm.detail?.entries.map(\.entityId) ?? []), ["s1", "s2", "s3"])
        XCTAssertEqual(vm.remaining, 1) // myVoteCount 2 → 残り1
        XCTAssertEqual(fake.voteCalls, ["s2", "s3"])
    }
}
