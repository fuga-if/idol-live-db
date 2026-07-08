import Foundation
import GRDB

/// 「アイドル本人ではない関係者」(プロデューサー補佐・事務員・社長・幹部)。
/// カレンダーの誕生日表示用。アイドル一覧・検索・統計には登場しない。
struct Staff: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "staff"

    var id: String
    var brandId: String
    var name: String
    var nameKana: String?
    var nameRomaji: String?
    /// 役職・所属 (例: "765プロダクション事務員 / プロデューサー補佐")。表示用の補助テキスト。
    var role: String?
    /// '--MM-DD' (年なし)。Idol.birthday と同じ形式。
    var birthday: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, role, birthday
        case brandId = "brand_id"
        case nameKana = "name_kana"
        case nameRomaji = "name_romaji"
        case sortOrder = "sort_order"
    }
}
