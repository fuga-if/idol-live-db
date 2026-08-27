import Foundation
import GRDB

struct Unit: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
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
    static let versions = hasMany(UnitVersion.self)

    var members: QueryInterfaceRequest<Idol> { request(for: Unit.members) }
    var versions: QueryInterfaceRequest<UnitVersion> { request(for: Unit.versions) }
}

/// ユニットのバージョンと、その版が有効だった期間。
///
/// リブート企画 (Project“ReLight”AXE8) のように、ロゴ・キャッチコピー・曲調が変わっても
/// **ユニット自体は同一**という場合がある。`units` を 2 行に割ると、メンバーも過去曲も
/// 分断されてしまう。会場の改名を `VenueName` に内包させたのと同じ形で、版を内包させる。
///
/// 曲がどの版のものかは `Song.unitVersionId` が持つ (nil = 無印)。
/// ユニット単位のフラグでは曲の新旧を区別できないので、版は曲側から指す。
///
/// これまで置き場が無かったキャッチコピーも、版ごとに持てるようになった。
struct UnitVersion: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "unit_versions"

    var id: String
    var unitId: String
    /// 版の識別子 ('AXE8' 等)。**版の判定はこれで行う**。
    ///
    /// 表示名 (`name`) の文字列一致に頼ると、表記揺れや改称で判定が壊れる。
    /// 無印の版は nil。
    var code: String?
    /// 表示名 ('Project“ReLight”AXE8' / 'オリジナル')。
    var name: String
    /// その版のキャッチコピー。
    var catchphrase: String?
    var logoUrl: String?
    /// nil = 結成時から。
    var validFrom: String?
    /// nil = 現行の版。
    var validTo: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, code, name, catchphrase
        case unitId = "unit_id"
        case logoUrl = "logo_url"
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case sortOrder = "sort_order"
    }

    // MARK: - Associations

    static let unit = belongsTo(Unit.self)

    // MARK: - Computed

    /// 指定日 (YYYY-MM-DD) にこの版が有効だったか。
    /// 境界は `validFrom <= date < validTo` (切り替え日当日は新しい版を採る)。
    func isValid(on date: String) -> Bool {
        if let validFrom, date < validFrom { return false }
        if let validTo, date >= validTo { return false }
        return true
    }
}
