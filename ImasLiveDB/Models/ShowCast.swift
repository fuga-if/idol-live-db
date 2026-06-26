import Foundation
import GRDB

/// 公演における出演アイドルの役割。 主演・ゲスト・通常は排他なので enum で表現する。
/// DB 列 cast_role TEXT NOT NULL DEFAULT 'member' に rawValue で対応。
enum CastRole: String, Codable, Sendable, CaseIterable {
    /// 通常出演 (主演でもゲストでもない常設メンバー)。
    case member
    /// 主演 (リード)。 公演単位で単独 or 複数 (ツイン主演) 可。
    case lead
    /// ゲスト出演 (他ブランド・外部からの客演など)。
    case guest
}

/// ショー出演アイドル。 Cast テーブル廃止により idol_id 直結。
/// テーブル名 show_cast は維持 (歴史的経緯、 SQL 影響少なくするため)。
struct ShowCast: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "show_cast"

    var showId: String
    var idolId: String
    /// 出演役割 (通常 / 主演 / ゲスト)。
    var castRole: CastRole

    init(showId: String, idolId: String, castRole: CastRole = .member) {
        self.showId = showId
        self.idolId = idolId
        self.castRole = castRole
    }

    /// 主演かどうかの便利プロパティ。
    var isLead: Bool { castRole == .lead }
    /// ゲストかどうかの便利プロパティ。
    var isGuest: Bool { castRole == .guest }

    enum CodingKeys: String, CodingKey {
        case showId = "show_id"
        case idolId = "idol_id"
        case castRole = "cast_role"
    }

    static let show = belongsTo(Show.self)
    static let idol = belongsTo(Idol.self)
}
