import XCTest
@testable import ImasLiveDB

/// `EditPermissionRules` の単体テスト。
///
/// オープン編集は承認待ちゼロで即反映されるモデルなので、ここの 4 通りが
/// そのまま「誰が書けるか」になる。`AuthService.shared` から切り離してあるので
/// BAN 済みユーザーの経路もテストで踏める。
final class EditPermissionRulesTests: XCTestCase {

    private let signedOut = EditPermissionRules(isSignedIn: false, isBanned: false)
    private let signedIn = EditPermissionRules(isSignedIn: true, isBanned: false)
    private let banned = EditPermissionRules(isSignedIn: true, isBanned: true)

    // MARK: - canEdit

    func testOnlySignedInAndNotBannedCanEdit() {
        XCTAssertFalse(signedOut.canEdit)
        XCTAssertTrue(signedIn.canEdit)
        XCTAssertFalse(banned.canEdit, "BAN 済みが編集シートを開けると 403 を量産できてしまう")
    }

    // MARK: - showEditAffordance

    /// 未ログインにもボタンは見せる (押してログインしてもらう導線)。
    func testAffordanceIsShownToSignedOutUsers() {
        XCTAssertTrue(signedOut.showEditAffordance)
    }

    /// BAN 済みには出さない (押しても 403 になるだけ)。
    func testAffordanceIsHiddenFromBannedUsers() {
        XCTAssertFalse(banned.showEditAffordance)
    }

    // MARK: - outcomeOnEditTap

    func testSignedInUserGetsTheEditor() {
        XCTAssertEqual(signedIn.outcomeOnEditTap, .present)
    }

    func testSignedOutUserGetsLoginPrompt() {
        XCTAssertEqual(signedOut.outcomeOnEditTap, .promptLogin)
    }

    /// BAN 済みは何も起きない。ログイン誘導を出してしまうと、
    /// 既にログインしているのにログイン画面が出る意味不明な挙動になる。
    func testBannedUserGetsNothing() {
        XCTAssertEqual(banned.outcomeOnEditTap, .ignore)
    }

    /// 導線が出ている状態なら、押した結果が `.ignore` になることはない
    /// (押せるのに何も起きないボタンを作らない)。
    func testVisibleAffordanceAlwaysDoesSomething() {
        for rules in [signedOut, signedIn, banned] where rules.showEditAffordance {
            XCTAssertNotEqual(rules.outcomeOnEditTap, .ignore, "\(rules)")
        }
    }
}
