import Foundation
import GRDB

struct SongArtist: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "song_artists"

    var songId: String
    var idolId: String
    var role: String

    enum CodingKeys: String, CodingKey {
        case songId = "song_id"
        case idolId = "idol_id"
        case role
    }

    // MARK: - Associations

    static let song = belongsTo(Song.self)
    static let idol = belongsTo(Idol.self)
}
