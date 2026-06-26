import XCTest
@testable import ImasLiveDB

/// `filterEvents` (純粋ロジック) の単体テスト。DB に依存しない。
final class EventListFilteringTests: XCTestCase {

    private func makeEW(_ id: String, name: String = "", brandId: String? = nil, kind: String = "live") -> EventWithDate {
        let event = Event(
            id: id, brandId: brandId, name: name.isEmpty ? "E\(id)" : name, eventType: "",
            isStreaming: false, isSolo: false, kind: kind,
            ticketOpenDate: nil, ticketDeadline: nil, ticketLotteryDate: nil,
            ticketUrl: nil, jointBrandIds: nil)
        return EventWithDate(event: event, firstDate: "2026-01-01", lastDate: "2026-01-01")
    }

    func testEmptyContextPassesThrough() {
        let events = [makeEW("a"), makeEW("b")]
        XCTAssertEqual(filterEvents(events, EventFilterContext()).map(\.id), ["a", "b"])
    }

    func testBrandFilter() {
        let events = [makeEW("a", brandId: "cg"), makeEW("b", brandId: "ml")]
        var ctx = EventFilterContext()
        ctx.selectedBrandIds = ["cg"]
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["a"])
    }

    func testSearchTextCaseInsensitive() {
        let events = [makeEW("a", name: "SHINY COLORS"), makeEW("b", name: "MILLION")]
        var ctx = EventFilterContext()
        ctx.searchText = "shiny"
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["a"])
    }

    func testAttendedFilter() {
        let events = [makeEW("a"), makeEW("b")]
        var ctx = EventFilterContext()
        ctx.attendanceFilter = "attended"
        ctx.attendedEventIds = ["b"]
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["b"])
    }

    func testNotAttendedFilter() {
        let events = [makeEW("a"), makeEW("b")]
        var ctx = EventFilterContext()
        ctx.attendanceFilter = "not_attended"
        ctx.attendedEventIds = ["b"]
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["a"])
    }

    func testFavoriteAndNoteAreAndConditions() {
        let events = [makeEW("a"), makeEW("b"), makeEW("c")]
        var ctx = EventFilterContext()
        ctx.requireFavorite = true
        ctx.favoriteIds = ["a", "b"]
        ctx.requireNote = true
        ctx.noteIds = ["b", "c"]
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["b"])
    }
}
