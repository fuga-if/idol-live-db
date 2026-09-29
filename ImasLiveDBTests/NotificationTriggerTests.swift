import UserNotifications
import XCTest
@testable import ImasLiveDB

/// 通知の予定 1 件をトリガーに詰めるところ (`NotificationService.trigger(for:)`)。
/// 何を・いつ積むかはコアの予定表。ここはくり返すかどうかの登録の仕方だけを見る。
final class NotificationTriggerTests: XCTestCase {

    private func item(date: String, hour: UInt32, repeatsYearly: Bool) -> PlannedNotificationRecord {
        PlannedNotificationRecord(
            id: "x", kind: .oshiBirthday, title: "t", body: nil, date: date,
            hour: hour, minute: 0, imageIdolId: nil, repeatsYearly: repeatsYearly)
    }

    /// 2/29 以外の誕生日は、年を持たない月日で毎年くり返す (アプリを開かない年も鳴る)。
    func testYearlyItemRepeatsOnMonthDayWithoutYear() {
        let trigger = NotificationService.trigger(for: item(date: "2026-04-03", hour: 9, repeatsYearly: true))
        XCTAssertTrue(trigger.repeats)
        XCTAssertNil(trigger.dateComponents.year)
        XCTAssertEqual(trigger.dateComponents.month, 4)
        XCTAssertEqual(trigger.dateComponents.day, 3)
        XCTAssertEqual(trigger.dateComponents.hour, 9)
    }

    /// それ以外 (2/29 生まれ・月曜・ライブ・チケット) は、返された日付に 1 回だけ。
    func testOneOffItemFiresOnceOnTheGivenDate() {
        let trigger = NotificationService.trigger(for: item(date: "2027-02-28", hour: 9, repeatsYearly: false))
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.dateComponents.year, 2027)
        XCTAssertEqual(trigger.dateComponents.month, 2)
        XCTAssertEqual(trigger.dateComponents.day, 28)
    }
}

/// 再予約で今の予約をどうするか (`NotificationService.pendingUpdate`)。
final class NotificationPendingUpdateTests: XCTestCase {
    func testPlanFailureClearsOnlyAfterTurningOffOrWithoutPermission() {
        typealias S = NotificationService
        XCTAssertEqual(S.pendingUpdate(authorized: true, planBuilt: true, reason: .refresh), .replace)
        XCTAssertEqual(S.pendingUpdate(authorized: true, planBuilt: false, reason: .refresh), .keep)
        XCTAssertEqual(S.pendingUpdate(authorized: true, planBuilt: false, reason: .settingTurnedOff), .clear)
        XCTAssertEqual(S.pendingUpdate(authorized: false, planBuilt: false, reason: .refresh), .clear)
    }
}
