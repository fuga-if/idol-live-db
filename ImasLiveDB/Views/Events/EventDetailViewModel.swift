import Foundation
import os

/// EventDetailView のデータ取得担当。
///
/// 役割分担:
/// - **VM (ここ)**: ポート越しの公演/統計/ブランド/参加/ユニット取得 (`showReading`/`eventReading`/
///   `brandReading`/`unitReading`) と、参加済み公演集合の再計算結果を保持。
/// - **View 側**: シート表示・セグメント・編集意図などの UI 状態を保持する。
///
/// 参加済み判定は `UserMarkService` を読むが、メソッド呼び出しは観測を張らないので VM 文脈で問題ない。
@MainActor
@Observable
final class EventDetailViewModel {
    private(set) var shows: [Show] = []
    private(set) var stats: EventStats?
    private(set) var brand: Brand?
    private(set) var attendance: EventAttendance?
    private(set) var unitIndex: UnitIndex?
    /// この event のセトリで歌唱された unit_id 集合 (出演者ユニット表示の許可リスト)。
    private(set) var performedUnitIds: Set<String> = []
    /// 参加済みの公演 ID (UserMarkBar の参加 ON 判定・シート反映後の再計算用)。
    private(set) var attendedShowIds: Set<String> = []

    private let eventReading: any EventReading
    private let showReading: any ShowReading
    private let brandReading: any BrandReading
    private let unitReading: any UnitReading

    nonisolated init(
        eventReading: any EventReading = AppContainer.shared.eventReading,
        showReading: any ShowReading = AppContainer.shared.showReading,
        brandReading: any BrandReading = AppContainer.shared.brandReading,
        unitReading: any UnitReading = AppContainer.shared.unitReading
    ) {
        self.eventReading = eventReading
        self.showReading = showReading
        self.brandReading = brandReading
        self.unitReading = unitReading
    }

    func loadData(event: Event) async {
        do {
            shows = try await showReading.shows(eventId: event.id)
            recomputeAttendedShows()
            stats = try await eventReading.eventStats(eventId: event.id)
            if let brandId = event.brandId {
                let brands = try await brandReading.brands()
                brand = brands.first { $0.id == brandId }
            }
            attendance = try await eventReading.eventAttendance(eventId: event.id)
            unitIndex = try await unitReading.unitIndex()
            performedUnitIds = try await unitReading.performedUnitIds(eventId: event.id)
        } catch {
            Logger.database.error("load_failed event_detail: \(error.localizedDescription)")
        }
    }

    func recomputeAttendedShows() {
        attendedShowIds = Set(shows.map(\.id).filter {
            UserMarkService.shared.bool(.attended, entity: .show, id: $0)
        })
    }
}
