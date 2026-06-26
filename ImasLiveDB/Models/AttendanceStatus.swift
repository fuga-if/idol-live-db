import Foundation

/// ユーザーが参加マーク (`.attended`) を付けた公演群から導く「参加予定 / 参加済み」状態。
///
/// 参加は公演 (show) 単位で記録されるが、表示は**日付で出し分ける**:
/// - 参加公演のうち最も早い「今日以降」の公演があれば **参加予定**（その日までの日数つき）
/// - すべて過去なら **参加済み**
///
/// これにより「開催前=参加予定 → 開催後=自動で参加済み」が、フラグを増やさず日付だけで実現できる。
enum AttendanceStatus: Equatable {
    case none                       // 参加マークなし
    case planned(daysUntil: Int)    // 参加予定 (今日以降の参加公演あり)。0 = 今日
    case attended                   // 参加済み (参加公演はすべて過去)

    /// 参加マークが1つでも付いているか。
    var isMarked: Bool { self != .none }

    /// 予定中（未来公演あり）か。
    var isPlanned: Bool { if case .planned = self { return true }; return false }

    /// 表示ラベル。「参加予定・あと3日」「参加予定・今日」「参加済み」。
    var label: String {
        switch self {
        case .none: return ""
        case .planned(let d): return d <= 0 ? "参加予定・今日" : "参加予定・あと\(d)日"
        case .attended: return "参加済み"
        }
    }

    /// SF Symbol。
    var systemImage: String {
        switch self {
        case .none: return "circle"
        case .planned: return "calendar.badge.clock"
        case .attended: return "checkmark.seal.fill"
        }
    }
}

extension AttendanceStatus {
    /// 参加マークのある公演日 (yyyy-MM-dd 文字列) 群から状態を導く。
    /// - Parameter attendedShowDates: `.attended` が付いた公演の `date` 文字列（空文字は無視）。
    static func derive(attendedShowDates: [String], now: Date = Date()) -> AttendanceStatus {
        let dates = attendedShowDates.filter { !$0.isEmpty }
        guard !dates.isEmpty else { return .none }
        let today = dayString(now)
        // 今日以降で最も早い参加公演。あれば「参加予定」。
        if let nearest = dates.filter({ $0 >= today }).min() {
            let d = daysBetween(target: nearest, now: now) ?? 0
            return .planned(daysUntil: max(0, d))
        }
        return .attended
    }

    private static func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }

    private static func dayString(_ date: Date) -> String { dayFormatter().string(from: date) }

    /// 今日(0:00)から対象公演日(0:00)までの日数。過去は負。
    private static func daysBetween(target: String, now: Date) -> Int? {
        guard let t = dayFormatter().date(from: target) else { return nil }
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: t)).day
    }
}
