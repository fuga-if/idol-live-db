import XCTest
@testable import ImasLiveDB

/// `ShortYearMonth` の単体テスト。
/// 統計タイルは 3 つ横並びなので、短縮に失敗すると即レイアウト崩れになる。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
final class ShortYearMonthTests: XCTestCase {

    func testFullDateBecomesShortYearMonth() {
        XCTAssertEqual(ShortYearMonth.format("2024-08-03"), "24.08")
    }
}
