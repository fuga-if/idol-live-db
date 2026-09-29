import GRDB
import os
import XCTest
@testable import ImasLiveDB

/// 起動時に DB を開く流れ (`DatabaseBoot`) のテスト。
///
/// 開けなかったときに落ちずに復旧画面へ進み、「もう一度試す」で開き直せること。
/// 開けた後は開き直さないこと (画面の出し直しで `.task` がもう一度走っても、DB は 1 つ)。
@MainActor
final class DatabaseBootTests: XCTestCase {

    func testFailureLeadsToRecoveryAndRetryOpens() async throws {
        let database = try AppDatabase(dbQueue: DatabaseQueue())
        let attempts = OSAllocatedUnfairLock(initialState: 0)
        let boot = DatabaseBoot {
            let attempt = attempts.withLock { count in
                count += 1
                return count
            }
            if attempt == 1 { throw CocoaError(.fileReadCorruptFile) }
            return database
        }

        await boot.prepare()
        guard case .failed(let detail) = boot.state else {
            return XCTFail("開けなかったのに復旧画面に進まない: \(boot.state)")
        }
        XCTAssertFalse(detail.isEmpty)

        await boot.prepare()
        guard case .ready(let opened) = boot.state else {
            return XCTFail("もう一度試しても開かない: \(boot.state)")
        }
        XCTAssertTrue(opened === database)

        await boot.prepare()
        XCTAssertEqual(attempts.withLock { $0 }, 2, "開けた後に開き直した")
    }
}
