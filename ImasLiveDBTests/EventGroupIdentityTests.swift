import XCTest
@testable import ImasLiveDB

/// SwiftUI の `ForEach` は id が重複すると描画が破綻する (実機で恒久フリーズになりうる)。
/// ライブ一覧は年グループ × 行の入れ子 ForEach なので、両方の id 一意性を実データで守る。
final class EventGroupIdentityTests: XCTestCase {

    private func loadedCore() throws -> any EventReading {
        let manager = AppContainer.shared.coreSnapshot
        manager.requestLoad()
        let deadline = CFAbsoluteTimeGetCurrent() + 30
        while manager.storeIfLoaded == nil && CFAbsoluteTimeGetCurrent() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertNotNil(manager.storeIfLoaded, "スナップショットがロードできない")
        return AppContainer.shared.eventReading
    }

    func testNoDuplicateIdsInEventListForEach() async throws {
        let reading = try loadedCore()
        let events = try await reading.eventsWithFirstDate(
            brandId: nil, includeEmpty: true, liveOnly: false, kinds: EventKind.allCases)

        // 実機で固まる条件 (検索「初」) を含む複数の検索語で確かめる
        for term in ["", "初", "ライブ", "学園", "THE"] {
            var filter = EventFilterContext()
            filter.searchText = term
            let filtered = filterEvents(events, filter)

            for upcoming in [true, false] {
                let groups = groupEventsByYear(filtered, upcoming: upcoming, todayKey: JSTDay.today())

                // 外側 ForEach: 年グループの id (= year) が一意か
                let groupIds = groups.map(\.id)
                let dupGroups = Dictionary(grouping: groupIds, by: { $0 }).filter { $0.value.count > 1 }
                XCTAssertTrue(dupGroups.isEmpty,
                    "年グループ id が重複 term=\(term) upcoming=\(upcoming) 重複=\(dupGroups.keys.sorted())")

                // 内側 ForEach: 行の id (= event.id) がグループ内で一意か
                for g in groups {
                    let ids = g.events.map(\.id)
                    let dup = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }
                    XCTAssertTrue(dup.isEmpty,
                        "行 id が重複 term=\(term) upcoming=\(upcoming) year=\(g.year) 重複=\(dup.keys.sorted())")
                }
            }
        }
    }
}
