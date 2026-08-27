import XCTest
@testable import ImasLiveDB

/// 検索ハイライトの範囲 (`String.searchMatchRange(of:)`)。
///
/// 規則そのものはコア (imas-core `domain/text_search_index.rs`) が持っているので、
/// ここで見るのは **コアが返すバイト位置を Swift の String.Index に正しく移せているか**。
/// 多バイト文字だらけの日本語で 1 バイトずれると、色が半文字ずれるか範囲生成に失敗する。
final class SearchHighlightTests: XCTestCase {

    private func highlighted(_ text: String, _ needle: String) -> String? {
        text.searchMatchRange(of: needle).map { String(text[$0]) }
    }

    /// 回帰 (2026-08-27): 「おね」で一覧に出た「マリオネットの心」に色が付かなかった。
    /// コアはかなを畳むのに Swift 側が `range(of:)` で畳まずに探していた。
    func testHiraganaQueryHighlightsKatakana() {
        XCTAssertEqual(highlighted("マリオネットの心", "おね"), "オネ")
        XCTAssertEqual(highlighted("おねがい", "オネ"), "おね")
    }

    /// 先頭でも末尾でも、多バイト文字をまたいでも位置がずれない。
    func testRangeIsExactAcrossMultibyteText() {
        XCTAssertEqual(highlighted("夢色ハーモニー", "夢色"), "夢色")
        XCTAssertEqual(highlighted("夢色ハーモニー", "もにー"), "モニー")
        XCTAssertEqual(highlighted("お願い！シンデレラ", "しんでれら"), "シンデレラ")
    }

    /// 大文字小文字は畳む (従来どおり)。
    func testCaseIsFolded() {
        XCTAssertEqual(highlighted("READY!!", "ready"), "READY")
    }

    /// 当たらない語と空の語では範囲を返さない (色を敷かない)。
    func testNoRangeWithoutAHit() {
        XCTAssertNil(highlighted("夢色ハーモニー", "星空"))
        XCTAssertNil(highlighted("夢色ハーモニー", ""))
    }
}
