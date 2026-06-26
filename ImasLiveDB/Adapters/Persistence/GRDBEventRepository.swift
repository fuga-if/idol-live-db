import Foundation

/// `EventReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は神オブジェクト `AppDatabase` の既存メソッドへ委譲する。
/// ポート境界が入ったことで、消費者 (ViewModel/View) は `AppDatabase` 具象から切り離され、
/// 後で実クエリをこのアダプタ内の GRDB 非同期 read へ移しても消費者は無改修で済む。
///
/// `nonisolated` な async メソッドなので、MainActor から `await` で呼ぶと協調スレッドプール上で
/// 実行され、同期的な DB read がメインスレッドを塞がない (従来は同期 on-main だった)。
struct GRDBEventRepository: EventReading {
    let database: AppDatabase

    func events(brandId: String?) async throws -> [Event] {
        try database.fetchEvents(brandId: brandId)
    }

    func event(id: String) async throws -> Event? {
        try database.fetchEvent(id: id)
    }

    func eventsWithFirstDate(brandId: String?, includeEmpty: Bool, liveOnly: Bool, kinds: [EventKind]?) async throws -> [EventWithDate] {
        try database.fetchEventsWithFirstDate(brandId: brandId, includeEmpty: includeEmpty, liveOnly: liveOnly, kinds: kinds)
    }

    func searchEventsByNameOrVenue(query: String, limit: Int) async throws -> [Event] {
        try database.searchEventsByNameOrVenue(query: query, limit: limit)
    }

    func eventStats(eventId: String) async throws -> EventStats {
        try database.fetchEventStats(eventId: eventId)
    }

    func eventAttendance(eventId: String) async throws -> EventAttendance? {
        try database.fetchEventAttendance(eventId: eventId)
    }

    func eventsWithDate(criterion: EventFilterCriterion, includeEmpty: Bool) async throws -> [EventWithDate] {
        try database.fetchEventsWithDate(criterion: criterion, includeEmpty: includeEmpty)
    }

    func eventNames() async throws -> [String] {
        try database.fetchEventNames()
    }

    func attendedEventsWithDate() async throws -> [EventWithDate] {
        try database.fetchAttendedEventsWithDate()
    }
}
