import XCTest
@testable import ImasLiveDB

/// `JSTDay` の単体テスト。
/// 「今日」の判定が端末のタイムゾーンに引きずられないこと、日付境界が JST 基準であることを見る。
final class JSTDayTests: XCTestCase {

    /// UTC の絶対時刻から Date を作る (端末 TZ に依存しない固定値)。
    private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: c)!
    }

    // MARK: - today

    /// JST 15:00 (= UTC 06:00) は当然その日。
    func testTodayInMiddleOfJSTDay() {
        XCTAssertEqual(JSTDay.today(now: utc(2026, 7, 26, 6, 0)), "2026-07-26")
    }

    /// JST 00:01 (= 前日 UTC 15:01) は既に翌日扱い。
    func testTodayJustAfterJSTMidnight() {
        XCTAssertEqual(JSTDay.today(now: utc(2026, 7, 25, 15, 1)), "2026-07-26")
    }

    /// JST 23:59 (= UTC 14:59) はまだその日。
    func testTodayJustBeforeJSTMidnight() {
        XCTAssertEqual(JSTDay.today(now: utc(2026, 7, 26, 14, 59)), "2026-07-26")
    }

    /// ハワイ (UTC-10) では現地 7/25 だが、JST では 7/26。
    /// 端末 TZ に引きずられると日本で終わった公演が「これから」に出てしまう。
    func testTodayIsJSTRegardlessOfDeviceTimeZone() {
        // UTC 2026-07-26 01:00 = ハワイ 07-25 15:00 = JST 07-26 10:00
        XCTAssertEqual(JSTDay.today(now: utc(2026, 7, 26, 1, 0)), "2026-07-26")
    }

    /// 月またぎ / 年またぎでもゼロ埋め書式が崩れない。
    func testTodayFormatAcrossBoundaries() {
        XCTAssertEqual(JSTDay.today(now: utc(2025, 12, 31, 15, 0)), "2026-01-01")
        XCTAssertEqual(JSTDay.today(now: utc(2026, 1, 8, 15, 0)), "2026-01-09")
    }

    /// 呼ぶたびに計算する (static let でキャッシュすると日付が変わっても古いままになる)。
    func testTodayIsRecomputedPerCall() {
        let before = JSTDay.today(now: utc(2026, 7, 26, 14, 0))
        let after = JSTDay.today(now: utc(2026, 7, 26, 15, 0))
        XCTAssertEqual(before, "2026-07-26")
        XCTAssertEqual(after, "2026-07-27")
    }

    // MARK: - isTodayOrLater

    /// 開催日当日はまだ終わっていないので「未来」扱い。
    func testSameDayCountsAsFuture() {
        XCTAssertTrue(JSTDay.isTodayOrLater("2026-07-26", now: utc(2026, 7, 26, 6, 0)))
    }

    func testPastDateIsNotFuture() {
        XCTAssertFalse(JSTDay.isTodayOrLater("2026-07-25", now: utc(2026, 7, 26, 6, 0)))
    }

    func testFutureDateIsFuture() {
        XCTAssertTrue(JSTDay.isTodayOrLater("2026-08-01", now: utc(2026, 7, 26, 6, 0)))
    }

    /// 日付未定 (空文字) は未来にしない。
    func testEmptyDateIsNotFuture() {
        XCTAssertFalse(JSTDay.isTodayOrLater("", now: utc(2026, 7, 26, 6, 0)))
    }

    /// ハワイにいても、日本で今日の公演は「未来」のまま。
    func testSameDayIsFutureEvenWhenDeviceIsBehindJST() {
        // UTC 2026-07-26 01:00 = ハワイ 07-25 15:00
        XCTAssertTrue(JSTDay.isTodayOrLater("2026-07-26", now: utc(2026, 7, 26, 1, 0)))
    }
}
