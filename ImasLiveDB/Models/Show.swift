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

    /// 配信実施の有無。nil=未設定→event 側にフォールバック。
    var hasStreaming: Bool? = nil
    /// ライブビューイング実施の有無。nil=未設定→event 側にフォールバック。
    var hasLiveViewing: Bool? = nil

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
        case hasStreaming = "has_streaming"
        case hasLiveViewing = "has_live_viewing"
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
