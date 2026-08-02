import XCTest
@testable import ImasLiveDB

/// `SetlistDiff` の単体テスト。
///
/// ここが取りこぼすと「直したつもりが直っていない」になる。特に
/// 削除・section のクリア・並べ替えは落としやすいので個別に固定する。
final class SetlistDiffTests: XCTestCase {

    private func item(_ id: String, song: String, pos: Int, section: String? = nil) -> SetlistItem {
        SetlistItem(id: id, showId: "shw_1", songId: song, position: pos,
                    section: section, notes: nil, unitName: nil)
    }

    private func snap(_ song: String, _ pos: Int, _ section: String? = nil) -> SetlistItemSnapshot {
        SetlistItemSnapshot(songId: song, position: pos, section: section)
    }

    private func performer(_ itemId: String, _ idolId: String) -> SetlistPerformer {
        SetlistPerformer(setlistItemId: itemId, idolId: idolId)
    }

    private func name(_ p: SetlistPerformer) -> String { "\(p.setlistItemId)_\(p.idolId)" }

    // MARK: - item: 変わっていないものは送らない

    /// 何も編集していなければ 0 件。ここが 0 にならないと差分化の意味がない。
    func testUnchangedSetlistProducesNothing() {
        let items = [item("a", song: "s1", pos: 1), item("b", song: "s2", pos: 2)]
        let original = ["a": snap("s1", 1), "b": snap("s2", 2)]
        XCTAssertTrue(SetlistDiff.itemsNeedingSync(items: items, original: original).isEmpty)
    }

    /// 1 曲だけ差し替えたら 1 件だけ送る。
    func testOnlyChangedSongIsSent() {
        let items = [item("a", song: "s1", pos: 1), item("b", song: "CHANGED", pos: 2)]
        let original = ["a": snap("s1", 1), "b": snap("s2", 2)]
        XCTAssertEqual(SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id), ["b"])
    }

    /// 新規追加 (スナップショットに無い id) は必ず送る。
    func testNewItemIsAlwaysSent() {
        let items = [item("a", song: "s1", pos: 1), item("new", song: "s9", pos: 2)]
        let original = ["a": snap("s1", 1)]
        XCTAssertEqual(SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id), ["new"])
    }

    // MARK: - item: 落としやすいケース

    /// section を付けた / 変えた。
    func testSectionChangeIsSent() {
        let items = [item("a", song: "s1", pos: 1, section: "アンコール")]
        let original = ["a": snap("s1", 1, nil)]
        XCTAssertEqual(SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id), ["a"])
    }

    /// section を「本編」に戻した (非 nil → nil) 。
    /// これを取りこぼすとアンコール表記が消えないまま残る。
    func testSectionClearIsSent() {
        let items = [item("a", song: "s1", pos: 1, section: nil)]
        let original = ["a": snap("s1", 1, "アンコール")]
        XCTAssertEqual(SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id), ["a"])
    }

    /// 並べ替えは position が動いた曲すべてを送る (動いていない曲は送らない)。
    func testReorderSendsOnlyMovedItems() {
        // a(1) b(2) c(3) → b と c を入れ替え
        let items = [item("a", song: "s1", pos: 1), item("c", song: "s3", pos: 2), item("b", song: "s2", pos: 3)]
        let original = ["a": snap("s1", 1), "b": snap("s2", 2), "c": snap("s3", 3)]
        XCTAssertEqual(
            Set(SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id)),
            ["b", "c"])
    }

    /// 曲は同じでも位置が変わっていれば送る。
    func testPositionOnlyChangeIsSent() {
        let items = [item("a", song: "s1", pos: 5)]
        let original = ["a": snap("s1", 1)]
        XCTAssertEqual(SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id), ["a"])
    }

    /// 出力順は入力のまま (position 順に並べた呼び出し側の意図を壊さない)。
    func testKeepsInputOrder() {
        let items = (1...5).map { item("i\($0)", song: "changed\($0)", pos: $0) }
        let original = Dictionary(uniqueKeysWithValues: (1...5).map { ("i\($0)", snap("s\($0)", $0)) })
        XCTAssertEqual(
            SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id),
            ["i1", "i2", "i3", "i4", "i5"])
    }

    // MARK: - 出演者

    /// 既存の出演者は 1 件も送らない。
    ///
    /// SetlistPerformer は (setlistItemId, idolId) しか持たず recordName がその 2 つから
    /// 決まるので、update しても変化しようがない。ここが差分化でいちばん効く。
    func testExistingPerformersAreNeverSent() {
        let performers = [performer("a", "i1"), performer("a", "i2"), performer("b", "i1")]
        let initial: Set<String> = ["a_i1", "a_i2", "b_i1"]
        XCTAssertTrue(
            SetlistDiff.performersNeedingSync(
                performers: performers, initialRecordNames: initial, recordName: name).isEmpty)
    }

    /// 追加された出演者だけ送る。
    func testOnlyAddedPerformersAreSent() {
        let performers = [performer("a", "i1"), performer("a", "NEW")]
        let initial: Set<String> = ["a_i1"]
        XCTAssertEqual(
            SetlistDiff.performersNeedingSync(
                performers: performers, initialRecordNames: initial, recordName: name).map(\.idolId),
            ["NEW"])
    }

    /// 出演者ゼロから付け直したケース (全員新規)。
    func testAllPerformersNewWhenNothingExisted() {
        let performers = [performer("a", "i1"), performer("a", "i2")]
        XCTAssertEqual(
            SetlistDiff.performersNeedingSync(
                performers: performers, initialRecordNames: [], recordName: name).count, 2)
    }

    // MARK: - 実データ相当での削減幅

    /// 実測最大級のセトリ (86曲 × 出演者6) で 1 曲だけ直したとき、
    /// 606 ops 相当が 1 件まで落ちること。
    func testLargeSetlistWithSingleEditCollapsesToOneOp() {
        var items: [SetlistItem] = []
        var original: [String: SetlistItemSnapshot] = [:]
        var performers: [SetlistPerformer] = []
        var initialNames: Set<String> = []
        for i in 1...86 {
            let id = "i\(i)"
            items.append(item(id, song: "song\(i)", pos: i))
            original[id] = snap("song\(i)", i)
            for p in 1...6 {
                performers.append(performer(id, "idol\(p)"))
                initialNames.insert("\(id)_idol\(p)")
            }
        }
        XCTAssertEqual(items.count + performers.count, 602, "前提: 600 ops 規模")

        // 42曲目だけ曲を差し替える
        items[41].songId = "CORRECTED"

        let changedItems = SetlistDiff.itemsNeedingSync(items: items, original: original)
        let changedPerformers = SetlistDiff.performersNeedingSync(
            performers: performers, initialRecordNames: initialNames, recordName: name)

        XCTAssertEqual(changedItems.map(\.id), ["i42"])
        XCTAssertTrue(changedPerformers.isEmpty)
        XCTAssertEqual(changedItems.count + changedPerformers.count, 1)
    }
}
