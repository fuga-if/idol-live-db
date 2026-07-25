import Foundation
import GRDB

struct Show: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "shows"

    var id: String
    var eventId: String
    var name: String
    var date: String
    /// 会場の生文字列 (当時名)。`venueId` が未解決の公演でも表示が壊れないよう残すフォールバック。
    var venue: String?
    /// 会場 ID。名前が変わっても履歴が分断されないよう、同一性はこちらで持つ。
    /// 配信のみの公演は nil。
    var venueId: String?
    /// ホール/構成名 (メインアリーナ / 幕張イベントホール / スタジアムモード 等)。
    /// `venue_halls.name` と突き合わせてキャパを引く。
    var hall: String?
    /// 配信プラットフォーム (ASOBI STAGE 等)。配信は会場ではないのでここへ逃がす。
    var streamPlatform: String?
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
        case name, date, venue, hall
        case venueId = "venue_id"
        case streamPlatform = "stream_platform"
        case venueCity = "venue_city"
        case startTime = "start_time"
        case sortOrder = "sort_order"
        case performerType = "performer_type"
        case hasStreaming = "has_streaming"
        case hasLiveViewing = "has_live_viewing"
    }

    // MARK: - Associations

    static let event = belongsTo(Event.self)
    static let venue_ = belongsTo(Venue.self)
    static let setlistItems = hasMany(SetlistItem.self)
    static let showCasts = hasMany(ShowCast.self)
    static let idols = hasMany(Idol.self, through: showCasts, using: ShowCast.idol)

    var event: QueryInterfaceRequest<Event> { request(for: Show.event) }
    var setlistItems: QueryInterfaceRequest<SetlistItem> { request(for: Show.setlistItems) }
    var idols: QueryInterfaceRequest<Idol> { request(for: Show.idols) }
}
