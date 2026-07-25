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
    /// 初回ロード中 (スケルトン表示用)。初回完了で false。
    private(set) var isLoading = true

    // 絞り込み + 年グルーピング済みの派生結果
    private(set) var filteredCount: Int = 0
    private(set) var groupedByYear: [YearGroup] = []

    private let eventReading: any EventReading
    private let brandReading: any BrandReading
    private let showReading: any ShowReading

    nonisolated init(
        eventReading: any EventReading = AppContainer.shared.eventReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading,
        showReading: any ShowReading = AppContainer.shared.showReading
    ) {
        self.eventReading = eventReading
        self.brandReading = brandReading
        self.showReading = showReading
    }

    func loadData(includeEmpty: Bool, query: EventListQuery) async {
        defer { isLoading = false }
        do {
            // 全 kind を取ってきて、表示時に excludedKinds で client-side filter。
            eventsWithDate = try await eventReading.eventsWithFirstDate(
                brandId: nil,
                includeEmpty: includeEmpty,
                liveOnly: false,
                kinds: EventKind.allCases
            )
            brands = try await brandReading.brands()
            await rebuild(query: query)
        } catch {
            Logger.database.error("load_failed events: \(error.localizedDescription)")
        }
    }

    func rebuild(query: EventListQuery) async {
        var filter = query.filter
        // 参加記録は show 単位でしか保存されない (UserMarkService.setAttendance は entity: .show)。
        // event 単位の参加フィルタは、参加済み show の event_id を逆引きして構築する。
        if filter.attendanceFilter != "all" {
            filter.attendedEventIds = await resolveAttendedEventIds()
        }
        // 会場は show 単位なので、event 単位の絞り込みに使うため id 集合へ逆引きする。
        if !filter.venue.isEmpty {
            filter.venueEventIds = (try? await showReading.eventIdsAtVenue(filter.venue)) ?? []
        }
        let filtered = filterEvents(eventsWithDate, filter)
        let groups = groupEventsByYear(filtered, upcoming: query.upcoming, todayKey: query.todayKey)
        filteredCount = groups.reduce(0) { $0 + $1.events.count }
        groupedByYear = groups
    }

    /// 参加済み (show 単位) マークから、該当する event_id の集合を解決する。
    /// show→event の一括逆引き API が存在しないため、既存の単発 `show(id:)` を
    /// 参加済み show id ごとに並行 fetch して event_id を集約する。
    private func resolveAttendedEventIds() async -> Set<String> {
        let attendedShowIds = UserMarkService.shared.allMarked(kind: .attended, entity: .show)
        guard !attendedShowIds.isEmpty else { return [] }
        let showReading = self.showReading
        return await withTaskGroup(of: String?.self) { group in
            for showId in attendedShowIds {
                group.addTask {
                    (try? await showReading.show(id: showId))?.eventId
                }
            }
            var result: Set<String> = []
            for await eventId in group {
                if let eventId { result.insert(eventId) }
            }
            return result
        }
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
