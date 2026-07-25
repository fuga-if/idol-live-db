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

    // MARK: - 会場

    func testVenueFilterKeepsOnlyEventsAtThatVenue() {
        let events = [makeEW("a"), makeEW("b"), makeEW("c")]
        var ctx = EventFilterContext()
        ctx.venue = "東京・日本武道館"
        ctx.venueEventIds = ["a", "c"]
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["a", "c"])
    }

    func testEmptyVenueDoesNotFilter() {
        let events = [makeEW("a"), makeEW("b")]
        var ctx = EventFilterContext()
        // 会場名が空なら、解決済み集合が空でも絞り込みは効かない
        // (「未選択」と「その会場に該当なし」を取り違えて全件消さないこと)。
        ctx.venue = ""
        ctx.venueEventIds = []
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["a", "b"])
    }

    func testVenueWithNoMatchesYieldsEmpty() {
        let events = [makeEW("a"), makeEW("b")]
        var ctx = EventFilterContext()
        ctx.venue = "存在しない会場"
        ctx.venueEventIds = []
        XCTAssertTrue(filterEvents(events, ctx).isEmpty)
    }

    func testVenueCombinesWithBrandAsAnd() {
        let events = [makeEW("a", brandId: "cg"), makeEW("b", brandId: "ml"), makeEW("c", brandId: "cg")]
        var ctx = EventFilterContext()
        ctx.selectedBrandIds = ["cg"]
        ctx.venue = "東京・日本武道館"
        ctx.venueEventIds = ["b", "c"]
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["c"])
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
