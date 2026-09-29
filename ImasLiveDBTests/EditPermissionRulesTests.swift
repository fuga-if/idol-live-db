import XCTest
@testable import ImasLiveDB

/// `EditPermissionRules` の単体テスト。
///
/// オープン編集は承認待ちゼロで即反映されるモデルなので、ここの 4 通りが
/// そのまま「誰が書けるか」になる。`AuthService.shared` から切り離してあるので
/// BAN 済みユーザーの経路もテストで踏める。
///
/// 規則そのものはコア (imas-core) の Rust テストが持つ。ここに残すのは、Swift の包みが
/// コアに正しく渡し・受け取れていることを見る配線のスモークテストと、Swift にしか無い処理のテスト (Q-13)。
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

    // MARK: - outcomeOnEditTap

    /// 導線が出ている状態なら、押した結果が `.ignore` になることはない
    /// (押せるのに何も起きないボタンを作らない)。
    func testVisibleAffordanceAlwaysDoesSomething() {
        for rules in [signedOut, signedIn, banned] where rules.showEditAffordance {
            XCTAssertNotEqual(rules.outcomeOnEditTap, .ignore, "\(rules)")
        }
    }
}
