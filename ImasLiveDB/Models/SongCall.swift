import Foundation
import GRDB

struct SongCall: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var songId: String
    var callText: String
    var sourceUrl: String?
    var createdAt: String
    var authorDisplayName: String?

    static let databaseTableName = "song_calls"

    // GRDB の Codable 永続化/デコードはこの CodingKeys でカラム名を決める。
    // 無いと property 名 (camelCase) のまま INSERT されて
    // "table song_calls has no column named songId" になる。
    enum CodingKeys: String, CodingKey {
        case id
        case songId = "song_id"
        case callText = "call_text"
        case sourceUrl = "source_url"
        case createdAt = "created_at"
        case authorDisplayName = "author_display_name"
    }

    enum Columns: String, ColumnExpression {
        case id, songId = "song_id", callText = "call_text",
             sourceUrl = "source_url", createdAt = "created_at",
             authorDisplayName = "author_display_name"
    }
}
