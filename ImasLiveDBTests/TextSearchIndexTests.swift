import XCTest
@testable import ImasLiveDB

/// 一覧の絞り込みに使う検索カタログ (`TextSearchCatalog`) の検査。
///
/// 判定本体 (バイト列前処理・部分列探索) は imas-core の
/// `domain/text_search_index.rs` に移り、そちらの Rust テストで固めてある
/// (生バイト列レベルの境界ケースも Rust 側)。ここで見るのは FFI 境界越しの
/// 当たり方 — nil 混じりフィールドの整形と index 列の解決 — が変わっていない
/// こと。ここが壊れると症状は「検索して 0 件」にしか出ず、原因が絞り込みなのか
/// データなのか切り分けられない。
final class TextSearchIndexTests: XCTestCase {

    /// 1 項目だけのカタログ。旧 `TextSearchIndex([...])` 相当。
    private func catalog(_ texts: String?...) -> TextSearchCatalog {
        TextSearchCatalog(fieldsPerItem: [texts])
    }

    /// 唯一の項目 (index 0) が当たるか。旧 `matches(Needle)` 相当。
    private func hit(_ catalog: TextSearchCatalog, _ query: String) -> Bool {
        catalog.matchingIndices(needle: query) == [0]
    }

    // MARK: - 基本

    func testMatchesSubstringAnywhere() {
        let c = catalog("夢色ハーモニー")
        XCTAssertTrue(hit(c, "夢"))       // 先頭
        XCTAssertTrue(hit(c, "ハーモ"))    // 途中
        XCTAssertTrue(hit(c, "ニー"))      // 末尾
        XCTAssertTrue(hit(c, "夢色ハーモニー"))  // 全体
        XCTAssertFalse(hit(c, "夢色ハーモニーズ"))  // 検索語の方が長い
        XCTAssertFalse(hit(c, "星"))
    }

    func testEmptyQueryMatchesEverything() {
        XCTAssertTrue(hit(catalog("READY!!"), ""))
        // 中身が無い曲でも空検索なら落とさない (絞り込みを掛けていない状態)
        XCTAssertTrue(hit(catalog(nil, ""), ""))
    }

    func testEmptyIndexNeverMatchesNonEmptyQuery() {
        XCTAssertFalse(hit(catalog(nil, ""), "夢"))
    }

    // MARK: - 複数フィールド

    func testMatchesAnyField() {
        let c = catalog("READY!!", "れでぃ")
        XCTAssertTrue(hit(c, "READY"))
        XCTAssertTrue(hit(c, "れでぃ"))
        XCTAssertFalse(hit(c, "GO"))
    }

    /// 連結して 1 本にすると境界をまたいだ偽の一致が起きる。分けて持つ理由。
    func testDoesNotMatchAcrossFieldBoundary() {
        XCTAssertFalse(hit(catalog("あい", "うえ"), "いう"))
    }

    // MARK: - 大文字小文字

    func testCaseInsensitiveForASCII() {
        let c = catalog("Crossing!")
        XCTAssertTrue(hit(c, "crossing"))
        XCTAssertTrue(hit(c, "CROSSING"))
        XCTAssertTrue(hit(c, "CrOsSiNg"))
    }

    /// かなの畳み込みは**しない**。既存の絞り込みと同じ当たり方を保つための境界。
    /// 緩めるなら Rust 側 (`domain/text_search_index.rs`) と検索側をまとめて変えること。
    func testDoesNotFoldKana() {
        XCTAssertFalse(hit(catalog("ツバサ"), "つばさ"))
        XCTAssertFalse(hit(catalog("ﾂﾊﾞｻ"), "ツバサ"))
    }

    // MARK: - バイト列探索の性質

    /// UTF-8 は先頭バイトと継続バイトの範囲が重ならないので、バイト一致が
    /// そのまま文字一致になる。途中のバイトから始まる偽の一致は起きない。
    func testNoFalseMatchInsideMultibyteCharacter() {
        // 「亜」= E4 BA 9C, 「介」= E4 BB 8B — 先頭バイトを共有する別の文字
        XCTAssertFalse(hit(catalog("亜"), "介"))
        // 継続バイトだけが一致する組み合わせでも当たらない
        XCTAssertFalse(hit(catalog("そら"), "らそ"))
    }

    func testMatchesEmojiAndCombiningCharacters() {
        let c = catalog("きらめき✨ 未来")
        XCTAssertTrue(hit(c, "✨"))
        XCTAssertTrue(hit(c, "✨ 未来"))
    }

    /// 部分一致の途中で外して、その先で当たる場合 (素朴な探索の巻き戻し)。
    /// 生バイト列レベルの境界ケースは Rust 側 `contains_edge_cases` にある。
    func testResumesAfterPartialMatch() {
        XCTAssertTrue(hit(catalog("aaab"), "aab"))
        XCTAssertTrue(hit(catalog("ababab"), "abab"))
        XCTAssertFalse(hit(catalog("ababa"), "abb"))
    }

    // MARK: - カタログ (index 列の解決)

    /// 当たった項目の index が入力順で返り、その添字で自国の配列を引ける。
    func testMatchingIndicesFollowInputOrder() {
        let c = TextSearchCatalog(fieldsPerItem: [
            ["夢色ハーモニー"],
            ["READY!!", "れでぃ"],
            [nil, ""],          // メタの無い曲
            ["Ready Go!"],
        ])
        XCTAssertEqual(c.matchingIndices(needle: "ready"), [1, 3])
        XCTAssertEqual(c.matchingIndices(needle: "夢"), [0])
        XCTAssertEqual(c.matchingIndices(needle: "星"), [])
        // 空の検索語は全項目 (メタの無い曲も落とさない)
        XCTAssertEqual(c.matchingIndices(needle: ""), [0, 1, 2, 3])
    }

    func testEmptyCatalogNeverMatches() {
        let c = TextSearchCatalog(fieldsPerItem: [])
        XCTAssertEqual(c.matchingIndices(needle: "夢"), [])
        XCTAssertEqual(c.matchingIndices(needle: ""), [])
    }

    // MARK: - 置き換え前との同値性

    /// 旧実装 (`lowercased().contains`) と同じ答えを返すこと。
    /// FFI 越し (Rust の `to_lowercase`) でも当たり方が変わらないことの確認。
    func testAgreesWithStringContains() {
        let haystacks = ["夢色ハーモニー", "READY!!", "Crossing!", "M@STERPIECE",
                         "きらめき✨", "ｱｲﾄﾞﾙ", "あいうえお", "1,2,3"]
        let needles = ["夢", "ready", "READY", "crossing", "@", "✨", "ｱｲ", "いう",
                       "3", "z", "ハーモニ", "M@S"]
        for haystack in haystacks {
            for needle in needles {
                let expected = haystack.lowercased().contains(needle.lowercased())
                XCTAssertEqual(hit(catalog(haystack), needle), expected,
                               "haystack=\(haystack) needle=\(needle)")
            }
        }
    }
}
