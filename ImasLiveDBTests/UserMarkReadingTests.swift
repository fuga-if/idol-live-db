import GRDB
import XCTest
@testable import ImasLiveDB

/// 付いているマークの読み出しのテスト。
///
/// 習熟度・メモ・座席は中身を文字で持ち、フラグ (bool_value) を立てない。
/// 読み出しがフラグで絞っていたため、習熟度は再起動のたびに全部 0 に見え、
/// メモのある曲・アイドル・イベントの印と絞り込みは常に空だった (DB に行は残っている)。
final class UserMarkReadingTests: XCTestCase {

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(dbQueue: makeMigratedDatabase())
    }

    /// 習熟度は段階を文字で持つ。再起動時の読み直し (`fetchAllUserMarks`) で落ちないこと。
    func testMasteryLevelsAreReadBack() throws {
        let db = try makeDatabase()
        try db.upsertUserMarkText(entity: .song, id: "s1", kind: .mastery, text: "3")
        try db.upsertUserMarkText(entity: .song, id: "s2", kind: .mastery, text: nil)  // 未設定に戻した

        let rows = try db.fetchAllUserMarks(kind: .mastery)
        XCTAssertEqual(rows.map(\.entityId), ["s1"])
        XCTAssertEqual(rows.first?.textValue, "3")
    }

    /// メモのある対象は、空白以外の文字があるものだけ。
    func testNotedEntitiesAreThoseWithText() throws {
        let db = try makeDatabase()
        try db.upsertUserMarkNote(entity: .song, id: "s1", text: "メモ")
        try db.upsertUserMarkNote(entity: .song, id: "s2", text: " \n ")  // 空白だけ
        try db.upsertUserMarkNote(entity: .song, id: "s3", text: nil)  // 消した

        XCTAssertEqual(try db.fetchMarkedEntityIds(entity: .song, kind: .note), ["s1"])
    }

    /// フラグのマークは、これまでどおりフラグが立っているものだけ。
    func testFlagMarksFollowTheFlag() throws {
        let db = try makeDatabase()
        try db.upsertUserMark(entity: .song, id: "s1", kind: .favorite, boolValue: true)
        try db.upsertUserMark(entity: .song, id: "s2", kind: .favorite, boolValue: false)

        XCTAssertEqual(try db.fetchMarkedEntityIds(entity: .song, kind: .favorite), ["s1"])
        XCTAssertEqual(try db.fetchAllUserMarks(kind: .favorite).map(\.entityId), ["s1"])
    }
}
