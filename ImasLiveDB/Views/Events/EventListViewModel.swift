import Foundation
import os

/// EventListView のデータ取得・絞り込み/グルーピング担当。
///
/// 役割分担:
/// - **VM (ここ)**: ポート越しのイベント/ブランド取得 (`eventReading`/`brandReading`) と、
///   純粋 UseCase (`filterEvents` + `groupEventsByYear`) による絞り込み・年グルーピング結果の保持。
/// - **View 側**: `@AppStorage` の設定値・選択状態 (ブランド/除外kind/参加/必須マーク/時系列タブ) を保持し、
///   `EventListQuery` (= 解決済み `EventFilterContext` + 今後/開催済み + 端末today) にまとめて渡す。
///
/// マーク集合の解決は View 文脈 (`UserMarkService` の `@Observable` 観測を壊さないため)。
@MainActor
@Observable
final class EventListViewModel {
    private(set) var eventsWithDate: [EventWithDate] = []
    private(set) var brands: [Brand] = []

    // 絞り込み + 年グルーピング済みの派生結果
    private(set) var filteredCount: Int = 0
    private(set) var groupedByYear: [YearGroup] = []

    private let eventReading: any EventReading
    private let brandReading: any BrandReading

    nonisolated init(
        eventReading: any EventReading = AppContainer.shared.eventReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading
    ) {
        self.eventReading = eventReading
        self.brandReading = brandReading
    }

    func loadData(includeEmpty: Bool, query: EventListQuery) async {
        do {
            // 全 kind を取ってきて、表示時に excludedKinds で client-side filter。
            eventsWithDate = try await eventReading.eventsWithFirstDate(
                brandId: nil,
                includeEmpty: includeEmpty,
                liveOnly: false,
                kinds: EventKind.allCases
            )
            brands = try await brandReading.brands()
            rebuild(query: query)
        } catch {
            Logger.database.error("load_failed events: \(error.localizedDescription)")
        }
    }

    func rebuild(query: EventListQuery) {
        let filtered = filterEvents(eventsWithDate, query.filter)
        let groups = groupEventsByYear(filtered, upcoming: query.upcoming, todayKey: query.todayKey)
        filteredCount = groups.reduce(0) { $0 + $1.events.count }
        groupedByYear = groups
    }
}

/// EventListView の現在の絞り込み・時系列状態をまとめた問い合わせ条件。
struct EventListQuery {
    /// マーク集合まで解決済みの絞り込み条件。
    var filter: EventFilterContext
    /// true = 今後の予定 / false = 開催済み。
    var upcoming: Bool
    /// 端末ローカルの今日 (YYYY-MM-DD)。今後/開催済みの境界。
    var todayKey: String
}
