import XCTest
@testable import ImasLiveDB

/// 情報ウィジェットの日付の扱いのテスト。
///
/// ウィジェットはアプリを開かない日が続くと、過ぎたライブに「あと-2日」と出していた
/// (作った日を見ていなかった)。日付の基準も端末の地域設定のままで、JST のアプリ本体とずれた。
final class WidgetDayTests: XCTestCase {

    /// 2026-09-23 00:30 (JST)。
    private let now = Date(timeIntervalSince1970: 1_790_091_000)

    /// ウィジェットの「今日」は、コアの JST の「今日」と同じ表記になる (日付の境目を含む)。
    func testKeyMatchesCoreJSTToday() {
        let jstMidnight: TimeInterval = 1_790_089_200  // 2026-09-23 00:00:00 (JST)
        // 前日・0 時の前後・UTC の 0 時 (JST 9 時) の前後・JST の 24 時 (次の日) の前後。
        let offsets: [TimeInterval] = [-86_400, -1, 0, 1, 32_399, 32_400, 86_399, 86_400]
        for offset in offsets {
            let date = Date(timeIntervalSince1970: jstMidnight + offset)
            XCTAssertEqual(WidgetDay.key(date), JSTDay.today(now: date), "offset=\(offset)")
        }
        XCTAssertEqual(WidgetDay.key(now), "2026-09-23")
    }

    func testDaysUntilCountsJSTDays() {
        XCTAssertEqual(WidgetDay.daysUntil("2026-09-23", from: now), 0)
        XCTAssertEqual(WidgetDay.daysUntil("2026-09-25", from: now), 2)
        XCTAssertEqual(WidgetDay.daysUntil("2026-09-22", from: now), -1)
        XCTAssertNil(WidgetDay.daysUntil("9月末", from: now))
    }

    /// 過ぎたライブは出さない。当日は出す (まだ終わっていない)。
    func testPastShowIsNotUpcoming() {
        func show(_ date: String) -> NextShowInfo {
            NextShowInfo(eventId: "e", eventName: "e", firstDate: date, brandColorHex: nil)
        }
        XCTAssertTrue(show("2026-09-23").isUpcoming(from: now))
        XCTAssertFalse(show("2026-09-21").isUpcoming(from: now))
    }

    /// 締切が過ぎたものは出さない。日付として読めない締切 (自由記述) は落とさない。
    func testPastDeadlineIsNotOpen() {
        func deadline(_ date: String) -> TicketDeadlineInfo {
            TicketDeadlineInfo(eventId: "e", eventName: "e", deadline: date)
        }
        XCTAssertTrue(deadline("2026-09-23").isOpen(from: now))
        XCTAssertFalse(deadline("2026-09-22").isOpen(from: now))
        XCTAssertTrue(deadline("9月末").isOpen(from: now))
    }

    /// 作った日 (JST) 以外のスナップショットは古いので出さない。
    func testSnapshotFromAnotherDayIsStale() {
        let snapshot = InfoWidgetSnapshot(nextShow: nil, todaySong: nil, ticketDeadlines: [], generatedDate: "2026-09-22")
        XCTAssertFalse(snapshot.isCurrent(now: now))
        XCTAssertTrue(snapshot.isCurrent(now: now.addingTimeInterval(-3_600)))  // 2026-09-22 23:30 (JST)
    }
}
