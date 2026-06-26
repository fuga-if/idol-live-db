import Foundation
import GRDB

struct UnitMember: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "unit_members"

    var unitId: String
    var idolId: String

    enum CodingKeys: String, CodingKey {
        case unitId = "unit_id"
        case idolId = "idol_id"
    }

    // MARK: - Associations

    static let unit = belongsTo(Unit.self)
    static let idol = belongsTo(Idol.self)
}
