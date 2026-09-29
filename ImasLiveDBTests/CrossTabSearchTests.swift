import XCTest
@testable import ImasLiveDB

/// タブを跨いだ検索の引き継ぎ (`CrossTabSearch`) の単体テスト。
///
/// 虫眼鏡 (`UnifiedSearchView`) を畳んだ代わりの導線なので、ここが壊れると
/// 「他のタブに N 件」を押しても何も起きない / 押していないのに語が入る、になる。
@MainActor
final class CrossTabSearchTests: XCTestCase {

    private var sut: CrossTabSearch { CrossTabSearch.shared }

    override func setUp() async throws {
        // 共有インスタンスなので、テスト間で持ち越さないよう毎回受け取り切る。
        for tab in RootTab.allCases { _ = sut.take(for: tab) }
    }

    /// 渡した先のタブだけが受け取れる。
    func testOnlyTheTargetTabTakesTheQuery() {
        sut.hand("あるすとろめりあ", to: .idols)

        XCTAssertNil(sut.take(for: .songs), "宛先でないタブは受け取らない")
        XCTAssertNil(sut.take(for: .events), "宛先でないタブは受け取らない")
        XCTAssertEqual(sut.take(for: .idols), "あるすとろめりあ")
    }

    /// 一度受け取ったら消える。
    ///
    /// 消さないと、そのタブへ戻るたびに同じ語が入り直して、利用者が消した
    /// 検索欄が勝手に復活する。
    func testQueryIsConsumedOnce() {
        sut.hand("武道館", to: .events)

        XCTAssertEqual(sut.take(for: .events), "武道館")
        XCTAssertNil(sut.take(for: .events), "2 回目は受け取れない")
    }

    /// 続けて渡したら、後の方が勝つ。
    func testLatestHandoffWins() {
        sut.hand("最初", to: .songs)
        sut.hand("あと", to: .events)

        XCTAssertNil(sut.take(for: .songs), "上書きされた宛先は受け取らない")
        XCTAssertEqual(sut.take(for: .events), "あと")
    }

    /// チップを出す対象は「検索欄を持つ一覧」だけ。
    /// スケジュール・プロデュースには検索欄が無いので、飛ばす先にならない。
    func testOnlyListsWithASearchFieldAreJumpTargets() {
        XCTAssertEqual(RootTab.searchable, [.events, .songs, .idols])
    }
}
