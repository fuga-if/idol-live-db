import XCTest
@testable import ImasLiveDB

@MainActor
final class PendingCommunityActionsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "PendingCommunityActionsTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    /// (A, true) が送れずに積まれた後で (A, false) が送れたら、積み残しの (A, true) は
    /// 送り直さない。送り直すと、集計が利用者の最後の操作 (false) から true に戻る。
    func testSuccessfulSendDropsTheOlderPendingValueForTheSameSong() async {
        let server = FakeFavoriteServer()
        let queue = PendingCommunityActions(defaults: defaults, send: server.send)

        server.setFailing(true)
        await queue.send(songId: "A", value: true)
        server.setFailing(false)
        await queue.send(songId: "A", value: false)
        await queue.flush()

        XCTAssertEqual(server.received.map(\.value), [false])
        XCTAssertTrue(queue.actions.isEmpty)
        // 積み残しは端末に残る列なので、読み直しても空のまま。
        XCTAssertTrue(PendingCommunityActions(defaults: defaults, send: server.send).actions.isEmpty)
    }
}

/// 送れた内容を記録し、指示されたら失敗する偽のサーバ。
private final class FakeFavoriteServer: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    private var log: [(songId: String, value: Bool)] = []

    var received: [(songId: String, value: Bool)] { lock.withLock { log } }
    func setFailing(_ value: Bool) { lock.withLock { failing = value } }

    var send: PendingCommunityActions.SendFavorite {
        { [self] songId, value in
            try lock.withLock {
                if failing { throw URLError(.notConnectedToInternet) }
                log.append((songId, value))
            }
        }
    }
}
