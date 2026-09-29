import XCTest
@testable import ImasLiveDB

/// 認証の判定はコア (`auth_rules.rs`) が持ち、そちらのテストが規則を押さえている。
/// ここで見るのは、`AuthService` が渡す形 (Worker が発行する形の JWT・Keychain の文字列) を
/// コアがそのまま読めること。
final class AuthRulesWiringTests: XCTestCase {

    private func jwt(exp: Int64, iss: String = "imas-live-db", aud: String = "imas-live-db-ios") -> String {
        func seg(_ json: String) -> String {
            Data(json.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return seg(#"{"alg":"HS256","typ":"JWT"}"#) + "."
            + seg(#"{"iss":"\#(iss)","aud":"\#(aud)","exp":\#(exp)}"#) + ".sig"
    }

    private let now: Int64 = 1_790_000_000

    func testRestoreReadsKeychainStringsAndDecidesRefresh() {
        let day: Int64 = 86_400
        func restore(_ session: String?) -> RestoredAuthState {
            authRestoreStoredState(
                stored: StoredAuthState(userId: "u1", identityToken: nil, sessionToken: session,
                                        isAdminFlag: "1", isBannedFlag: "0"),
                nowEpochSeconds: now)
        }
        let fresh = restore(jwt(exp: now + 100 * day))
        XCTAssertTrue(fresh.isSignedIn)
        XCTAssertNotNil(fresh.sessionToken)
        XCTAssertFalse(fresh.shouldRefreshSession)
        XCTAssertTrue(fresh.isAdmin)
        XCTAssertFalse(fresh.isBanned)

        // 期限切れでも形が妥当なら保存は残して再発行を試す。
        let expired = restore(jwt(exp: now - day))
        XCTAssertNil(expired.sessionToken)
        XCTAssertTrue(expired.shouldRefreshSession)
        XCTAssertFalse(expired.shouldDeleteStoredSessionToken)

        // 別アプリ向けのトークンは捨てる。
        XCTAssertTrue(restore(jwt(exp: now + day * 100, aud: "other")).shouldDeleteStoredSessionToken)

        // userId が無ければ何も復元しない。
        XCTAssertFalse(authRestoreStoredState(
            stored: StoredAuthState(userId: nil, identityToken: nil, sessionToken: jwt(exp: now + day * 100),
                                    isAdminFlag: "1", isBannedFlag: nil),
            nowEpochSeconds: now).isSignedIn)
    }

    func testBearerPrefersSessionTokenAndFlagsRoundTrip() {
        XCTAssertEqual(authBearerToken(sessionToken: "s", identityToken: "i"), "s")
        XCTAssertEqual(authBearerToken(sessionToken: nil, identityToken: "i"), "i")
        XCTAssertEqual(authStoredFlagValue(flag: true), "1")
        XCTAssertEqual(authStoredFlagValue(flag: false), "0")
        XCTAssertTrue(authAdminCapabilities(isAdmin: true).canApplyMasterEditDirectly)
        XCTAssertFalse(authAdminCapabilities(isAdmin: false).canModerateUsers)
    }
}
