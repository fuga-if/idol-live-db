import XCTest
@testable import ImasLiveDB

/// 楽曲詳細タブの出し分け (`SongDetailTab.available` / `resolved`) の検査。
///
/// 歌詞タブの出し入れは JASRAC の許諾 (`LyricsFeature`) にだけ従う。
/// 許諾が失効・変更されたときに落とす先がここ 1 箇所であることを固定しておく
/// (掲載曲数の上限はサーバが持っているので、アプリ側の関心はタブの有無だけ)。
final class SongDetailTabAvailabilityTests: XCTestCase {

    /// 歌詞タブの有無は `LyricsFeature` にだけ従う。
    func testLyricsTabFollowsFeatureFlag() {
        XCTAssertEqual(SongDetailTab.available.contains(.lyrics), LyricsFeature.isAvailable)
    }

    /// 歌詞以外のタブはフラグに関係なく常に出る (巻き添えで消えていないこと)。
    func testNonLyricsTabsAreUnaffected() {
        for tab in SongDetailTab.allCases where tab != .lyrics {
            XCTAssertTrue(SongDetailTab.available.contains(tab), "\(tab) が消えている")
        }
    }

    /// `resolved` は必ず出せるタブを返す。ディープリンクや保存済みの初期タブが
    /// 歌詞を指していても、載っていないビルドでは情報タブに倒れる。
    func testResolvedAlwaysReturnsAnAvailableTab() {
        for tab in SongDetailTab.allCases {
            XCTAssertTrue(SongDetailTab.available.contains(tab.resolved),
                          "\(tab).resolved = \(tab.resolved) が available に無い")
        }
    }
}
