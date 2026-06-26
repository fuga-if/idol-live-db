import Foundation
import GRDB

struct Meta: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "meta"

    var key: String
    var value: String?

    static func getValue(_ db: Database, forKey key: String) throws -> String? {
        try Meta.filter(Column("key") == key).fetchOne(db)?.value
    }

    static func setValue(_ db: Database, _ value: String, forKey key: String) throws {
        try Meta(key: key, value: value).save(db)
    }
}
