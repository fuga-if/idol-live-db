import XCTest
@testable import ImasLiveDB

/// `groupEventsByYear` (純粋ロジック) の単体テスト。DB に依存しない。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class EventGroupingTests: XCTestCase {

    private func makeEW(_ id: String, _ date: String?) -> EventWithDate {
        let event = Event(
            id: id, brandId: nil, name: "E\(id)", eventType: "",
            isStreaming: false, isSolo: false, kind: "live",
            ticketOpenDate: nil, ticketDeadline: nil, ticketLotteryDate: nil,
            ticketUrl: nil, jointBrandIds: nil)
        return EventWithDate(event: event, firstDate: date, lastDate: date)
    }

    func testUnknownDateAppearsInUpcomingAtEndOnly() {
        let today = "2026-06-18"
        let events = [makeEW("a", "2026-07-01"), makeEW("unknown", nil)]

        let upcoming = groupEventsByYear(events, upcoming: true, todayKey: today)
        // 語は imas-core の UNKNOWN_YEAR が正 (2026-09 に「年度不明」から改めた。
        // ここに入るのは発表済みで日付だけ未定の予定なので「日程が未定」と言う)。
        XCTAssertEqual(upcoming.map(\.year), ["2026年", "日程未定"]) // 日程未定は末尾

        let past = groupEventsByYear(events, upcoming: false, todayKey: today)
        XCTAssertFalse(past.contains { $0.year == "日程未定" }) // 開催済みには出ない
    }
}
