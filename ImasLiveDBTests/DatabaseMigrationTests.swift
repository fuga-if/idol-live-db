import GRDB
import XCTest
@testable import ImasLiveDB

/// 起動時の DB 移行 (`DatabaseMigrations` → コアの `ensureMasterSchema`) のテスト。
///
/// 移行が落ちるとアプリは起動できず、利用者には直す手段が無い (実際に審査 reject になった)。
/// 移行が消した行も戻らない。担当・お気に入り・マイタグ・家計簿はクラウドにもサーバにも無い。
/// どちらも CI で捕まえないと、利用者の手元で初めて分かる。
final class DatabaseMigrationTests: XCTestCase {

    /// 端末ローカルにしかない表。移行で 1 行も欠けてはいけない。
    private static let localOnlyTables = ["user_marks", "personal_tags", "expenses"]

    /// 空の DB に全移行を当て、コアのマスタスキーマまで通ること
    /// (同梱 DB が無いときの新規インストールの経路)。
    func testEmptyDatabaseMigratesToLatestAndAcceptsCoreSchema() throws {
        let path = temporaryDatabasePath()
        let queue = try DatabaseQueue(path: path)
        try DatabaseMigrations.migrator.migrate(queue)
        XCTAssertTrue(try queue.read { db in try DatabaseMigrations.migrator.hasCompletedMigrations(db) })

        let result = try ensureMasterSchema(dbPath: path)
        XCTAssertEqual(result.deferred, [], "移行の後に、人の移行を待つ差分が残っている")

        let tables = try queue.read { db in
            Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'"))
        }
        // 端末ローカルの表 (移行が作る) と、コアだけが作る表 (song_units) の両方が揃う。
        for table in Self.localOnlyTables + ["songs", "song_units"] {
            XCTAssertTrue(tables.contains(table), "\(table) が無い")
        }
    }

    /// 実機の経路: 同梱 DB を置いたところから、seedMigrationHistoryIfNeeded → 移行 →
    /// コアのスキーマ → reseed の判定まで通り、外部キーを破る行が残らないこと。
    /// 2 回目の起動 (置いた DB を開き直す) も同じく通ること。
    func testBundledDatabasePreparesToLatest() throws {
        guard let bundle = Bundle.main.url(forResource: "master", withExtension: "sqlite") else {
            throw XCTSkip("同梱 master.sqlite が無いビルド")
        }
        let url = URL(fileURLWithPath: temporaryDatabasePath())

        for launch in 1...2 {
            let pool = try AppDatabase.openDatabase(at: url, bundleURL: bundle)
            try pool.read { db in
                XCTAssertTrue(try DatabaseMigrations.migrator.hasCompletedMigrations(db), "起動 \(launch)")
                let tables = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'"))
                for table in Self.localOnlyTables {
                    XCTAssertTrue(tables.contains(table), "起動 \(launch): \(table) が無い")
                }
                XCTAssertEqual(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").count, 0, "起動 \(launch)")
            }
        }
    }

    /// 移行は Debug でも、各移行の後に外部キーを検査する (Release と同じ)。
    /// Debug だけ検査を外していたので、Release でだけ起動時に落ちる種類の失敗を
    /// CI (Debug で走る) が捕まえられなかった。
    func testMigrationChecksForeignKeysInDebugToo() throws {
        let queue = try DatabaseQueue(path: temporaryDatabasePath())
        try DatabaseMigrations.migrator.migrate(queue, upTo: "v32_expenses")
        // 外部キーを破る行 (存在しない公演での衣装の着用)。
        try queue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF")
            try db.execute(sql: "INSERT INTO costumes (id, name) VALUES ('c1', 'c1')")
            try db.execute(sql: "INSERT INTO costume_wears (id, costume_id, show_id) VALUES ('w1', 'c1', 'missing')")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        XCTAssertThrowsError(try DatabaseMigrations.migrator.migrate(queue))
    }

    func testLocalOnlyRowsSurviveMigrationFromV18() throws {
        try assertLocalOnlyRowsSurviveMigration(from: "v18_event_joint_brands")
    }

    func testLocalOnlyRowsSurviveMigrationFromV22() throws {
        try assertLocalOnlyRowsSurviveMigration(from: "v22_event_ticket_open_date")
    }

    /// マイタグ (v26) と家計簿 (v32) の表がある版からでも、3 表とも残ること。
    func testLocalOnlyRowsSurviveMigrationFromV32() throws {
        try assertLocalOnlyRowsSurviveMigration(from: "v32_expenses")
    }

    /// `version` まで上げた DB に、その版にある端末ローカルの表の行を入れ、
    /// 最新まで上げてコアのスキーマも当てた後に、行が 1 つも変わっていないことを確かめる。
    private func assertLocalOnlyRowsSurviveMigration(
        from version: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let path = temporaryDatabasePath()
        let queue = try DatabaseQueue(path: path)
        try DatabaseMigrations.migrator.migrate(queue, upTo: version)

        let tables = try queue.read { db in try Self.localOnlyTables.filter { try db.tableExists($0) } }
        let before = try queue.write { db -> [String: [Row]] in
            try Self.insertLocalOnlyRows(db)
            return try Self.rows(of: tables, in: db)
        }
        XCTAssertFalse(before.values.joined().isEmpty, "入れた行が無い", file: file, line: line)

        try DatabaseMigrations.migrator.migrate(queue)
        _ = try ensureMasterSchema(dbPath: path)

        let after = try queue.read { db in try Self.rows(of: tables, in: db) }
        XCTAssertEqual(after, before, "移行で端末ローカルの行が変わった", file: file, line: line)
    }

    /// その版にある端末ローカルの表にだけ、代表的な行を入れる。
    private static func insertLocalOnlyRows(_ db: Database) throws {
        let now = "2026-09-23T00:00:00Z"
        if try db.tableExists("user_marks") {
            for (type, id, kind, flag, text) in [
                ("idol", "ml_x", "pick", 1, nil),
                ("idol", "ml_y", "favorite", 1, nil),
                ("show", "sh_1", "attended", 1, nil),
                ("show", "sh_1", "seat", 0, "アリーナ A1"),
                ("song", "s_1", "memo", 0, "メモ"),
            ] as [(String, String, String, Int, String?)] {
                try db.execute(
                    sql: """
                        INSERT INTO user_marks (entity_type, entity_id, kind, bool_value, text_value, updated_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [type, id, kind, flag, text, now])
            }
        }
        if try db.tableExists("personal_tags") {
            try db.execute(
                sql: "INSERT INTO personal_tags (entity_type, entity_id, tag_name, created_at) VALUES (?, ?, ?, ?)",
                arguments: ["song", "s_1", "聞いた", now])
        }
        if try db.tableExists("expenses") {
            try db.execute(
                sql: """
                    INSERT INTO expenses (id, date, category, amount, show_id, event_id, note, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: ["exp_1", "2026-09-01", "ticket", 13_200, "sh_1", "ev_1", "S席", now])
        }
    }

    private static func rows(of tables: [String], in db: Database) throws -> [String: [Row]] {
        var rows: [String: [Row]] = [:]
        for table in tables {
            rows[table] = try Row.fetchAll(db, sql: "SELECT * FROM \(table) ORDER BY 1, 2, 3")
        }
        return rows
    }
}
