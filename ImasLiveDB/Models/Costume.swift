import Foundation
import GRDB

/// ライブ衣装の目録。
///
/// **画像は持たない。** 版権物を配らない方針なので、衣装は名前と出典で見分ける。
///
/// `unitId` / `idolId` は「誰のための衣装か」。両方 nil なら公演の共通衣装、
/// `unitId` があればその編成の衣装、`idolId` があればその人のソロ衣装。
/// 「実際に誰が着たか」は `CostumeWear` 側にあり、ここは目録としての帰属だけ。
struct Costume: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "costumes"

    var id: String
    var brandId: String?
    var name: String
    var nameKana: String?
    var unitId: String?
    var idolId: String?
    var description: String?
    /// 出典 (公式サイト・公式物販ページ等)。二次情報しか無い衣装は入れない。
    var sourceUrl: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case brandId = "brand_id"
        case nameKana = "name_kana"
        case unitId = "unit_id"
        case idolId = "idol_id"
        case sourceUrl = "source_url"
        case sortOrder = "sort_order"
    }

    static let wears = hasMany(CostumeWear.self)
    var wears: QueryInterfaceRequest<CostumeWear> { request(for: Costume.wears) }
}

/// その公演で衣装が着られた記録。
///
/// **粗さをそのまま持てる形にしてある。** 衣装は「公演で使われたのは確かだが
/// どの曲かまでは分からない」ことが多いので、`setlistItemId` は nil を許す。
/// `idolId` が nil なら「その場の全員」= 共通衣装で、入っていればその人だけ
/// (同じ曲でユニットごとに違う衣装、という記録ができる)。
///
/// どちらの nil も欠損ではなく正規の状態なので、同期で捨ててはいけない。
struct CostumeWear: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "costume_wears"

    var id: String
    var costumeId: String
    var showId: String
    /// nil = 公演では使われたが、どの曲かは特定していない。
    var setlistItemId: String?
    /// nil = その場の全員 (共通衣装)。
    var idolId: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case costumeId = "costume_id"
        case showId = "show_id"
        case setlistItemId = "setlist_item_id"
        case idolId = "idol_id"
        case sortOrder = "sort_order"
    }

    static let costume = belongsTo(Costume.self)
    static let show = belongsTo(Show.self)
}
