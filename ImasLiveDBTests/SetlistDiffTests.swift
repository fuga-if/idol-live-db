import XCTest
@testable import ImasLiveDB

/// `SetlistDiff` の単体テスト。
///
/// ここが取りこぼすと「直したつもりが直っていない」になる。特に
/// 削除・section のクリア・並べ替えは落としやすいので個別に固定する。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
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

    // MARK: - item: 落としやすいケース

    /// section を「本編」に戻した (非 nil → nil) 。
    /// これを取りこぼすとアンコール表記が消えないまま残る。
    func testSectionClearIsSent() {
        let items = [item("a", song: "s1", pos: 1, section: nil)]
        let original = ["a": snap("s1", 1, "アンコール")]
        XCTAssertEqual(SetlistDiff.itemsNeedingSync(items: items, original: original).map(\.id), ["a"])
    }

    // MARK: - 出演者

    /// 追加された出演者だけ送る。
    func testOnlyAddedPerformersAreSent() {
        let performers = [performer("a", "i1"), performer("a", "NEW")]
        let initial: Set<String> = ["a_i1"]
        XCTAssertEqual(
            SetlistDiff.performersNeedingSync(
                performers: performers, initialRecordNames: initial, recordName: name).map(\.idolId),
            ["NEW"])
    }

    // MARK: - 実データ相当での削減幅

}
