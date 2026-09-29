//  AppDatabase の Event Queries / Setlist Queries / Filtered Fetch Methods / Private Helpers を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Event Queries

    /// 公演をイベント名・公演名で検索（コミュニティ投稿用）
    func searchShows(query: String, limit: Int = 30) throws -> [ShowWithEventName] {
        try dbQueue.read { db in try Self.searchShowsQuery(db, query: query, limit: limit) }
    }

    private static func searchShowsQuery(_ db: Database, query: String, limit: Int) throws -> [ShowWithEventName] {
        let pattern = "%\(query.likeEscaped)%"
        let sql = """
            SELECT s.id, s.event_id, s.name, s.date, s.venue, e.name AS event_name
            FROM shows s
            JOIN events e ON s.event_id = e.id
            WHERE s.name LIKE ? ESCAPE '\\' OR e.name LIKE ? ESCAPE '\\'
            ORDER BY s.date DESC
            LIMIT ?
            """
        return try ShowWithEventName.fetchAll(db, sql: sql, arguments: [pattern, pattern, limit])
    }

    /// 参加したライブ(イベント)を重複なしで返す。
    /// 「イベント単位の参加マーク」と「公演(show)単位の参加マーク→所属イベント」を UNION で統合する。
    /// (参加を公演単位で付けるユーザーが多く、event マークだけ見るとリストが取りこぼすため)
    func fetchAttendedEventsWithDate() throws -> [EventWithDate] {
        try dbQueue.read { db in try Self.fetchAttendedEventsWithDateQuery(db) }
    }

    private static func fetchAttendedEventsWithDateQuery(_ db: Database) throws -> [EventWithDate] {
        let sql = """
            SELECT e.id, e.brand_id, e.name, e.event_type, e.is_streaming, e.is_solo, e.kind,
                   MIN(s.date) AS first_date,
                   MAX(s.date) AS last_date
            FROM events e
            LEFT JOIN shows s ON s.event_id = e.id
            WHERE e.id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
                UNION
                SELECT sh.event_id FROM user_marks um
                JOIN shows sh ON sh.id = um.entity_id
                WHERE um.entity_type = 'show' AND um.kind = 'attended' AND um.bool_value = 1
            )
            GROUP BY e.id
            ORDER BY COALESCE(MIN(s.date), '') DESC
            """
        return try Row.fetchAll(db, sql: sql).map(Self.eventWithDate)
    }

    // MARK: - Private Helpers

    private static func eventWithDate(_ row: Row) -> EventWithDate {
        EventWithDate(
            event: Event(
                id: row["id"],
                brandId: row["brand_id"],
                name: row["name"],
                eventType: row["event_type"],
                isStreaming: row["is_streaming"] ?? false,
                isSolo: row["is_solo"] ?? true,
                kind: row["kind"] ?? "live"
            ),
            firstDate: row["first_date"],
            lastDate: row["last_date"]
        )
    }
}
