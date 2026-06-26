import AuthenticationServices
import os
import SwiftUI

@Observable
@MainActor
final class AuthService {
    static let shared = AuthService()

    var isSignedIn = false
    var userId: String?
    var userName: String?
    var userEmail: String?
    var identityToken: String?
    var sessionToken: String?
    var isAdmin: Bool = false
    /// サーバ /auth/me で BAN 判定済みか。BAN ユーザーには編集導線を出さない。
    /// 起動時 / refreshMe / 編集 403 受信時に更新する (ローカル反映は best-effort)。
    var isBanned: Bool = false

    // Keychain key (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly + 非同期)
    // sessionToken / identityToken / userId / userName は機密扱いで Keychain に保管。
    // isAdmin は権限 boolean なので UserDefaults でも問題ないが、 一貫性のため Keychain。
    private let userIdKey = "apple_user_id"
    private let userNameKey = "apple_user_name"
    private let identityTokenKey = "apple_identity_token"
    private let sessionTokenKey = "imas_session_token"
    private let isAdminKey = "imas_is_admin"
    private let isBannedKey = "imas_is_banned"

    // sessionToken (Worker 発行 HS256) の期待 claim 値。Worker 側
    // SESSION_JWT_ISSUER / SESSION_JWT_AUDIENCE と一致させる。
    private static let sessionTokenIssuer = "imas-live-db"
    private static let sessionTokenAudience = "imas-live-db-ios"
    private static let sessionTokenAlg = "HS256"

    /// API リクエスト時の Authorization 用ヘッダ値。
    /// sessionToken (30 日有効) を優先、フォールバックで identityToken (10 分有効)。
    var bearerToken: String? {
        sessionToken ?? identityToken
    }

    private init() {
        // 旧バージョンが UserDefaults に保存していた場合は Keychain に移送して
        // UserDefaults 側を削除する (Critical: バックアップから token 流出を塞ぐ)。
        Self.migrateFromUserDefaultsIfNeeded(keys: [userIdKey, userNameKey, identityTokenKey, sessionTokenKey, isAdminKey, isBannedKey])

        if let savedId = KeychainStore.get(userIdKey) {
            userId = savedId
            userName = KeychainStore.get(userNameKey)
            if let token = KeychainStore.get(identityTokenKey), !Self.isJWTExpired(token) {
                identityToken = token
            }
            if let session = KeychainStore.get(sessionTokenKey) {
                if Self.isValidSessionToken(session) {
                    sessionToken = session
                    // 期限が近ければ起動時に先回りで更新しておく。
                    if Self.isSessionTokenNearExpiry(session) {
                        Task { await refreshSession() }
                    }
                } else if Self.isRefreshableSessionToken(session) {
                    // 期限切れでも形・iss/aud が妥当なら Apple 再認証なしで再発行を試みる
                    // (Keychain からは消さず保持しておく)。
                    Task { await refreshSession() }
                } else {
                    // claims が不正で再発行も不可なら Keychain から消す。
                    KeychainStore.delete(key: sessionTokenKey)
                }
            }
            isAdmin = (KeychainStore.get(isAdminKey) == "1")
            isBanned = (KeychainStore.get(isBannedKey) == "1")
            isSignedIn = true
        }
    }

    /// 旧 UserDefaults 保存値があれば Keychain に移送し、 UserDefaults からは削除する。
    /// 1.1.0 → 1.1.1 アップグレード時のワンショット移行。
    private static func migrateFromUserDefaultsIfNeeded(keys: [String]) {
        let ud = UserDefaults.standard
        for key in keys {
            guard let raw = ud.object(forKey: key) else { continue }
            let value: String? = (raw as? String) ?? (raw as? Bool).map { $0 ? "1" : "0" }
            if let v = value, KeychainStore.get(key) == nil {
                KeychainStore.set(v, forKey: key)
            }
            ud.removeObject(forKey: key)
        }
    }

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            userId = credential.user

            var rawIdentityToken: String?
            if let tokenData = credential.identityToken,
               let token = String(data: tokenData, encoding: .utf8) {
                identityToken = token
                rawIdentityToken = token
                KeychainStore.set(token, forKey: identityTokenKey)
            }

            if let fullName = credential.fullName {
                let name = [fullName.familyName, fullName.givenName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !name.isEmpty {
                    userName = name
                    KeychainStore.set(name, forKey: userNameKey)
                }
            }

            if let email = credential.email {
                userEmail = email
            }

            KeychainStore.set(userId, forKey: userIdKey)
            isSignedIn = true

            // 30 日有効の sessionToken をサーバから取得して保存。
            // これ以降の API は sessionToken を使うので、Apple identityToken が
            // 10 分で expire しても再ログインが要らない。
            if let token = rawIdentityToken {
                Task { await self.exchangeForSessionToken(identityToken: token) }
            }

        case .failure(let error):
            Logger.auth.error("apple_sign_in_failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func signOut() {
        userId = nil
        userName = nil
        userEmail = nil
        identityToken = nil
        sessionToken = nil
        isAdmin = false
        isBanned = false
        isSignedIn = false
        for k in [userIdKey, userNameKey, identityTokenKey, sessionTokenKey, isAdminKey, isBannedKey] {
            KeychainStore.delete(key: k)
        }
        // user 依存の集計キャッシュ (has_user_liked / has_user_voted) を破棄。
        // 残すとサインアウト後/別アカウント切替後に前ユーザーの状態が最大 TTL 分漏れる。
        SetlistLikeService.shared.clearCache()
        PredictionService.shared.clearCache()
    }

    /// App Store Review Guideline 5.1.1(v) 対応:
    /// サーバー上の本人データ (投稿・投票・予想・レート制限・user レコード) を削除した上で、
    /// ローカルのサインイン状態も完全にクリアする。
    func deleteAccount() async throws {
        try await APIClient.shared.requestVoid("DELETE", path: "/users/me", authorized: true)
        signOut()
    }

    func updateDisplayName(_ name: String) async throws {
        struct Body: Encodable { let display_name: String }
        try await APIClient.shared.requestVoid(
            "PATCH",
            path: "/users/me",
            body: Body(display_name: name),
            authorized: true
        )
        userName = name
        KeychainStore.set(name, forKey: userNameKey)
    }

    /// 401 で API 認証に使ったトークンが無効と判明した時に呼ぶ。
    /// sessionToken を優先的に捨て、フォールバックで使われていた identityToken も併せて破棄。
    /// userId は保持して、再ログインを促す UI を出せるようにしておく。
    func invalidateToken() {
        sessionToken = nil
        identityToken = nil
        KeychainStore.delete(key: sessionTokenKey)
        KeychainStore.delete(key: identityTokenKey)
    }

    /// 自動リフレッシュも失敗してセッションが完全に失効した時 (401) に呼ぶ。
    /// トークン破棄に加えて isSignedIn=false にし、ログインが必要なコンポーネントが
    /// ログイン導線を出せるようにする (再ログインで isSignedIn が false→true に切り替わり
    /// LoginToEditSheet が自動 dismiss、各画面の導線も復帰する)。userId は再ログイン用に保持。
    func handleSessionExpired() {
        invalidateToken()
        isSignedIn = false
    }

    /// 編集系 API が 403 (BAN) を返した時に呼ぶ。ローカルに BAN を反映して
    /// 編集導線を即座に畳む (サーバ側 refreshMe を待たずに best-effort 反映)。
    func markBannedFromServer() {
        isBanned = true
        KeychainStore.set("1", forKey: isBannedKey)
    }

    /// Apple identityToken をサーバへ送って 1 年有効の sessionToken を発行・保存する。
    /// identityToken は 10 分で expire するため、 失敗時は (まだ有効なうちに) 数回リトライする。
    func exchangeForSessionToken(identityToken token: String) async {
        struct Body: Encodable {
            let identityToken: String
            let displayName: String?
        }
        struct Resp: Decodable {
            let sessionToken: String
            let uid: String
            let email: String?
            let isAdmin: Bool
            let expiresIn: Int
        }
        for attempt in 0..<3 {
            do {
                let resp: Resp = try await APIClient.shared.request(
                    "POST",
                    path: "/auth/login",
                    body: Body(identityToken: token, displayName: userName)
                )
                // defense-in-depth: サーバ署名は API 側で検証済みだが、想定外の token を
                // そのまま保持するのを防ぐためクライアントでも claim チェック。
                guard Self.isValidSessionToken(resp.sessionToken) else {
                    Logger.auth.error("session_token_rejected_invalid_claims")
                    return
                }
                sessionToken = resp.sessionToken
                isAdmin = resp.isAdmin
                KeychainStore.set(resp.sessionToken, forKey: sessionTokenKey)
                KeychainStore.set(resp.isAdmin ? "1" : "0", forKey: isAdminKey)
                Logger.auth.notice("session_token_issued isAdmin=\(resp.isAdmin, privacy: .public)")
                return
            } catch APIClientError.notAuthorized {
                // identityToken が無効 (期限切れ等) ならリトライしても無駄。
                Logger.auth.error("session_token_exchange_unauthorized")
                return
            } catch {
                Logger.auth.error("session_token_exchange_failed (attempt \(attempt + 1)): \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    // MARK: - Sliding refresh (Apple 再認証なしの自動再ログイン)

    private var refreshInFlight: Task<Bool, Never>?

    /// 期限切れ/間近の sessionToken を /auth/refresh で再発行する。
    /// 署名が有効で猶予内ならサーバが新しい 1 年トークンを返す (Apple サインイン不要)。
    /// 同時多発の 401 で多重実行しないよう in-flight タスクを共有する。
    @discardableResult
    func refreshSession() async -> Bool {
        if let existing = refreshInFlight { return await existing.value }
        let task = Task<Bool, Never> { [weak self] in
            guard let self else { return false }
            return await self.performSessionRefresh()
        }
        refreshInFlight = task
        let result = await task.value
        refreshInFlight = nil
        return result
    }

    private func performSessionRefresh() async -> Bool {
        let candidate = sessionToken ?? KeychainStore.get(sessionTokenKey)
        guard let token = candidate, Self.isRefreshableSessionToken(token) else { return false }
        struct Resp: Decodable {
            let sessionToken: String
            let uid: String
            let isAdmin: Bool
            let expiresIn: Int
        }
        do {
            let resp: Resp = try await APIClient.shared.requestWithBearer(
                "POST", path: "/auth/refresh", bearer: token
            )
            guard Self.isValidSessionToken(resp.sessionToken) else {
                Logger.auth.error("session_refresh_rejected_invalid_claims")
                return false
            }
            sessionToken = resp.sessionToken
            isAdmin = resp.isAdmin
            isSignedIn = true
            KeychainStore.set(resp.sessionToken, forKey: sessionTokenKey)
            KeychainStore.set(resp.isAdmin ? "1" : "0", forKey: isAdminKey)
            Logger.auth.notice("session_refreshed")
            return true
        } catch {
            Logger.auth.error("session_refresh_failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// /auth/me を叩いて isAdmin を最新化する。アプリ起動時に sessionToken がある場合に呼ぶ。
    ///
    /// 契約 §1/§3: レスポンスは素の camelCase。貢献度は 2 指標
    /// (`editCount` / `goodsReceived`) を別フィールドで返す (旧 `contribution_count` は廃止)。
    func refreshMe() async {
        guard sessionToken != nil || identityToken != nil else { return }
        struct Me: Decodable {
            let uid: String
            let displayName: String?
            let isAdmin: Bool
            let isBanned: Bool
            let editCount: Int?
            let goodsReceived: Int?
        }
        do {
            let me: Me = try await APIClient.shared.request("GET", path: "/auth/me", authorized: true)
            isAdmin = me.isAdmin
            isBanned = me.isBanned
            KeychainStore.set(me.isAdmin ? "1" : "0", forKey: isAdminKey)
            KeychainStore.set(me.isBanned ? "1" : "0", forKey: isBannedKey)
            if let name = me.displayName, userName != name {
                userName = name
                KeychainStore.set(name, forKey: userNameKey)
            }
        } catch APIClientError.notAuthorized {
            // sessionToken も identityToken も無効 → invalidateToken は APIClient 側で実行済み。
            Logger.auth.notice("refresh_me unauthorized — token cleared")
        } catch {
            Logger.auth.error("refresh_me_failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// refresh 可能な形か (署名は検証できないので alg/iss/aud/exp の有無だけ確認)。
    /// 実際の猶予判定はサーバ /auth/refresh が署名込みで行う。
    private static func isRefreshableSessionToken(_ token: String) -> Bool {
        guard let header = decodeJWTHeader(token),
              (header["alg"] as? String) == sessionTokenAlg,
              let payload = decodeJWTPayload(token),
              (payload["iss"] as? String) == sessionTokenIssuer,
              (payload["aud"] as? String) == sessionTokenAudience,
              (payload["exp"] as? TimeInterval) != nil else {
            return false
        }
        return true
    }

    /// 有効だが期限が近い (既定 7 日以内) か。起動時の先回り更新に使う。
    private static func isSessionTokenNearExpiry(_ token: String, within seconds: TimeInterval = 60 * 60 * 24 * 7) -> Bool {
        guard let payload = decodeJWTPayload(token), let exp = payload["exp"] as? TimeInterval else { return false }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < seconds
    }

    private static func isJWTExpired(_ token: String) -> Bool {
        guard let payload = decodeJWTPayload(token),
              let exp = payload["exp"] as? TimeInterval else { return true }
        return Date(timeIntervalSince1970: exp).timeIntervalSinceNow < 60
    }

    /// sessionToken の claim 検証 (defense-in-depth)。
    /// 期待: alg=HS256 / iss=imas-live-db / aud=imas-live-db-ios / exp > now+60s。
    /// サーバ署名は API 側で検証済みなので、ここでは header/payload を decode して
    /// 値だけ照合する。
    private static func isValidSessionToken(_ token: String) -> Bool {
        guard let header = decodeJWTHeader(token),
              let alg = header["alg"] as? String, alg == sessionTokenAlg,
              let payload = decodeJWTPayload(token),
              let iss = payload["iss"] as? String, iss == sessionTokenIssuer,
              let aud = payload["aud"] as? String, aud == sessionTokenAudience,
              let exp = payload["exp"] as? TimeInterval,
              Date(timeIntervalSince1970: exp).timeIntervalSinceNow > 60 else {
            return false
        }
        return true
    }

    private static func decodeJWTHeader(_ token: String) -> [String: Any]? {
        decodeJWTSegment(token, index: 0)
    }

    private static func decodeJWTPayload(_ token: String) -> [String: Any]? {
        decodeJWTSegment(token, index: 1)
    }

    /// JWT (header.payload.signature) の 0=header / 1=payload セグメントを取り出して JSON decode する。
    private static func decodeJWTSegment(_ token: String, index: Int) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count == 3, parts.indices.contains(index) else { return nil }
        return decodeBase64URLJSON(String(parts[index]))
    }

    private static func decodeBase64URLJSON(_ segment: String) -> [String: Any]? {
        var s = segment.replacingOccurrences(of: "-", with: "+")
                       .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let data = Data(base64Encoded: s),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    func checkCredentialState() async {
        guard let userId else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userId)
            switch state {
            case .authorized:
                break
            case .revoked:
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let retryState = try await provider.credentialState(forUserID: userId)
                if retryState == .revoked {
                    signOut()
                }
            case .notFound, .transferred:
                signOut()
            @unknown default:
                signOut()
            }
        } catch {
            Logger.auth.error("credential_state_check_failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// Apple Sign In ボタン（SwiftUI）
struct AppleSignInButton: View {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            AuthService.shared.handleSignInResult(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
