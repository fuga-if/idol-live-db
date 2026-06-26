import Foundation
import GRDB

struct Unit: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "units"

    var id: String
    var brandId: String
    var name: String
    var isPermanent: Bool
    var nameAlt: String?

    /// 表示用の名前（別名があれば "name / nameAlt"）
    var displayName: String {
        if let alt = nameAlt {
            return "\(name) / \(alt)"
        }
        return name
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case brandId = "brand_id"
        case isPermanent = "is_permanent"
        case nameAlt = "name_alt"
    }

    // MARK: - Associations

    static let brand = belongsTo(Brand.self)
    static let unitMembers = hasMany(UnitMember.self)
    static let members = hasMany(Idol.self, through: unitMembers, using: UnitMember.idol)

    var members: QueryInterfaceRequest<Idol> { request(for: Unit.members) }
}
