import GRDB
import XCTest
@testable import ImasLiveDB

/// 端末にしか無いデータ (参加・マーク・マイタグ・家計簿) の書き込みのテスト。
///
/// どれもクラウドにもサーバにも無く、壊れたら戻す手段が無い。
/// 復元 (`restore…IfAbsent`) は「無い行を足すだけ」で、既にある行を上書きも削除もしないこと。
final class LocalDataWriteTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(dbQueue: makeMigratedDatabase())
    }

    private func mark(_ id: String, _ kind: UserMarkKind, flag: Bool = true, text: String? = nil) -> UserMark {
        UserMark(entityType: "show", entityId: id, kind: kind.rawValue,
                 boolValue: flag, textValue: text, updatedAt: "2026-09-01T00:00:00Z")
    }

    // MARK: - 参加

    /// 参加の有無と種別は 1 行にまとめて書かれ、付け直し・取り消しで食い違わない。
    func testAttendanceMarkKeepsFlagAndTypeTogether() throws {
        let db = try makeDatabase()

        try db.setAttendanceMark(entity: .show, id: "sh1", type: .stream)
        var row = try XCTUnwrap(db.fetchUserMark(entity: .show, id: "sh1", kind: .attended))
        XCTAssertTrue(row.boolValue)
        XCTAssertEqual(row.textValue, "stream")

        try db.setAttendanceMark(entity: .show, id: "sh1", type: .live)
        row = try XCTUnwrap(db.fetchUserMark(entity: .show, id: "sh1", kind: .attended))
        XCTAssertTrue(row.boolValue)
        XCTAssertEqual(row.textValue, "live")

        try db.setAttendanceMark(entity: .show, id: "sh1", type: nil)
        row = try XCTUnwrap(db.fetchUserMark(entity: .show, id: "sh1", kind: .attended))
        XCTAssertFalse(row.boolValue)
        XCTAssertNil(row.textValue, "取り消したのに種別が残っている")
    }

    // MARK: - 復元 (非破壊)

    func testRestoreUserMarksAddsOnlyMissingRows() throws {
        let db = try makeDatabase()
        try db.setAttendanceMark(entity: .show, id: "sh1", type: .live)

        let added = try db.restoreUserMarksIfAbsent([
            mark("sh1", .attended, text: "stream"),  // 既にある: 上書きしない
            mark("sh2", .attended, text: "stream"),  // 無い: 足す
        ])

        XCTAssertEqual(added, 1)
        XCTAssertEqual(try db.fetchUserMark(entity: .show, id: "sh1", kind: .attended)?.textValue, "live")
        XCTAssertEqual(try db.fetchUserMark(entity: .show, id: "sh2", kind: .attended)?.textValue, "stream")
    }

    func testRestorePersonalTagsAddsOnlyMissingRows() throws {
        let db = try makeDatabase()
        try db.addPersonalTag(entityType: "song", entityId: "s1", tagName: "聞いた")
        let existing = try XCTUnwrap(db.allPersonalTags().first)

        let added = try db.restorePersonalTagsIfAbsent([
            PersonalTag(entityType: "song", entityId: "s1", tagName: "聞いた", createdAt: "2000-01-01T00:00:00Z"),
            PersonalTag(entityType: "song", entityId: "s1", tagName: "好き", createdAt: "2000-01-01T00:00:00Z"),
        ])

        XCTAssertEqual(added, 1)
        let tags = try db.allPersonalTags()
        XCTAssertEqual(Set(tags.map(\.tagName)), ["聞いた", "好き"])
        XCTAssertEqual(tags.first { $0.tagName == "聞いた" }?.createdAt, existing.createdAt, "既にある行を上書きした")
    }

    /// 家計簿は id で重複を見る。同じ支出を 2 回足すと帳簿の額が倍になる。
    func testRestoreExpensesAddsOnlyMissingIds() throws {
        let db = try makeDatabase()
        try db.saveExpense(expense("e1", amount: 1_000))

        let added = try db.restoreExpensesIfAbsent([
            expense("e1", amount: 9_999),
            expense("e2", amount: 2_000),
        ])

        XCTAssertEqual(added, 1)
        let amounts = Dictionary(uniqueKeysWithValues: try db.allExpenses().map { ($0.id, $0.amount) })
        XCTAssertEqual(amounts, ["e1": 1_000, "e2": 2_000])
    }

    // MARK: - 家計簿の保存・削除

    func testExpenseSaveUpdatesInPlaceAndDeleteRemoves() throws {
        let db = try makeDatabase()
        try db.saveExpense(expense("e1", amount: 1_000))
        try db.saveExpense(expense("e1", amount: 1_500))  // 同じ id は上書き (行は増えない)
        try db.saveExpense(expense("e2", amount: 2_000))

        XCTAssertEqual(try db.allExpenses().map(\.amount).sorted(), [1_500, 2_000])

        try db.deleteExpense(id: "e1")
        XCTAssertEqual(try db.allExpenses().map(\.id), ["e2"])
    }

    private func expense(_ id: String, amount: Int64) -> Expense {
        Expense(id: id, date: "2026-09-01", category: "ticket", amount: amount,
                showId: nil, eventId: nil, note: nil, updatedAt: "2026-09-01T00:00:00Z")
    }
}
