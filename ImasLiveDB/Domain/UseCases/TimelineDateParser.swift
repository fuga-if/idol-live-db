import Foundation

/// DB の `YYYY-MM-DD` 文字列を Date に直す。年表はすべて JST の日付として扱う。
enum TimelineDateParser {
    /// 年表の座標計算に使うカレンダー (JST 固定)。端末のタイムゾーンで年境界がずれると
    /// 「1/1 のリリースが前年の帯に入る」ような表示崩れになるため、明示的に固定する。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo") ?? .gmt
        return calendar
    }()

    static func date(_ text: String?) -> Date? {
        guard let text, text.count >= 10 else { return nil }
        let parts = text.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }

    /// `GROUP_CONCAT` のカンマ区切り日付を Date 配列に。重複は畳んで昇順で返す。
    static func dates(_ text: String?) -> [Date] {
        guard let text, !text.isEmpty else { return [] }
        let parsed = text.split(separator: ",").compactMap { date(String($0)) }
        return Array(Set(parsed)).sorted()
    }
}
