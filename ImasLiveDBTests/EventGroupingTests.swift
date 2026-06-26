import XCTest
@testable import ImasLiveDB

/// `groupEventsByYear` (純粋ロジック) の単体テスト。DB に依存しない。
final class EventGroupingTests: XCTestCase {

    private func makeEW(_ id: String, _ date: String?) -> EventWithDate {
        let event = Event(
            id: id, brandId: nil, name: "E\(id)", eventType: "",
            isStreaming: false, isSolo: false, kind: "live",
            ticketOpenDate: nil, ticketDeadline: nil, ticketLotteryDate: nil,
            ticketUrl: nil, jointBrandIds: nil)
        return EventWithDate(event: event, firstDate: date, lastDate: date)
    }

    func testUpcomingKeepsFutureAndSortsAscending() {
        let today = "2026-06-18"
        let events = [makeEW("a", "2026-07-01"), makeEW("past", "2025-01-01"), makeEW("c", "2026-06-20")]

        let groups = groupEventsByYear(events, upcoming: true, todayKey: today)

        // 過去 (2025) は除外。2026 のみ、近い順 (c=06-20 → a=07-01)。
        XCTAssertEqual(groups.map(\.year), ["2026年"])
        XCTAssertEqual(groups[0].events.map(\.id), ["c", "a"])
    }

    func testPastKeepsPastAndSortsYearsDescending() {
        let today = "2026-06-18"
        let events = [makeEW("a", "2025-03-01"), makeEW("b", "2024-12-01"), makeEW("future", "2026-07-01")]

        let groups = groupEventsByYear(events, upcoming: false, todayKey: today)

        // 未来 (2026-07) は除外。年は降順。
        XCTAssertEqual(groups.map(\.year), ["2025年", "2024年"])
    }

    func testWithinYearPastSortsDescending() {
        let today = "2026-06-18"
        let events = [makeEW("old", "2025-01-10"), makeEW("new", "2025-09-10")]

        let groups = groupEventsByYear(events, upcoming: false, todayKey: today)

        XCTAssertEqual(groups.map(\.year), ["2025年"])
        // 開催済みは新しい順。
        XCTAssertEqual(groups[0].events.map(\.id), ["new", "old"])
    }

    func testUnknownDateAppearsInUpcomingAtEndOnly() {
        let today = "2026-06-18"
        let events = [makeEW("a", "2026-07-01"), makeEW("unknown", nil)]

        let upcoming = groupEventsByYear(events, upcoming: true, todayKey: today)
        XCTAssertEqual(upcoming.map(\.year), ["2026年", "年度不明"]) // 年度不明は末尾

        let past = groupEventsByYear(events, upcoming: false, todayKey: today)
        XCTAssertFalse(past.contains { $0.year == "年度不明" }) // 開催済みには出ない
    }
}
