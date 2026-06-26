import Foundation

/// イベント一覧の「年度グループ」。`groupEventsByYear` の出力単位。
struct YearGroup: Identifiable {
    var id: String { year }
    let year: String
    let events: [EventWithDate]
}

/// 時系列フィルタ + 年度グルーピング (純粋ロジック)。
///
/// フィルタ済みの `[EventWithDate]` を「今後 / 開催済み」で時系列分割し、年度ごとに束ねて並べる。
/// DB にも UI にも依存しない純粋関数なので単体テスト可能。
///
/// - Parameters:
///   - events: ブランド/kind/参加状態など事前フィルタ済みのイベント。
///   - upcoming: true=今後の予定 (近い順/昇順)、false=開催済み (新しい順/降順)。
///   - todayKey: 端末ローカルの今日 "YYYY-MM-DD"。今後/開催済みの境界。
/// - Returns: 年度グループの配列。今後=年昇順、開催済み=年降順。「年度不明」は常に末尾。
func groupEventsByYear(_ events: [EventWithDate], upcoming: Bool, todayKey: String) -> [YearGroup] {
    // 年度キーとして使える日付か (4桁未満は不明扱い)。
    func yearDateKey(_ event: EventWithDate) -> String? {
        guard let date = event.firstDate, date.count >= 4 else { return nil }
        return date
    }

    // 時系列分割。日付不明 (4桁未満) は開催済みに入れず今後タブにのみ残す (登録途中の予定扱い)。
    let timeFiltered = events.filter { ew in
        guard let date = yearDateKey(ew) else { return upcoming }
        return upcoming ? date >= todayKey : date < todayKey
    }

    var yearMap: [String: [EventWithDate]] = [:]
    for ew in timeFiltered {
        let year = yearDateKey(ew).map { String($0.prefix(4)) + "年" } ?? "年度不明"
        yearMap[year, default: []].append(ew)
    }

    let yearKeys = yearMap.keys.sorted { a, b in
        if a == "年度不明" { return false }
        if b == "年度不明" { return true }
        return upcoming ? a < b : a > b
    }

    return yearKeys.map { year in
        let sorted = yearMap[year]!.sorted { l, r in
            let ld = l.firstDate ?? "", rd = r.firstDate ?? ""
            return upcoming ? ld < rd : ld > rd
        }
        return YearGroup(year: year, events: sorted)
    }
}
