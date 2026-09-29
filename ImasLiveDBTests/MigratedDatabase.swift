import Foundation
import GRDB
import XCTest
@testable import ImasLiveDB

extension XCTestCase {
    /// 起動時と同じ手順 (GRDB の移行 → コアのマスタスキーマ) で作った一時ファイルの DB。
    /// テストが終わったらファイルごと消える。
    ///
    /// スキーマをテストに手で書くと本物とずれる (songs は 28 列あるのに 20 列しか
    /// 書いていなかった)。本物の手順で作れば、列や表が増えても勝手に追従する。
    func makeMigratedDatabase() throws -> DatabaseQueue {
        try DatabaseQueue(path: makeMigratedDatabaseFile())
    }

    /// `makeMigratedDatabase()` と同じ DB を作り、ファイルのパスを返す
    /// (コアのようにパスで DB を開く相手に渡すとき用)。
    func makeMigratedDatabaseFile() throws -> String {
        let path = temporaryDatabasePath()
        do {
            let queue = try DatabaseQueue(path: path)
            try DatabaseMigrations.migrator.migrate(queue)
        }
        // コアは自分の接続でファイルを開くので、上の接続を閉じてから当てる (起動時も移行の後)。
        _ = try ensureMasterSchema(dbPath: path)
        return path
    }

    /// テストの終わりに消える一時ファイルのパス。
    func temporaryDatabasePath() -> String {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_\(UUID().uuidString).sqlite").path
        addTeardownBlock {
            for suffix in ["", "-wal", "-shm", "-journal"] {
                try? FileManager.default.removeItem(atPath: path + suffix)
            }
        }
        return path
    }
}
