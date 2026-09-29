//  AppDatabase の Song Queries / Song Search (for OCR matching) / Album Queries を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Song Queries

    /// 楽曲一括取得（複数ID指定・IN句1回）。N+1防止用。
    func fetchSongs(ids: [String]) throws -> [Song] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in try Self.fetchSongsByIdsQuery(db, ids: ids) }
    }

    private static func fetchSongsByIdsQuery(_ db: Database, ids: [String]) throws -> [Song] {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        return try Song.fetchAll(db, sql: "SELECT * FROM songs WHERE id IN (\(placeholders))",
                                arguments: StatementArguments(ids))
    }

    /// アイドル一括取得（ID配列）— N+1 解消用
    func fetchIdols(ids: [String]) throws -> [Idol] {
        guard !ids.isEmpty else { return [] }
        return try dbQueue.read { db in try Self.fetchIdolsByIdsQuery(db, ids: ids) }
    }

    private static func fetchIdolsByIdsQuery(_ db: Database, ids: [String]) throws -> [Idol] {
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        return try Idol.fetchAll(db, sql: "SELECT * FROM idols WHERE id IN (\(placeholders))",
                                 arguments: StatementArguments(ids))
    }

    /// 公演取得（ID指定）
    func fetchShow(id: String) throws -> Show? {
        try dbQueue.read { db in try Self.fetchShowQuery(db, id: id) }
    }

    private static func fetchShowQuery(_ db: Database, id: String) throws -> Show? {
        try Show.fetchOne(db, key: id)
    }

    /// イベント取得（ID指定）
    func fetchEvent(id: String) throws -> Event? {
        try dbQueue.read { db in try Self.fetchEventQuery(db, id: id) }
    }

    private static func fetchEventQuery(_ db: Database, id: String) throws -> Event? {
        try Event.fetchOne(db, key: id)
    }

    // MARK: - Song Search (for OCR matching)

    /// 楽曲をタイトルで検索（完全一致優先、部分一致も含む）
    func searchSongs(query: String, limit: Int = 10) throws -> [Song] {
        try dbQueue.read { db in try Self.searchSongsQuery(db, query: query, limit: limit) }
    }

    private static func searchSongsQuery(_ db: Database, query: String, limit: Int) throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 完全一致を先に取得
        let exact = try Song
            .filter(Column("title") == trimmed)
            .fetchAll(db)

        if !exact.isEmpty { return exact }

        // 部分一致
        let pattern = "%\(trimmed.likeEscaped)%"
        return try Song
            .filter(Column("title").like(pattern, escape: "\\") || Column("title_kana").like(pattern, escape: "\\"))
            .limit(limit)
            .fetchAll(db)
    }
}
