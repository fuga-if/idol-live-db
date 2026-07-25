import Foundation

/// アイドル一覧の並び順。
///
/// `official` 以外を選ぶと **ブランドの区切りを外した通し並び** になる。
/// 「誰がいちばん背が高いか」はブランドを跨いで初めて意味を持つ指標で、
/// ブランド別セクションの中で身長順にしても知りたいことが分からないため。
enum IdolSortOrder: String, CaseIterable, Sendable {
    /// 公式順 (sort_order)。ブランド別セクションのまま = 既定。
    case official = "公式順"
    case nameKana = "五十音順"
    case age = "年齢"
    case height = "身長"
    case weight = "体重"
    case birthday = "誕生日"
    case debut = "デビュー日"

    /// 未指定時の並び方向。数値系は「大きい順」の方が知りたい形 (背が高い順・年上順)。
    var defaultAscending: Bool {
        switch self {
        case .official, .nameKana, .birthday, .debut: return true
        case .age, .height, .weight: return false
        }
    }

    /// ブランド別セクションを維持するか。
    var keepsBrandGrouping: Bool { self == .official }

    /// 昇順/降順の言い回しは並び順で変える。「年齢を昇順」より「年下から」の方が読んで分かる。
    var ascendingLabel: String {
        switch self {
        case .official:  return "公式順"
        case .nameKana:  return "あ→ん"
        case .age:       return "年下から"
        case .height:    return "低い順"
        case .weight:    return "軽い順"
        case .birthday:  return "1月から"
        case .debut:     return "古い順"
        }
    }

    var descendingLabel: String {
        switch self {
        case .official:  return "逆順"
        case .nameKana:  return "ん→あ"
        case .age:       return "年上から"
        case .height:    return "高い順"
        case .weight:    return "重い順"
        case .birthday:  return "12月から"
        case .debut:     return "新しい順"
        }
    }

    /// 行に併記する指標のラベル (nil ならバッジを出さない)。
    func metricLabel(for idol: Idol) -> String? {
        switch self {
        case .official, .nameKana: return nil
        case .age:      return idol.age.map { "\($0)歳" }
        case .height:   return idol.height.map { "\(Int($0))cm" }
        case .weight:   return idol.weight.map { "\(Int($0))kg" }
        case .birthday: return idol.birthdayDisplay
        case .debut:    return idol.debutDate
        }
    }
}

/// アイドル一覧を指定の並び順で整列する純粋ロジック。
///
/// 値が無いアイドル (年齢・身長 未設定の外部ゲスト等) は **並び方向に関わらず必ず末尾**へ送る。
/// 昇順で先頭に空欄が並ぶと「若い順」を見に来た人の視界を潰すため。
/// 同値は公式順 (sortOrder) で安定させる。
func sortIdols(_ idols: [Idol], by order: IdolSortOrder, ascending: Bool? = nil) -> [Idol] {
    let asc = ascending ?? order.defaultAscending

    /// 比較キー。nil (値なし) は末尾送りの判定に使う。
    func doubleKey(_ idol: Idol) -> Double? {
        switch order {
        case .age:    return idol.age.map(Double.init)
        case .height: return idol.height
        case .weight: return idol.weight
        default:      return nil
        }
    }
    func stringKey(_ idol: Idol) -> String? {
        switch order {
        case .nameKana: return idol.nameKana ?? idol.name
        case .birthday: return idol.birthday
        case .debut:    return idol.debutDate
        default:        return nil
        }
    }

    guard order != .official else {
        return idols.sorted { lhs, rhs in
            asc ? lhs.sortOrder < rhs.sortOrder : lhs.sortOrder > rhs.sortOrder
        }
    }

    return idols.sorted { lhs, rhs in
        if let l = doubleKey(lhs) ?? nil, let r = doubleKey(rhs) ?? nil {
            if l != r { return asc ? l < r : l > r }
            return lhs.sortOrder < rhs.sortOrder
        }
        if let l = stringKey(lhs), let r = stringKey(rhs), !l.isEmpty, !r.isEmpty {
            if l != r { return asc ? l < r : l > r }
            return lhs.sortOrder < rhs.sortOrder
        }
        // 片方だけ値なし → 値ありを常に前に。
        let lHas = hasValue(lhs, order: order)
        let rHas = hasValue(rhs, order: order)
        if lHas != rHas { return lHas }
        return lhs.sortOrder < rhs.sortOrder
    }
}

/// 並び順のキーに値を持っているか (末尾送り判定用)。
private func hasValue(_ idol: Idol, order: IdolSortOrder) -> Bool {
    switch order {
    case .official:  return true
    case .nameKana:  return !(idol.nameKana ?? idol.name).isEmpty
    case .age:       return idol.age != nil
    case .height:    return idol.height != nil
    case .weight:    return idol.weight != nil
    case .birthday:  return !(idol.birthday ?? "").isEmpty
    case .debut:     return !(idol.debutDate ?? "").isEmpty
    }
}

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
