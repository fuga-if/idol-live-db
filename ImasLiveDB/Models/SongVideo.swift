import Foundation
import GRDB

struct SongVideo: Identifiable, Codable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var songId: String
    var youtubeUrl: String
    var videoTitle: String?
    var note: String?
    var createdAt: String
    var authorDisplayName: String?

    static let databaseTableName = "song_videos"

    // GRDB の Codable 永続化/デコードはこの CodingKeys でカラム名を決める。
    // 無いと property 名 (camelCase) のまま INSERT されて列不一致エラーになる。
    enum CodingKeys: String, CodingKey {
        case id
        case songId = "song_id"
        case youtubeUrl = "youtube_url"
        case videoTitle = "video_title"
        case note
        case createdAt = "created_at"
        case authorDisplayName = "author_display_name"
    }

    enum Columns: String, ColumnExpression {
        case id, songId = "song_id", youtubeUrl = "youtube_url",
             videoTitle = "video_title", note,
             createdAt = "created_at", authorDisplayName = "author_display_name"
    }
}
