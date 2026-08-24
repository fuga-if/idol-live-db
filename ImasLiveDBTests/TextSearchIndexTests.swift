import XCTest
@testable import ImasLiveDB

/// 一覧の絞り込みに使う部分列探索 (`TextSearchIndex`) の検査。
///
/// `String.contains` を自前のバイト列探索に置き換えたので、当たり方が
/// 変わっていないことを固めておく。ここが壊れると症状は「検索して 0 件」
/// にしか出ず、原因が絞り込みなのかデータなのか切り分けられない。
final class TextSearchIndexTests: XCTestCase {

    private func index(_ texts: String?...) -> TextSearchIndex {
        TextSearchIndex(texts)
    }

    private func hit(_ index: TextSearchIndex, _ query: String) -> Bool {
        index.matches(TextSearchIndex.Needle(query))
    }

    // MARK: - 基本

    func testMatchesSubstringAnywhere() {
        let i = index("夢色ハーモニー")
        XCTAssertTrue(hit(i, "夢"))       // 先頭
        XCTAssertTrue(hit(i, "ハーモ"))    // 途中
        XCTAssertTrue(hit(i, "ニー"))      // 末尾
        XCTAssertTrue(hit(i, "夢色ハーモニー"))  // 全体
        XCTAssertFalse(hit(i, "夢色ハーモニーズ"))  // 検索語の方が長い
        XCTAssertFalse(hit(i, "星"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(hit(index("READY!!"), ""))
        // 中身が無い曲でも空検索なら落とさない (絞り込みを掛けていない状態)
        XCTAssertTrue(hit(index(nil, ""), ""))
    }

    func testEmptyIndexNeverMatchesNonEmptyQuery() {
        XCTAssertFalse(hit(index(nil, ""), "夢"))
    }

    // MARK: - 複数フィールド

    func testMatchesAnyField() {
        let i = index("READY!!", "れでぃ")
        XCTAssertTrue(hit(i, "READY"))
        XCTAssertTrue(hit(i, "れでぃ"))
        XCTAssertFalse(hit(i, "GO"))
    }

    /// 連結して 1 本にすると境界をまたいだ偽の一致が起きる。分けて持つ理由。
    func testDoesNotMatchAcrossFieldBoundary() {
        XCTAssertFalse(hit(index("あい", "うえ"), "いう"))
    }

    // MARK: - 大文字小文字

    func testCaseInsensitiveForASCII() {
        let i = index("Crossing!")
        XCTAssertTrue(hit(i, "crossing"))
        XCTAssertTrue(hit(i, "CROSSING"))
        XCTAssertTrue(hit(i, "CrOsSiNg"))
    }

    /// かなの畳み込みは**しない**。既存の絞り込みと同じ当たり方を保つための境界。
    /// 緩めるならここを落として検索側とまとめて変えること。
    func testDoesNotFoldKana() {
        XCTAssertFalse(hit(index("ツバサ"), "つばさ"))
        XCTAssertFalse(hit(index("ﾂﾊﾞｻ"), "ツバサ"))
    }

    // MARK: - バイト列探索の性質

    /// UTF-8 は先頭バイトと継続バイトの範囲が重ならないので、バイト一致が
    /// そのまま文字一致になる。途中のバイトから始まる偽の一致は起きない。
    func testNoFalseMatchInsideMultibyteCharacter() {
        // 「亜」= E4 BA 9C, 「介」= E4 BB 8B — 先頭バイトを共有する別の文字
        XCTAssertFalse(hit(index("亜"), "介"))
        // 継続バイトだけが一致する組み合わせでも当たらない
        XCTAssertFalse(hit(index("そら"), "らそ"))
    }

    func testMatchesEmojiAndCombiningCharacters() {
        let i = index("きらめき✨ 未来")
        XCTAssertTrue(hit(i, "✨"))
        XCTAssertTrue(hit(i, "✨ 未来"))
    }

    /// 部分一致の途中で外して、その先で当たる場合 (素朴な探索の巻き戻し)。
    func testResumesAfterPartialMatch() {
        XCTAssertTrue(TextSearchIndex.contains(Array("aaab".utf8), Array("aab".utf8)))
        XCTAssertTrue(TextSearchIndex.contains(Array("ababab".utf8), Array("abab".utf8)))
        XCTAssertFalse(TextSearchIndex.contains(Array("ababa".utf8), Array("abb".utf8)))
    }

    func testContainsEdgeCases() {
        XCTAssertFalse(TextSearchIndex.contains([], [1]))
        XCTAssertFalse(TextSearchIndex.contains([1], []))       // 空の検索語はここでは false
        XCTAssertFalse(TextSearchIndex.contains([1, 2], [1, 2, 3]))
        XCTAssertTrue(TextSearchIndex.contains([1, 2, 3], [1, 2, 3]))
        XCTAssertTrue(TextSearchIndex.contains([1, 2, 3], [3]))
    }

    // MARK: - 置き換え前との同値性

    /// 旧実装 (`lowercased().contains`) と同じ答えを返すこと。
    func testAgreesWithStringContains() {
        let haystacks = ["夢色ハーモニー", "READY!!", "Crossing!", "M@STERPIECE",
                         "きらめき✨", "ｱｲﾄﾞﾙ", "あいうえお", "1,2,3"]
        let needles = ["夢", "ready", "READY", "crossing", "@", "✨", "ｱｲ", "いう",
                       "3", "z", "ハーモニ", "M@S"]
        for haystack in haystacks {
            for needle in needles {
                let expected = haystack.lowercased().contains(needle.lowercased())
                XCTAssertEqual(hit(index(haystack), needle), expected,
                               "haystack=\(haystack) needle=\(needle)")
            }
        }
    }
}
