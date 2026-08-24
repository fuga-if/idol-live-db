import Foundation

/// イベント一覧の「年度グループ」。`groupEventsByYear` の出力単位。
struct YearGroup: Identifiable {
    var id: String { year }
    let year: String
    let events: [EventWithDate]
}

/// 時系列フィルタ + 年度グルーピング。
///
/// 本体は imas-core (Rust) の `domain/event_grouping.rs`。今後/開催済みの境界判定・
/// 部分日付 ("YYYY" 等) の桁合わせ・「年度不明」を末尾に置く規則もそちらに記載。
/// ここは firstDate の射影を 1 回の FFI 呼び出しに渡し、返った index 列を
/// `events` から引き直して表示用 `YearGroup` に組み立てるだけ (件数によらず 1 呼び出し)。
///
/// `todayKey` の既定値は注入しない: 呼び出し側が `JSTDay.today()` を渡す
/// (公演日は日本の開催日なので、端末ローカル日で切ると海外で 1 日ずれる)。
func groupEventsByYear(_ events: [EventWithDate], upcoming: Bool, todayKey: String) -> [YearGroup] {
    let groups = groupEventIndicesByYear(
        firstDates: events.map(\.firstDate),
        upcoming: upcoming,
        todayKey: todayKey
    )
    return groups.map { group in
        YearGroup(year: group.year, events: group.indices.map { events[Int($0)] })
    }
}
