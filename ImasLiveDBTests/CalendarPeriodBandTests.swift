import XCTest
@testable import ImasLiveDB

/// 受付期間の帯を週の列に置くところ (`CalendarPeriodBand.pack`)。置き方はコア。
/// ここでは、週の頭の日付を端末の暦のまま渡していることを見る。
final class CalendarPeriodBandTests: XCTestCase {

    /// JST より東 (UTC+14) の端末でも、受付開始の日は週の同じ列に来る (RedTeam M-3)。
    func testBandStartsOnTheSameColumnEastOfJST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        let sunday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 20)))
        let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: sunday) }
        let tuesday = weekDays[2]
        let entry = CalendarEntry.ticketPeriod(TicketPeriodRow(
            eventId: "ev1", eventName: "ライブ", brandColor: nil,
            start: "2026-09-22", end: "2026-09-24", url: nil))

        let bands = CalendarPeriodBand.pack(
            weekDays: weekDays, entriesByDate: [calendar.startOfDay(for: tuesday): [entry]],
            calendar: calendar)

        XCTAssertEqual(bands.map(\.startCol), [2])
        XCTAssertEqual(bands.map(\.endCol), [4])
    }
}
