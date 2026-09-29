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
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
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

    // MARK: - 複数フィールド

    // MARK: - 大文字小文字

    // MARK: - バイト列探索の性質

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

    // MARK: - 置き換え前との同値性

}
