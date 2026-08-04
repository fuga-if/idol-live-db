import XCTest
@testable import ImasLiveDB

/// コールのアンカー位置 (`start` / `end`) が **Unicode スカラー単位**であることの単体テスト。
///
/// ここがサーバ (Worker) との唯一の暗黙の取り決めで、UTF-16 (`NSRange` / `String.utf16`)
/// と取り違えると絵文字・結合文字を含む行だけアンカーが 1〜2 文字ズレる。目で見て気付き
/// にくく、しかもデータ側に間違った数値が残るので、境界だけは機械で押さえておく。
final class CallGuideTextTests: XCTestCase {

    /// 絵文字を含む行では UTF-16 とスカラーで数え方が食い違う。
    /// 食い違うこと自体を固定し、`cells` がスカラー側を返していることを保証する。
    func testScalarOffsetsDifferFromUTF16ForEmoji() {
        let text = "あ😀い"
        XCTAssertEqual(text.unicodeScalars.count, 3)
        XCTAssertEqual(text.utf16.count, 4, "😀 はサロゲートペアなので UTF-16 では 2")

        let cells = CallGuideText.cells(of: text)
        XCTAssertEqual(cells.map(\.text), ["あ", "😀", "い"])
        XCTAssertEqual(cells.map(\.scalarStart), [0, 1, 2])
        XCTAssertEqual(cells.map(\.scalarEnd), [1, 2, 3])
    }

    /// 結合文字 (家族絵文字) は 1 書記素クラスタだが複数スカラー。
    /// 選択は必ずクラスタ境界にスナップし、範囲の途中で切れないこと。
    func testCombiningSequenceIsOneCellSpanningMultipleScalars() {
        let text = "x👨‍👩‍👧y"
        let cells = CallGuideText.cells(of: text)
        XCTAssertEqual(cells.count, 3, "書記素クラスタ単位なので 3 セル")

        let family = cells[1]
        XCTAssertEqual(family.scalarStart, 1)
        XCTAssertTrue(family.scalarEnd > 2, "家族絵文字は複数スカラーを占める")
        // 次のセルは必ず前のセルの終端から始まる (隙間も重なりも無い)。
        XCTAssertEqual(cells[2].scalarStart, family.scalarEnd)
        XCTAssertEqual(cells[2].scalarEnd, CallGuideText.scalarCount(of: text))
    }

    /// `slice` はスカラー範囲をそのまま切り出す。アンカー文字列の組み立てに使う経路。
    func testSliceReturnsScalarRange() {
        let text = "ダミー歌詞のサンプル"
        XCTAssertEqual(CallGuideText.slice(text, start: 0, end: 3), "ダミー")
        XCTAssertEqual(CallGuideText.slice(text, start: 3, end: 5), "歌詞")
    }

    /// 壊れた範囲 (範囲外・逆転・空) は描かない。サーバ側の歌詞が編集されて
    /// アンカーが行の長さを超えたときに落ちないこと。
    func testSliceRejectsOutOfRangeOrInverted() {
        let text = "みじかい"
        XCTAssertNil(CallGuideText.slice(text, start: 0, end: 99))
        XCTAssertNil(CallGuideText.slice(text, start: 3, end: 1))
        XCTAssertNil(CallGuideText.slice(text, start: 2, end: 2))
        XCTAssertNil(CallGuideText.slice(text, start: -1, end: 2))
    }

    /// ハイライトを敷いても本文は 1 文字も欠けない/増えない (見た目だけの装飾であること)。
    /// 重なり合うアンカー・範囲外のアンカーが混ざっても同じ。
    func testAttributedPreservesPlainText() {
        let text = "ダミー歌詞のサンプル行です"
        let highlights = [
            CallGuideText.Highlight(start: 0, end: 3, color: .red),
            CallGuideText.Highlight(start: 2, end: 6, color: .green),   // 先勝ちで重複部分を捨てる
            CallGuideText.Highlight(start: 90, end: 99, color: .blue),  // 範囲外
        ]
        let attributed = CallGuideText.attributed(text, highlights: highlights)
        XCTAssertEqual(String(attributed.characters), text)
    }

    /// ハイライトが 1 つも無い行も、そのまま素通しする。
    func testAttributedWithoutHighlights() {
        let text = "コールの無い行"
        XCTAssertEqual(String(CallGuideText.attributed(text, highlights: []).characters), text)
    }
}
