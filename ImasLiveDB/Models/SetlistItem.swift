import Foundation
import GRDB

struct SetlistItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "setlist_items"

    var id: String
    var showId: String
    var songId: String
    var position: Int
    var section: String?
    var notes: String?
    /// 披露時のユニット表記。テーブル (setlist_items.unit_name) / CloudKit (unitName) に存在するが
    /// モデルに無かったため、sync・replaceSetlist の INSERT OR REPLACE で NULL に消えていた。
    var unitName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case showId = "show_id"
        case songId = "song_id"
        case position, section, notes
        case unitName = "unit_name"
    }

    // MARK: - Associations

    static let show = belongsTo(Show.self)
    static let song = belongsTo(Song.self)
    static let setlistPerformers = hasMany(SetlistPerformer.self)
    static let performers = hasMany(Idol.self, through: setlistPerformers, using: SetlistPerformer.idol)

    var show: QueryInterfaceRequest<Show> { request(for: SetlistItem.show) }
    var song: QueryInterfaceRequest<Song> { request(for: SetlistItem.song) }
    var performers: QueryInterfaceRequest<Idol> { request(for: SetlistItem.performers) }
}
