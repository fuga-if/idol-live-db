import XCTest
@testable import ImasLiveDB

/// `ShortYearMonth` の単体テスト。
/// 統計タイルは 3 つ横並びなので、短縮に失敗すると即レイアウト崩れになる。
final class ShortYearMonthTests: XCTestCase {

    func testFullDateBecomesShortYearMonth() {
        XCTAssertEqual(ShortYearMonth.format("2024-08-03"), "24.08")
    }

    /// 月のゼロ埋めは落とさない ("24.8" だと桁が揃わず並びが汚れる)。
    func testKeepsZeroPaddedMonth() {
        XCTAssertEqual(ShortYearMonth.format("2005-01-15"), "05.01")
    }

    /// 年月までしかない部分日付も短縮できる。
    func testYearMonthOnly() {
        XCTAssertEqual(ShortYearMonth.format("2024-08"), "24.08")
    }

    /// 短縮できない入力はそのまま返す (捏造しない)。
    func testUnsplittableInputPassesThrough() {
        XCTAssertEqual(ShortYearMonth.format("2024"), "2024")
        XCTAssertEqual(ShortYearMonth.format(""), "")
        XCTAssertEqual(ShortYearMonth.format("未定"), "未定")
    }
}
