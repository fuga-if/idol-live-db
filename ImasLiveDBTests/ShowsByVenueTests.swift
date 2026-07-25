import XCTest
import GRDB
@testable import ImasLiveDB

/// 「会場をタップ → その会場での公演一覧」が会場 ID で引けることのテスト。
///
/// 会場を ID 管理 (`shows.venue_id` + `venues`) にしたとき、公演一覧のクエリだけが
/// 旧来の生文字列カラム (`shows.venue`) で突き合わせたまま残っていた。呼び出し側は
/// `venue_id` を渡すので必ず 0 件になり、「公演が見つかりません」しか出なかった。
///
/// 会場は改称するうえ表記ゆれもある (「東京・京王アリーナTOKYO」「京王アリーナ TOKYO」
/// 「武蔵野の森総合スポーツプラザ」) ので、**表記ではなく ID で束ねられること**が要点。
final class ShowsByVenueTests: XCTestCase {

    /// - `sh_new` / `sh_old` : 同じ会場 (`venue_keio`) だが `venue` 文字列は表記ゆれ + 改称前後
    /// - `sh_other`          : 別会場
    /// - `sh_legacy`         : venue_id を持たない旧データ (生文字列でしか辿れない)
    private func makeDatabase() throws -> AppDatabase {
        let queue = try DatabaseQueue()
        try queue.write { db in
            try db.execute(sql: """
                CREATE TABLE shows(
                    id TEXT PRIMARY KEY, event_id TEXT NOT NULL, name TEXT NOT NULL,
                    date TEXT NOT NULL, venue TEXT, venue_city TEXT, start_time TEXT,
                    sort_order INTEGER NOT NULL DEFAULT 0, performer_type TEXT,
                    venue_id TEXT, hall TEXT, stream_platform TEXT
                )
                """)
            let rows = [
                ("sh_new", "京王アリーナ TOKYO", "2026-07-25", "venue_keio"),
                ("sh_old", "東京・京王アリーナTOKYO", "2026-02-28", "venue_keio"),
                ("sh_renamed", "武蔵野の森総合スポーツプラザ", "2024-05-01", "venue_keio"),
                ("sh_other", "日本武道館", "2026-03-01", "venue_budokan"),
            ]
            for (id, venue, date, venueId) in rows {
                try db.execute(
                    sql: "INSERT INTO shows(id, event_id, name, date, venue, venue_id) VALUES(?,?,?,?,?,?)",
                    arguments: [id, "ev1", id, date, venue, venueId]
                )
            }
            // venue_id 未設定の旧データ
            try db.execute(
                sql: "INSERT INTO shows(id, event_id, name, date, venue) VALUES(?,?,?,?,?)",
                arguments: ["sh_legacy", "ev1", "sh_legacy", "2019-01-01", "どこかのホール"]
            )
        }
        return try AppDatabase(dbQueue: queue)
    }

    func testVenueIdCollectsShowsAcrossRenamesAndSpellingVariants() async throws {
        let db = try makeDatabase()
        let shows = try await db.fetchShowsAsync(criterion: .venue("venue_keio"))
        XCTAssertEqual(Set(shows.map(\.id)), ["sh_new", "sh_old", "sh_renamed"],
                       "表記ゆれ・改称をまたいで venue_id で束ねられること")
    }

    func testResultsAreNewestFirst() async throws {
        let db = try makeDatabase()
        let shows = try await db.fetchShowsAsync(criterion: .venue("venue_keio"))
        XCTAssertEqual(shows.map(\.date), ["2026-07-25", "2026-02-28", "2024-05-01"])
    }

    func testOtherVenueIsNotIncluded() async throws {
        let db = try makeDatabase()
        let shows = try await db.fetchShowsAsync(criterion: .venue("venue_keio"))
        XCTAssertFalse(shows.contains { $0.id == "sh_other" })
    }

    /// venue_id を持たない旧データは生文字列でしか辿れないので、後方互換で引けること。
    func testLegacyShowWithoutVenueIdStillMatchesByRawString() async throws {
        let db = try makeDatabase()
        let shows = try await db.fetchShowsAsync(criterion: .venue("どこかのホール"))
        XCTAssertEqual(shows.map(\.id), ["sh_legacy"])
    }

    func testUnknownVenueYieldsEmpty() async throws {
        let db = try makeDatabase()
        let shows = try await db.fetchShowsAsync(criterion: .venue("venue_unknown"))
        XCTAssertTrue(shows.isEmpty)
    }
}
