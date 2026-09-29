//  AppDatabase の Idol Queries / Idol Song Queries を切り出したもの。
//  分割の意図と分割線の引き方は docs/ARCHITECTURE.md を参照。
//  ここにあるのは移動してきたクエリだけで、ロジックは 1 行も変えていない。

import Foundation
import GRDB

extension AppDatabase {

    // MARK: - Idol Queries

    /// アイドル一覧 (外部ゲスト演者は除外)
    func fetchIdols(brandId: String? = nil) throws -> [Idol] {
        try dbQueue.read { db in try Self.fetchIdolsByBrandQuery(db, brandId: brandId) }
    }

    private static func fetchIdolsByBrandQuery(_ db: Database, brandId: String?) throws -> [Idol] {
        if let brandId {
            let sql = """
                SELECT DISTINCT i.* FROM idols i
                JOIN idol_brands ib ON i.id = ib.idol_id
                WHERE ib.brand_id = ? AND i.is_external = 0
                ORDER BY i.sort_order
                """
            return try Idol.fetchAll(db, sql: sql, arguments: [brandId])
        }
        return try Idol
            .filter(Column("is_external") == 0)
            .order(Column("sort_order"))
            .fetchAll(db)
    }

    /// 編集フィード用: 参考動画 (`ytref_xxx`) の曲名。動画はスナップショットに無いので SQL で引く
    /// (ほかの種類の呼び名はコアの `edit_record_target`)。
    func fetchSongVideoSongTitleAsync(videoId: String) async throws -> String? {
        try await dbQueue.read { db in
            try String.fetchOne(db, sql: """
                SELECT s.title FROM song_videos sv
                JOIN songs s ON s.id = sv.song_id WHERE sv.id = ?
                """, arguments: [videoId])
        }
    }

    /// 編集レコードが属する曲 ID を解決する (SongVideo 編集 → 該当曲詳細へ遷移するため)。
    func fetchEditRecordSongIdAsync(recordType: String, recordName: String) async throws -> String? {
        try await dbQueue.read { db in try Self.fetchEditRecordSongIdQuery(db, recordType: recordType, recordName: recordName) }
    }

    private static func fetchEditRecordSongIdQuery(_ db: Database, recordType: String, recordName: String) throws -> String? {
        func one(_ sql: String) -> String? {
            (try? String.fetchOne(db, sql: sql, arguments: [recordName])) ?? nil
        }
        switch recordType {
        case "SongVideo":
            return one("SELECT song_id FROM song_videos WHERE id = ?")
        default:
            return nil
        }
    }
}
