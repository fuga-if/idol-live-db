import Foundation
import GRDB

struct IdolBrand: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "idol_brands"

    var idolId: String
    var brandId: String
    var isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case idolId = "idol_id"
        case brandId = "brand_id"
        case isPrimary = "is_primary"
    }
}
