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
    /// 参加済みの公演 ID (UserMarkBar の参加 ON 判定・シート反映後の再計算用)。
    private(set) var attendedShowIds: Set<String> = []
    /// ヒーロー (開催期間・会場・今後か・参加の札)。コアが組む。参加を付け替えたら組み直す。
    private(set) var hero: EventHeroRecord?
    /// チケット受付を帯の時間軸に並べたもの (段階・並び・表示文字列・軸の位置は共有コアが決め切って返す)。
    private(set) var ticketTimeline: TicketSaleTimeline?
    /// チケット受付一覧 (帯の行の並びそのまま)。
    var ticketSales: [TicketSale] { ticketTimeline?.rows.map(\.sale) ?? [] }
    /// このイベントで着られた衣装 (共通・個別)。分け方も並びも imas-core。
    private(set) var costumes: EventCostumesRecord?

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
            ticketTimeline = try await eventReading.ticketSaleTimeline(eventId: event.id)
        } catch {
            Logger.database.error("load_failed event_detail: \(error.localizedDescription)")
        }
        await reloadHero(eventId: event.id)
        do {
            costumes = try await showReading.eventCostumes(eventId: event.id)
        } catch {
            Logger.database.error("load_failed event_costumes: \(error.localizedDescription)")
        }
    }

    /// チケット受付の追加・編集・削除の後に呼ぶ (他は変わっていないので全体は読み直さない)。
    func reloadTicketSales(eventId: String) async {
        do {
            ticketTimeline = try await eventReading.ticketSaleTimeline(eventId: eventId)
        } catch {
            Logger.database.error("load_failed ticket_sales: \(error.localizedDescription)")
        }
    }

    func recomputeAttendedShows() {
        attendedShowIds = Set(shows.map(\.id).filter {
            UserMarkService.shared.bool(.attended, entity: .show, id: $0)
        })
    }

    /// 参加の札は参加マークで変わるので、付け替えた後にも呼ぶ。
    func reloadHero(eventId: String) async {
        do {
            hero = try await eventReading.eventHero(
                eventId: eventId, attendedShowIds: Array(attendedShowIds),
                eventMarked: UserMarkService.shared.bool(.attended, entity: .event, id: eventId),
                today: JSTDay.today())
        } catch {
            Logger.database.error("load_failed event_hero: \(error.localizedDescription)")
        }
    }
}
