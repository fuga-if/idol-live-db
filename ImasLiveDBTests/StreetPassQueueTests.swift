import XCTest
@testable import ImasLiveDB

/// すれちがいの繋ぐ順番 (待ち行列の捨て方・次に繋いでよい時刻)。
final class StreetPassQueueTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    private func makeQueue() -> StreetPassQueue<String> {
        StreetPassQueue(reconnectAfterRead: 3600, reconnectAfterFailure: 180, max: 3, stale: 20)
    }

    func testTuningComesFromCore() {
        let tuning = streetpassTuning()
        let queue = StreetPassQueue<String>(tuning: tuning)
        XCTAssertEqual(queue.max, Int(tuning.queueMax))
        XCTAssertEqual(queue.stale, TimeInterval(tuning.queueStaleSeconds))
        XCTAssertEqual(queue.reconnectAfterRead, TimeInterval(tuning.reconnectAfterReadSeconds))
        XCTAssertEqual(queue.reconnectAfterFailure, TimeInterval(tuning.reconnectAfterFailureSeconds))
    }

    func testSameIdIsQueuedOnceAndRefreshed() {
        var queue = makeQueue()
        queue.offer("a", now: t0)
        queue.offer("b", now: t0)
        queue.offer("a", now: t0.addingTimeInterval(5))
        XCTAssertEqual(queue.waiting.map(\.id), ["b", "a"], "見つけ直したら後ろへ")
        XCTAssertEqual(queue.waiting.last?.foundAt, t0.addingTimeInterval(5))
    }

    func testOverflowDropsOldest() {
        var queue = makeQueue()
        for id in ["a", "b", "c", "d"] { queue.offer(id, now: t0) }
        XCTAssertEqual(queue.waiting.map(\.id), ["b", "c", "d"])
    }

    func testStaleEntriesAreSkipped() {
        var queue = makeQueue()
        queue.offer("old", now: t0)
        queue.offer("new", now: t0.addingTimeInterval(15))
        XCTAssertEqual(queue.next(now: t0.addingTimeInterval(25)), "new", "20 秒より前に見つけた相手は捨てる")
        XCTAssertNil(queue.next(now: t0.addingTimeInterval(25)))
    }

    func testReconnectWaitsDependOnOutcome() {
        var queue = makeQueue()
        queue.markRead("read", now: t0)
        queue.markFailed("failed", now: t0)
        XCTAssertFalse(queue.offer("read", now: t0.addingTimeInterval(600)))
        XCTAssertFalse(queue.offer("failed", now: t0.addingTimeInterval(100)))
        XCTAssertTrue(queue.offer("failed", now: t0.addingTimeInterval(180)))
        XCTAssertTrue(queue.offer("read", now: t0.addingTimeInterval(3600)))
        queue.prune(now: t0.addingTimeInterval(3600))
        XCTAssertTrue(queue.canConnect("read", now: t0.addingTimeInterval(3600)))
    }
}
