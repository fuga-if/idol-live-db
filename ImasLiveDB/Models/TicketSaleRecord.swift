import Foundation
import GRDB

/// チケット受付 1 行 (`ticket_sales`)。**マスタ**なので同期で降ってくるほか、
/// モデレーターがイベント編集画面から作成・編集・削除できる (`TicketSaleEditView`)。
///
/// 段階の判定・並び・注目受付・期間の文字列・検査文言はすべて共有コア
/// (`imas-core` `domain/ticket_sales.rs`) が決める。この型は GRDB へ保存するだけの器で、
/// 表示・検査は `SnapshotStore` (`ticketSalesForEvent` / `ticketSaleSpotlight` /
/// `ticketSaleDeadlines`) や `validateTicketSaleDraft` を直接呼ぶ (この型を経由しない)。
struct TicketSaleRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "ticket_sales"

    var id: String
    var eventId: String
    /// カンマ区切りの show id。空/nil = 全公演対象。
    var showIds: String?
    /// `lottery` / `first_come` / `resale` / `same_day`。
    var kind: String
    var name: String
    var startsAt: String?
    var endsAt: String?
    var resultAt: String?
    var url: String?
    var note: String?
    var sourceUrl: String
    var sortOrder: Int64

    enum CodingKeys: String, CodingKey {
        case id, kind, name, url, note
        case eventId = "event_id"
        case showIds = "show_ids"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case resultAt = "result_at"
        case sourceUrl = "source_url"
        case sortOrder = "sort_order"
    }

    enum Columns {
        static let eventId = Column(CodingKeys.eventId)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }
}
