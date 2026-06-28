import Foundation
import GRDB

/// イベントの映像円盤 (ライブ Blu-ray / DVD)。
/// 所有チェックの母集団。レコードが存在するライブだけ所有UIを出す (データ駆動)。
/// 所有フラグ自体は user_marks(entity=release, kind=owned) に持つ。
struct EventRelease: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "event_releases"

    var id: String
    var eventId: String
    /// 公演単位の円盤なら show_id。イベント全体BOXなら nil。
    var showId: String?
    /// blu_ray / dvd / dvd_box
    var productType: String
    var title: String
    /// 品番 (例: EYXA-13123)
    var catalogNumber: String?
    /// 発売日 (YYYY-MM-DD)
    var releaseDate: String?
    var jacketUrl: String?
    var purchaseUrl: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case showId = "show_id"
        case productType = "product_type"
        case title
        case catalogNumber = "catalog_number"
        case releaseDate = "release_date"
        case jacketUrl = "jacket_url"
        case purchaseUrl = "purchase_url"
        case sortOrder = "sort_order"
    }

    // MARK: - Associations

    static let event = belongsTo(Event.self)
    var event: QueryInterfaceRequest<Event> { request(for: EventRelease.event) }
}

// MARK: - ProductType 表示

enum ReleaseProductType: String, Codable, CaseIterable, Sendable {
    case bluRay = "blu_ray"
    case dvd
    case dvdBox = "dvd_box"

    var label: String {
        switch self {
        case .bluRay: return "Blu-ray"
        case .dvd:    return "DVD"
        case .dvdBox: return "DVD BOX"
        }
    }
}

extension EventRelease {
    var productTypeEnum: ReleaseProductType { ReleaseProductType(rawValue: productType) ?? .bluRay }
}
