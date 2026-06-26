import Foundation

/// アイドル一覧の絞り込みに必要な、解決済みの条件・集合。
/// マーク集合・キャスト名は呼び出し側 (View) が事前に解決して渡す。
struct IdolFilterContext {
    var selectedBrandIds: Set<String> = []
    /// ブランド内サブ属性 (cute/cool/passion 等)。nil = 属性絞り込みなし。
    var selectedAttribute: String? = nil
    var requireMyPick: Bool = false
    var myPickIds: Set<String> = []
    var requireFavorite: Bool = false
    var favoriteIds: Set<String> = []
    var requireNote: Bool = false
    var noteIds: Set<String> = []
    /// 名前/かな/キャスト名の部分一致検索 (空 = 検索なし)。
    var searchText: String = ""
    /// idol_id → キャスト(声優)名。検索対象に含める。
    var castNames: [String: String] = [:]
}

/// アイドル一覧へブランド/属性/マイマーク/テキスト検索の絞り込みを適用する純粋ロジック。
/// DB にも UI にも依存しない (集合・キャスト名は解決済みで受け取る) ので単体テスト可能。
func filterIdols(_ idols: [Idol], _ ctx: IdolFilterContext) -> [Idol] {
    var result = idols

    if !ctx.selectedBrandIds.isEmpty {
        result = result.filter { ctx.selectedBrandIds.contains($0.brandId) }
    }
    if let attribute = ctx.selectedAttribute {
        result = result.filter { $0.attribute == attribute }
    }
    if ctx.requireMyPick {
        result = result.filter { ctx.myPickIds.contains($0.id) }
    }
    if ctx.requireFavorite {
        result = result.filter { ctx.favoriteIds.contains($0.id) }
    }
    if ctx.requireNote {
        result = result.filter { ctx.noteIds.contains($0.id) }
    }
    if !ctx.searchText.isEmpty {
        let q = ctx.searchText
        result = result.filter { idol in
            idol.name.localizedCaseInsensitiveContains(q)
                || idol.nameKana?.localizedCaseInsensitiveContains(q) == true
                || (ctx.castNames[idol.id] ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    return result
}
