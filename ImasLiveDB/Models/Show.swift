import Foundation
import GRDB

struct Show: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "shows"

    var id: String
    var eventId: String
    var name: String
    var date: String
    var venue: String?
    var venueCity: String?
    var startTime: String?
    var sortOrder: Int
    var performerType: String?

    /// キャラライブかどうか
    var isCharacterLive: Bool { performerType == "character" }

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case name, date, venue
        case venueCity = "venue_city"
        case startTime = "start_time"
        case sortOrder = "sort_order"
        case performerType = "performer_type"
    }

    // MARK: - Associations

    static let event = belongsTo(Event.self)
    static let setlistItems = hasMany(SetlistItem.self)
    static let showCasts = hasMany(ShowCast.self)
    static let idols = hasMany(Idol.self, through: showCasts, using: ShowCast.idol)

    var event: QueryInterfaceRequest<Event> { request(for: Show.event) }
    var setlistItems: QueryInterfaceRequest<SetlistItem> { request(for: Show.setlistItems) }
    var idols: QueryInterfaceRequest<Idol> { request(for: Show.idols) }
}
