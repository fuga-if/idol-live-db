import Foundation

/// `CalendarReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
struct GRDBCalendarRepository: CalendarReading {
    let database: AppDatabase

    func calendarEntries(in interval: DateInterval) async throws -> [CalendarEntry] {
        try database.fetchCalendarEntries(in: interval)
    }
}
