import XCTest
@testable import ImasLiveDB

/// `JSTDay` の単体テスト。
/// 「今日」の判定が端末のタイムゾーンに引きずられないこと、日付境界が JST 基準であることを見る。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
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

    /// 呼ぶたびに計算する (static let でキャッシュすると日付が変わっても古いままになる)。
    func testTodayIsRecomputedPerCall() {
        let before = JSTDay.today(now: utc(2026, 7, 26, 14, 0))
        let after = JSTDay.today(now: utc(2026, 7, 26, 15, 0))
        XCTAssertEqual(before, "2026-07-26")
        XCTAssertEqual(after, "2026-07-27")
    }

    // MARK: - isTodayOrLater

    /// ハワイにいても、日本で今日の公演は「未来」のまま。
    func testSameDayIsFutureEvenWhenDeviceIsBehindJST() {
        // UTC 2026-07-26 01:00 = ハワイ 07-25 15:00
        XCTAssertTrue(JSTDay.isTodayOrLater("2026-07-26", now: utc(2026, 7, 26, 1, 0)))
    }
}
