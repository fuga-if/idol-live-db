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

    // MARK: - 幅ゼロのアンカー (行末の追っかけコール)

    /// 行末アンカーは `start == end == 行のスカラー数`。セル分割の終端と一致すること
    /// (ここがズレるとサーバの `end > lineLength` 検証に弾かれる)。
    func testTrailingAnchorSitsAtScalarCount() {
        let text = "ダミー歌詞のサンプル"
        let end = CallGuideText.scalarCount(of: text)
        XCTAssertEqual(end, 10)
        XCTAssertEqual(CallGuideText.cells(of: text).last?.scalarEnd, end)

        // 絵文字を含む行でも UTF-16 ではなくスカラー数で数える。
        let emoji = "あ😀い"
        XCTAssertEqual(CallGuideText.scalarCount(of: emoji), 3)
        XCTAssertEqual(CallGuideText.cells(of: emoji).last?.scalarEnd, 3)
    }

    /// 幅ゼロは切り出す文字が無い = `anchorText` は空文字。
    /// `slice` が nil を返すので、行内に敷くハイライトも作られない。
    func testTrailingAnchorSlicesToNothing() {
        let text = "ダミー歌詞のサンプル"
        let end = CallGuideText.scalarCount(of: text)
        XCTAssertNil(CallGuideText.slice(text, start: end, end: end))
        XCTAssertNil(CallGuideText.slice(text, start: 0, end: 0))
    }

    /// 幅ゼロのハイライトが混ざっても本文は 1 文字も欠けない (敷く範囲が無いので素通し)。
    func testAttributedIgnoresZeroWidthHighlight() {
        let text = "ダミー歌詞のサンプル"
        let end = CallGuideText.scalarCount(of: text)
        let highlights = [
            CallGuideText.Highlight(start: 0, end: 3, color: .red),
            CallGuideText.Highlight(start: end, end: end, color: .blue),  // 行末 (幅ゼロ)
        ]
        let attributed = CallGuideText.attributed(text, highlights: highlights)
        XCTAssertEqual(String(attributed.characters), text)
    }

    /// 幅ゼロのコールは「掛かる範囲を持たない」。表示側はこれを見てハイライトを敷かない。
    func testZeroWidthCallHasNoAnchor() {
        let ranged = makeCall(start: 0, end: 3, anchorText: "ダミー")
        let trailing = makeCall(start: 10, end: 10, anchorText: "")
        XCTAssertTrue(ranged.hasAnchor)
        XCTAssertFalse(trailing.hasAnchor)
    }

    /// 幅ゼロは `anchorText` が常に空なのでズレようがない。
    /// サーバが誤って印を付けて返しても、選び直しを迫らないこと。
    func testZeroWidthCallIsNeverStale() {
        XCTAssertTrue(makeCall(start: 0, end: 3, anchorText: "ダミー", stale: true).isStale)
        XCTAssertFalse(makeCall(start: 10, end: 10, anchorText: "", stale: true).isStale)
    }

    /// 幅ゼロには被せる相手が無いので「同時」にはならない (サーバも after に倒す)。
    func testZeroWidthCallIsNeverOverlapping() {
        XCTAssertTrue(makeCall(start: 0, end: 3, anchorText: "ダミー", timing: .over).isOverlapping)
        XCTAssertFalse(makeCall(start: 0, end: 3, anchorText: "ダミー", timing: .after).isOverlapping)
        XCTAssertFalse(makeCall(start: 10, end: 10, anchorText: "", timing: .over).isOverlapping)
    }

    /// `timing` が無い応答 (旧サーバ) は追っかけ扱い。未知の値も落とさず追っかけに倒す。
    func testTimingDecodingFallsBackToAfter() throws {
        func decode(_ json: String) throws -> LyricCall {
            try JSONDecoder().decode(LyricCall.self, from: Data(json.utf8))
        }
        XCTAssertEqual(try decode(#"{"id":"c1","start":0,"end":3,"text":"(Hi!)"}"#).timing, .after)
        XCTAssertEqual(try decode(#"{"id":"c1","start":0,"end":3,"text":"(Hi!)","timing":"over"}"#).timing, .over)
        XCTAssertEqual(try decode(#"{"id":"c1","start":0,"end":3,"text":"(Hi!)","timing":"???"}"#).timing, .after)
    }

    /// 送信型に詰め替えるとき、幅ゼロの `timing` は必ず "after" に揃う
    /// (サーバの正規化と食い違わせない)。
    func testPayloadForcesAfterForZeroWidth() {
        let overRanged = CallGuidePayload.Call(makeCall(start: 0, end: 3, anchorText: "ダミー",
                                                        timing: .over))
        XCTAssertEqual(overRanged.timing, "over")
        let overTrailing = CallGuidePayload.Call(makeCall(start: 10, end: 10, anchorText: "",
                                                          timing: .over))
        XCTAssertEqual(overTrailing.timing, "after")
        XCTAssertEqual(overTrailing.anchorText, "")
    }

    // MARK: - なぞって選ぶときの当たり判定

    /// 折り返した 2 行ぶんのセル矩形。上段が 0〜2、下段が 3〜4 (下段は途中で終わる)。
    private var wrappedFrames: [Int: CGRect] {
        var frames: [Int: CGRect] = [:]
        for i in 0..<3 { frames[i] = CGRect(x: CGFloat(i) * 20, y: 0, width: 20, height: 30) }
        for i in 3..<5 { frames[i] = CGRect(x: CGFloat(i - 3) * 20, y: 34, width: 20, height: 30) }
        return frames
    }

    /// 矩形の中にいるときはそのセル。
    func testCellIndexHitsContainingCell() {
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 10, y: 15), in: wrappedFrames), 0)
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 50, y: 15), in: wrappedFrames), 2)
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 30, y: 45), in: wrappedFrames), 4)
    }

    /// 折り返した行の**行末より右**に指がいても、その行の最後のセルに寄る
    /// (上の行に飛ばない = なぞりが 1 行ぶんワープしない)。
    func testCellIndexSnapsToSameRowWhenPastLineEnd() {
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 300, y: 45), in: wrappedFrames), 4,
                       "下段の右の余白 → 下段の最後のセル")
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 300, y: 15), in: wrappedFrames), 2,
                       "上段の右の余白 → 上段の最後のセル")
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: -50, y: 45), in: wrappedFrames), 3,
                       "行頭より左 → その行の先頭のセル")
    }

    /// 行間の隙間や行の上下にはみ出した位置でも、最も近いセルに寄って nil にはしない
    /// (なぞっている最中に選択が途切れるのを防ぐ)。
    func testCellIndexFallsBackToNearestCell() {
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 10, y: 32), in: wrappedFrames), 0,
                       "行間の隙間 → 直上のセル")
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 10, y: -100), in: wrappedFrames), 0,
                       "行の上 → 上段の同じ列")
        XCTAssertEqual(CallGuideText.cellIndex(at: CGPoint(x: 10, y: 999), in: wrappedFrames), 3,
                       "行の下 → 下段の同じ列")
    }

    /// セルが 1 つも無い (空行) なら nil。
    func testCellIndexWithoutFramesIsNil() {
        XCTAssertNil(CallGuideText.cellIndex(at: .zero, in: [:]))
    }

    private func makeCall(start: Int, end: Int, anchorText: String,
                          timing: CallTiming = .after, stale: Bool? = nil) -> LyricCall {
        LyricCall(id: "c_test", start: start, end: end, anchorText: anchorText,
                  text: "(Hi!)", emphasis: .normal, timing: timing, stale: stale)
    }
}

/// タップでアンカーを選ぶときの「語のまとまり」(`imas-core` の `lyric_chunks`) が
/// FFI 越しに期待どおり返ることの確認。
///
/// 1 タップで語を確定する導線に変えたので、ここがズレると「押した語と違う範囲が
/// 選ばれる」という一番気付きにくい壊れ方をする。切れ目の規則そのものは Rust 側の
/// テストが持っているので、ここでは**バインディングが繋がっていること**と、
/// アンカーがスカラー単位のままであることだけを押さえる。
final class LyricChunkBridgeTests: XCTestCase {

    func testTappingAnyCharacterOfAWordSelectsTheWholeWord() {
        let line = "ダミー歌詞のサンプル行です"
        // 「歌詞」は 3..<5。どちらの文字を触っても同じまとまりが返る。
        for scalar in [UInt32(3), UInt32(4)] {
            let chunk = lyricChunkAt(line: line, scalar: scalar)
            XCTAssertEqual(chunk?.text, "歌詞", "scalar=\(scalar)")
            XCTAssertEqual(chunk?.start, 3)
            XCTAssertEqual(chunk?.end, 5)
        }
    }

    func testAnchorOffsetsStayScalarBasedAcrossTheBridge() {
        // 絵文字を含む行。UTF-16 で数えていると 1 文字ぶんズレる。
        let line = "あ😀いろは"
        XCTAssertEqual(line.unicodeScalars.count, 5)
        XCTAssertEqual(line.utf16.count, 6)
        let chunk = lyricChunkAt(line: line, scalar: 2)
        XCTAssertEqual(chunk?.text, "いろは")
        XCTAssertEqual(chunk?.start, 2, "UTF-16 で数えていると 3 になる")
    }

    func testTapPastTheEndOfTheLineStillSelectsSomething() {
        // 行の右端の余白を触っても空振りしない (指は文字ちょうどには乗らない)。
        XCTAssertEqual(lyricChunkAt(line: "ダミー歌詞", scalar: 99)?.text, "歌詞")
    }

    func testChunksCoverTheLineWithoutGaps() {
        // アンカーの計算がズレないこと。実際の歌詞にありがちな並びで確かめる。
        for line in ["キミが好きだよ、ずっと", "Shiny Days！", "ミュージック・アワー"] {
            let got = lyricChunks(line: line)
            XCTAssertEqual(got.first?.start, 0, line)
            XCTAssertEqual(got.last?.end, UInt32(line.unicodeScalars.count), line)
            for (a, b) in zip(got, got.dropFirst()) {
                XCTAssertEqual(a.end, b.start, line)
            }
        }
    }
}
