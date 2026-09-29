import Foundation

/// アイドル一覧の並び順。
///
/// 既定方向・ブランド区切りの扱い・ラベル文言の本体は imas-core の
/// domain/idol_list_filtering.rs (`IdolSortKind` / `IdolSortOrderMeta`)。
/// なぜ公式順以外でブランドの区切りを外すか (通し並び) もそちらに記載。
/// この enum が残るのは、rawValue が `@AppStorage` の保存値・UI の `CaseIterable`
/// 列挙という Swift 側の顔だから。各プロパティは起動後 1 回の FFI 呼び出しで
/// 引いたメタ表 (`idolSortOrderTable`) の参照だけで、判定はしない。
enum IdolSortOrder: String, CaseIterable, Sendable {
    case official = "公式順"
    case nameKana = "五十音順"
    case age = "年齢"
    case height = "身長"
    case weight = "体重"
    case birthday = "誕生日"
    case debut = "デビュー日"

    /// 生成バインディング側の対応値 (`sortIdols` が FFI へ渡す)。
    fileprivate var kind: IdolSortKind {
        switch self {
        case .official: return .official
        case .nameKana: return .nameKana
        case .age:      return .age
        case .height:   return .height
        case .weight:   return .weight
        case .birthday: return .birthday
        case .debut:    return .debut
        }
    }

    /// Rust から一括で引いたメタ表。ケースごとの FFI 呼び出しループにしないための
    /// 1 回取得 + キャッシュ。全種別が必ず載っていることは Rust 側のテストで保証される。
    private static let meta: [IdolSortOrder: IdolSortOrderMeta] = {
        let table = idolSortOrderTable()
        return Dictionary(uniqueKeysWithValues: allCases.map { order in
            (order, table.first { $0.kind == order.kind }!)
        })
    }()

    /// 未指定時の並び方向。
    var defaultAscending: Bool { Self.meta[self]!.defaultAscending }

    /// ブランド別セクションを維持するか。
    var keepsBrandGrouping: Bool { Self.meta[self]!.keepsBrandGrouping }

    /// 昇順の言い回し (「年下から」等)。
    var ascendingLabel: String { Self.meta[self]!.ascendingLabel }

    /// 降順の言い回し (「年上から」等)。
    var descendingLabel: String { Self.meta[self]!.descendingLabel }
}

/// アイドル一覧を指定の並び順で整列し、行に添える指標も受け取る。
///
/// 並べ方の本体は imas-core の domain/idol_list_filtering.rs (値なしを並び方向にかかわらず
/// 末尾へ送る・同値を公式順で安定させる)。ここは `Idol` を判定に要るフィールドの射影
/// (`IdolListEntry`) へ落とし、返ってきた index 列で自国の配列を引き直すだけ。
/// 指標の文言もコア (`sort_idol_list_rows`) が作る。行ごとに FFI を呼ばないよう、
/// 添え物は idol id → 文言の表で返す (公式順・五十音は空)。
func sortIdolsWithMetrics(
    _ idols: [Idol], by order: IdolSortOrder, ascending: Bool? = nil
) -> (idols: [Idol], metricLabels: [String: String]) {
    let rows = sortIdolListRows(entries: idols.map(idolListEntry), kind: order.kind, ascending: ascending)
    var labels: [String: String] = [:]
    let sorted = rows.map { row -> Idol in
        let idol = idols[Int(row.index)]
        if let label = row.metricLabel { labels[idol.id] = label }
        return idol
    }
    return (sorted, labels)
}

/// 検索欄の語を何として引くか。名前と CV 名は別の軸で、混ぜて当てない
/// (照合の本体は imas-core の `filter_idol_list`)。rawValue は `@AppStorage` の保存値。
enum IdolSearchTarget: String, CaseIterable, Sendable {
    case name = "アイドル名"
    case voiceActor = "CV名"
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
    /// 検索欄の語 (空 = 検索なし)。何に当てるかは `searchTarget`。
    var searchText: String = ""
    var searchTarget: IdolSearchTarget = .name
    /// idol_id → キャスト(声優)名。`searchTarget == .voiceActor` の照合先。
    var castNames: [String: String] = [:]
}

/// アイドル一覧へブランド/属性/マイマーク/テキスト検索の絞り込みを適用する。
///
/// 本体は imas-core の domain/idol_list_filtering.rs (`filter_idol_list`)。別名 (フルネーム)
/// や愛称まで検索対象に含める理由もそちらに記載。ここは射影 (`IdolListEntry`) と
/// 条件 (`IdolListFilterCriteria`) へ落とし、返ってきた index 列で自国の配列を引き直すだけ。
/// 生成側の型名が `IdolListFilterCriteria` なのは、この既存 struct と同一モジュール内で
/// 衝突するため。
func filterIdols(_ idols: [Idol], _ ctx: IdolFilterContext) -> [Idol] {
    filterIdolList(entries: idols.map(idolListEntry), criteria: criteria(ctx))
        .map { idols[Int($0)] }
}

/// 検索欄の語を「アイドル名として」「CV 名として」引いたときの件数。切替に添える。
/// 検索以外の軸は `ctx` のとおり効かせる (本体は imas-core の `idol_search_target_counts`)。
func idolSearchCounts(_ idols: [Idol], _ ctx: IdolFilterContext) -> IdolSearchTargetCounts {
    idolSearchTargetCounts(entries: idols.map(idolListEntry), criteria: criteria(ctx), text: ctx.searchText)
}

private func criteria(_ ctx: IdolFilterContext) -> IdolListFilterCriteria {
    IdolListFilterCriteria(
        selectedBrandIds: Array(ctx.selectedBrandIds),
        selectedAttribute: ctx.selectedAttribute,
        requireMyPick: ctx.requireMyPick,
        myPickIds: Array(ctx.myPickIds),
        requireFavorite: ctx.requireFavorite,
        favoriteIds: Array(ctx.favoriteIds),
        requireNote: ctx.requireNote,
        noteIds: Array(ctx.noteIds),
        searchText: ctx.searchTarget == .name ? ctx.searchText : "",
        voiceActorText: ctx.searchTarget == .voiceActor ? ctx.searchText : "",
        castNames: ctx.castNames)
}

/// FFI 射影: 絞り込み・並べ替えの判定に要るフィールドだけを `IdolListEntry` へ落とす。
/// `aliases` は生のカンマ区切りのまま渡す (分割規則も Rust 側が一次実装)。
private func idolListEntry(_ idol: Idol) -> IdolListEntry {
    IdolListEntry(
        idolId: idol.id,
        brandId: idol.brandId,
        name: idol.name,
        nameKana: idol.nameKana,
        nickname: idol.nickname,
        aliases: idol.aliases,
        attribute: idol.attribute,
        sortOrder: Int64(idol.sortOrder),
        age: idol.age.map(Int64.init),
        height: idol.height,
        weight: idol.weight,
        birthday: idol.birthday,
        debutDate: idol.debutDate)
}
