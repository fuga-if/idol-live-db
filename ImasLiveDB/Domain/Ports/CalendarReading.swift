import Foundation

/// カレンダー表示用エントリの読み取りポート (driven port)。
///
/// 実装は `Adapters/Persistence/GRDBCalendarRepository`。
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol CalendarReading: Sendable {
    /// 指定期間に該当する公演/リリース/チケット等のカレンダーエントリ。
    func calendarEntries(in interval: DateInterval) async throws -> [CalendarEntry]
}
