import XCTest
@testable import ImasLiveDB

/// `filterEvents` (純粋ロジック) の単体テスト。DB に依存しない。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class EventListFilteringTests: XCTestCase {

    private func makeEW(_ id: String, name: String = "", brandId: String? = nil, kind: String = "live") -> EventWithDate {
        let event = Event(
            id: id, brandId: brandId, name: name.isEmpty ? "E\(id)" : name, eventType: "",
            isStreaming: false, isSolo: false, kind: kind,
            ticketOpenDate: nil, ticketDeadline: nil, ticketLotteryDate: nil,
            ticketUrl: nil, jointBrandIds: nil)
        return EventWithDate(event: event, firstDate: "2026-01-01", lastDate: "2026-01-01")
    }

    // MARK: - 会場

    func testVenueCombinesWithBrandAsAnd() {
        let events = [makeEW("a", brandId: "cg"), makeEW("b", brandId: "ml"), makeEW("c", brandId: "cg")]
        var ctx = EventFilterContext()
        ctx.selectedBrandIds = ["cg"]
        ctx.venue = "東京・日本武道館"
        ctx.venueEventIds = ["b", "c"]
        XCTAssertEqual(filterEvents(events, ctx).map(\.id), ["c"])
    }
}
