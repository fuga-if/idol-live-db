import Foundation
import GRDB

/// セトリ曲の出演アイドル。 Cast テーブル廃止により idol_id 直結に変更済み。
struct SetlistPerformer: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "setlist_performers"

    var setlistItemId: String
    var idolId: String

    enum CodingKeys: String, CodingKey {
        case setlistItemId = "setlist_item_id"
        case idolId = "idol_id"
    }

    static let setlistItem = belongsTo(SetlistItem.self)
    static let idol = belongsTo(Idol.self)
}
