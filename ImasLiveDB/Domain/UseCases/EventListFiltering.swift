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

/// イベント一覧へブランド/kind/検索/参加状態/お気に入り/メモ絞り込みを適用する純粋ロジック。
/// 時系列分割・年度グルーピングは行わない (それは `groupEventsByYear`)。
/// DB にも UI にも依存しない (集合は解決済みで受け取る) ので単体テスト可能。
func filterEvents(_ events: [EventWithDate], _ ctx: EventFilterContext) -> [EventWithDate] {
    var result = events

    if !ctx.selectedBrandIds.isEmpty {
        result = result.filter { $0.event.matchesBrandFilter(ctx.selectedBrandIds) }
    }
    if !ctx.excludedKinds.isEmpty {
        result = result.filter { !ctx.excludedKinds.contains($0.event.eventKind) }
    }
    if !ctx.searchText.isEmpty {
        let lower = ctx.searchText.lowercased()
        result = result.filter { $0.event.name.lowercased().contains(lower) }
    }

    switch ctx.attendanceFilter {
    case "attended":
        result = result.filter { ctx.attendedEventIds.contains($0.event.id) }
    case "not_attended":
        result = result.filter { !ctx.attendedEventIds.contains($0.event.id) }
    default:
        break
    }

    if ctx.requireFavorite {
        result = result.filter { ctx.favoriteIds.contains($0.event.id) }
    }
    if ctx.requireNote {
        result = result.filter { ctx.noteIds.contains($0.event.id) }
    }
    if !ctx.venue.isEmpty {
        result = result.filter { ctx.venueEventIds.contains($0.event.id) }
    }

    return result
}
