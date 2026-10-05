import Foundation
import GRDB

/// 公演のチケット価格 1 行 (`show_tickets`)。**マスタ**なので同期で降ってくる。
///
/// 自分がいくら払ったかは端末ローカルの `Expense` 側。ここは「定価はいくらか」で、
/// 税込・手数料抜き。`isEstimate` は公式に出ていない推定値の札。
///
/// 選び方・並び・価格帯は共有コア (`domain/ticket_prices.rs`)。この型は器で、
/// FFI に渡すときは `ticket` で core の `ShowTicket` に詰め替える。
struct ShowTicketRecord: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "show_tickets"

    var id: String
    var showId: String
    /// `live` / `stream` / `live_viewing`。
    var kind: String
    var name: String
    var price: Int64
    var isEstimate: Bool
    var note: String?
    var sortOrder: Int64
    /// 配信 (アーカイブ) の視聴期間。JST の `YYYY-MM-DD HH:MM` か `YYYY-MM-DD`。無ければ nil。
    /// 公開中かどうかの判定・文言はコア (`ticketArchive`) が決める。
    var archiveStartsAt: String?
    var archiveEndsAt: String?

    enum CodingKeys: String, CodingKey {
        case id, kind, name, price, note
        case showId = "show_id"
        case isEstimate = "is_estimate"
        case sortOrder = "sort_order"
        case archiveStartsAt = "archive_starts_at"
        case archiveEndsAt = "archive_ends_at"
    }

    enum Columns {
        static let showId = Column(CodingKeys.showId)
        static let sortOrder = Column(CodingKeys.sortOrder)
    }

    /// コアに渡す形。形態の読み替えもコアの規則に任せる。
    var ticket: ShowTicket {
        ShowTicket(
            id: id,
            showId: showId,
            kind: ticketKindFromAttendance(textValue: kind),
            name: name,
            price: price,
            isEstimate: isEstimate,
            note: note,
            sortOrder: sortOrder,
            archiveStartsAt: archiveStartsAt,
            archiveEndsAt: archiveEndsAt
        )
    }
}
