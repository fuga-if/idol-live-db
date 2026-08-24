import Foundation

/// イベント一覧の絞り込みに必要な、解決済みの条件・集合。
/// マーク集合は呼び出し側 (View) が UserMarkService から事前に解決して渡す。
struct EventFilterContext {
    /// 選択ブランド (空 = 全ブランド)。joint 含めいずれか該当で残す。
    var selectedBrandIds: Set<String> = []
    /// 除外する kind。
    var excludedKinds: Set<EventKind> = []
    /// 名前部分一致の検索語 (空 = 検索なし)。
    var searchText: String = ""
    /// "all" / "attended" / "not_attended"。
    var attendanceFilter: String = "all"
    var attendedEventIds: Set<String> = []
    var requireFavorite: Bool = false
    var favoriteIds: Set<String> = []
    var requireNote: Bool = false
    var noteIds: Set<String> = []
    /// 会場名で絞り込む (空 = 絞り込みなし)。表示用に保持するだけで、
    /// 実際の判定は解決済みの `venueEventIds` で行う。
    var venue: String = ""
    /// `venue` で公演があったイベントの id 集合 (呼び出し側が DB から解決して渡す)。
    /// 会場は show 単位・絞り込み対象は event 単位なので、ここで橋渡しする。
    var venueEventIds: Set<String> = []
}

/// イベント一覧へブランド/kind/検索/参加状態/お気に入り/メモ/会場絞り込みを適用する。
///
/// 本体は imas-core の domain/event_list_filtering.rs (合同ブランド判定・未知 kind の
/// live フォールバック・venue の on/off 判定もそちら参照)。ここはエンティティ全体を
/// FFI へ渡さないための薄いラッパ: `EventWithDate` を判定に要る 5 フィールドの射影
/// (`EventFilterItem`) へ落とし、返ってきた index 列で自国の配列を引き直すだけ。
/// `excludedKinds` は Rust 側が生文字列比較なので rawValue へ落として渡す。
func filterEvents(_ events: [EventWithDate], _ ctx: EventFilterContext) -> [EventWithDate] {
    let items = events.map {
        EventFilterItem(
            id: $0.event.id,
            brandId: $0.event.brandId,
            jointBrandIds: $0.event.jointBrandIds,
            name: $0.event.name,
            kind: $0.event.kind)
    }
    let criteria = EventFilterCriteria(
        selectedBrandIds: Array(ctx.selectedBrandIds),
        excludedKinds: ctx.excludedKinds.map(\.rawValue),
        searchText: ctx.searchText,
        attendanceFilter: ctx.attendanceFilter,
        attendedEventIds: Array(ctx.attendedEventIds),
        requireFavorite: ctx.requireFavorite,
        favoriteIds: Array(ctx.favoriteIds),
        requireNote: ctx.requireNote,
        noteIds: Array(ctx.noteIds),
        venue: ctx.venue,
        venueEventIds: Array(ctx.venueEventIds))
    return filterEventIndices(items: items, criteria: criteria).map { events[Int($0)] }
}
