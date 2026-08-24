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

    /// 行に併記する指標のラベル (nil ならバッジを出さない)。
    ///
    /// ここだけ Swift 実装のまま残す: 一覧の行ごと (ForEach 内) に呼ばれるため、
    /// FFI へ委譲すると「要素ごとの FFI 呼び出し」になり境界規約に反する。
    /// 中身は表示文字列の組み立てだけで、`birthdayDisplay` は `Idol` モデル側の表示補助。
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

/// アイドル一覧を指定の並び順で整列する。
///
/// 本体は imas-core の domain/idol_list_filtering.rs (`sort_idol_list`)。値なしを並び方向に
/// かかわらず末尾へ送る理由・同値を公式順 (sortOrder) で安定させる理由もそちらに記載。
/// ここはエンティティ全体を FFI へ渡さないための薄いラッパ: `Idol` を判定に要る
/// フィールドの射影 (`IdolListEntry`) へ落とし、返ってきた index 列で自国の配列を
/// 引き直すだけ。`ascending` 未指定 (nil) の既定方向解決も Rust 側が担う。
func sortIdols(_ idols: [Idol], by order: IdolSortOrder, ascending: Bool? = nil) -> [Idol] {
    sortIdolList(entries: idols.map(idolListEntry), kind: order.kind, ascending: ascending)
        .map { idols[Int($0)] }
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
    /// 名前/かな/キャスト名/別名/愛称の部分一致検索 (空 = 検索なし)。
    var searchText: String = ""
    /// idol_id → キャスト(声優)名。検索対象に含める。
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
    let criteria = IdolListFilterCriteria(
        selectedBrandIds: Array(ctx.selectedBrandIds),
        selectedAttribute: ctx.selectedAttribute,
        requireMyPick: ctx.requireMyPick,
        myPickIds: Array(ctx.myPickIds),
        requireFavorite: ctx.requireFavorite,
        favoriteIds: Array(ctx.favoriteIds),
        requireNote: ctx.requireNote,
        noteIds: Array(ctx.noteIds),
        searchText: ctx.searchText,
        castNames: ctx.castNames)
    return filterIdolList(entries: idols.map(idolListEntry), criteria: criteria)
        .map { idols[Int($0)] }
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
