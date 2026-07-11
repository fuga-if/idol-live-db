import Foundation
import GRDB

/// 個人用タグ (ローカル専用)。コミュニティタグ (`idol_tag_master` 等の共有マスタ、サーバー同期・投票制) とは異なり、
/// ユーザーが自由入力で付ける私用の分類 (例:「聞いた」)。サーバーには一切送信しない。
struct PersonalTag: Codable, FetchableRecord, PersistableRecord, Identifiable, Sendable {
    static let databaseTableName = "personal_tags"

    var entityType: String
    var entityId: String
    var tagName: String
    var createdAt: String

    /// GRDB Identifiable 用の合成 id (テーブルの実主キーは entity_type/entity_id/tag_name の複合)。
    var id: String { "\(entityType):\(entityId):\(tagName)" }

    enum Columns {
        static let entityType = Column(CodingKeys.entityType)
        static let entityId   = Column(CodingKeys.entityId)
        static let tagName    = Column(CodingKeys.tagName)
        static let createdAt  = Column(CodingKeys.createdAt)
    }

    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId   = "entity_id"
        case tagName    = "tag_name"
        case createdAt  = "created_at"
    }
}
