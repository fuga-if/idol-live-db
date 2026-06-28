import Foundation

/// イベント (ライブ/公演) のマスタ読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// マスタ読みなので read 専用。実装は `Adapters/Persistence/GRDBEventRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol EventReading: Sendable {
    /// ブランド絞り込み (nil で全件) のイベント一覧。
    func events(brandId: String?) async throws -> [Event]
    /// 単一イベント。
    func event(id: String) async throws -> Event?
    /// 最初の公演日付つきイベント一覧 (一覧表示・グルーピング用)。
    func eventsWithFirstDate(brandId: String?, includeEmpty: Bool, liveOnly: Bool, kinds: [EventKind]?) async throws -> [EventWithDate]
    /// ライブ名 / 会場での検索。
    func searchEventsByNameOrVenue(query: String, limit: Int) async throws -> [Event]

    // MARK: - イベント詳細

    /// 公演数・曲数・キャスト数などの集計。
    func eventStats(eventId: String) async throws -> EventStats
    /// 参加状況 (現地/配信などの集計)。
    func eventAttendance(eventId: String) async throws -> EventAttendance?
    /// フィルタ条件で絞った、日付つきイベント。
    func eventsWithDate(criterion: EventFilterCriterion, includeEmpty: Bool) async throws -> [EventWithDate]
    /// イベント名の一覧 (フィルタ補完用)。
    func eventNames() async throws -> [String]
    /// 参加マーク済みイベント (日付つき)。
    func attendedEventsWithDate() async throws -> [EventWithDate]
    /// 参加イベントを現地/配信/LVの3集合に分類 (混在は複数に含む)。
    func attendedEventTypeSets() async throws -> (live: Set<String>, stream: Set<String>, liveViewing: Set<String>)
}
