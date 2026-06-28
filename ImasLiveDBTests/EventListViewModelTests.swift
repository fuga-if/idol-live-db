import XCTest
@testable import ImasLiveDB

/// `EventListViewModel` のオーケストレーション (ポート取得 → 絞り込み + 年グルーピング) の単体テスト。
/// 絞り込み/グルーピング自体は `filterEvents` / `groupEventsByYear` でテスト済み。
/// ここでは VM が両者を繋いで `groupedByYear` / `filteredCount` を導出する配線を検証する。
@MainActor
final class EventListViewModelTests: XCTestCase {

    private enum FakeError: Error { case notUsed }

    // MARK: - Fakes

    private struct FakeEventReading: EventReading {
        var eventsToReturn: [EventWithDate] = []

        func eventsWithFirstDate(brandId: String?, includeEmpty: Bool, liveOnly: Bool, kinds: [EventKind]?) async throws -> [EventWithDate] {
            eventsToReturn
        }

        // 未使用メソッドは呼ばれない (このテストの load 経路では eventsWithFirstDate のみ)。
        func events(brandId: String?) async throws -> [Event] { [] }
        func event(id: String) async throws -> Event? { nil }
        func searchEventsByNameOrVenue(query: String, limit: Int) async throws -> [Event] { [] }
        func eventStats(eventId: String) async throws -> EventStats { throw FakeError.notUsed }
        func eventAttendance(eventId: String) async throws -> EventAttendance? { nil }
        func eventsWithDate(criterion: EventFilterCriterion, includeEmpty: Bool) async throws -> [EventWithDate] { [] }
        func eventNames() async throws -> [String] { [] }
        func attendedEventsWithDate() async throws -> [EventWithDate] { [] }
        func attendedEventTypeSets() async throws -> (live: Set<String>, stream: Set<String>, liveViewing: Set<String>) {
            ([], [], [])
        }
    }

    private struct FakeBrandReading: BrandReading {
        var brandsToReturn: [Brand] = []
        func brands() async throws -> [Brand] { brandsToReturn }
    }

    // MARK: - Fixtures

    private func makeEW(_ id: String, date: String?, brandId: String? = nil, name: String = "") -> EventWithDate {
        let event = Event(
            id: id, brandId: brandId, name: name.isEmpty ? "E\(id)" : name, eventType: "",
            isStreaming: false, isSolo: false, kind: "live",
            ticketOpenDate: nil, ticketDeadline: nil, ticketLotteryDate: nil,
            ticketUrl: nil, jointBrandIds: nil)
        return EventWithDate(event: event, firstDate: date, lastDate: date)
    }

    private func makeBrand(_ id: String) -> Brand {
        Brand(id: id, name: id, shortName: id, color: nil, sortOrder: 0, iconUrl: nil)
    }

    private func makeVM(events: [EventWithDate], brands: [Brand] = []) -> EventListViewModel {
        EventListViewModel(
            eventReading: FakeEventReading(eventsToReturn: events),
            brandReading: FakeBrandReading(brandsToReturn: brands))
    }

    private func query(_ filter: EventFilterContext = EventFilterContext(), upcoming: Bool, today: String) -> EventListQuery {
        EventListQuery(filter: filter, upcoming: upcoming, todayKey: today)
    }

    // MARK: - Tests

    func testLoadGroupsPastByYearDescending() async {
        let events = [makeEW("a", date: "2025-03-01"), makeEW("b", date: "2024-12-01"), makeEW("future", date: "2026-07-01")]
        let vm = makeVM(events: events)

        await vm.loadData(includeEmpty: false, query: query(upcoming: false, today: "2026-06-18"))

        // 未来 (2026-07) は除外。年は降順。
        XCTAssertEqual(vm.groupedByYear.map(\.year), ["2025年", "2024年"])
        // filteredCount は表示対象 (= 過去2件) の合計。
        XCTAssertEqual(vm.filteredCount, 2)
    }

    func testLoadUpcomingKeepsFutureAscending() async {
        let events = [makeEW("a", date: "2026-07-01"), makeEW("past", date: "2025-01-01"), makeEW("c", date: "2026-06-20")]
        let vm = makeVM(events: events)

        await vm.loadData(includeEmpty: false, query: query(upcoming: true, today: "2026-06-18"))

        XCTAssertEqual(vm.groupedByYear.map(\.year), ["2026年"])
        XCTAssertEqual(vm.groupedByYear.first?.events.map(\.id), ["c", "a"])
        XCTAssertEqual(vm.filteredCount, 2)
    }

    func testRebuildAppliesBrandFilterWithoutRefetch() async {
        let events = [makeEW("a", date: "2025-03-01", brandId: "cg"), makeEW("b", date: "2025-04-01", brandId: "ml")]
        let vm = makeVM(events: events)
        await vm.loadData(includeEmpty: false, query: query(upcoming: false, today: "2026-06-18"))
        XCTAssertEqual(vm.filteredCount, 2)

        var filter = EventFilterContext()
        filter.selectedBrandIds = ["ml"]
        vm.rebuild(query: query(filter, upcoming: false, today: "2026-06-18"))

        XCTAssertEqual(vm.filteredCount, 1)
        XCTAssertEqual(vm.groupedByYear.flatMap { $0.events.map(\.id) }, ["b"])
    }
}
