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

    // トークンの判定 (claim の検証・期限・再発行の要否・応答の採否・リトライ) は
    // imas-core `domain/auth_rules.rs` が持つ。ここは Keychain と通信と状態の反映だけ。

    /// API リクエスト時の Authorization 用ヘッダ値 (sessionToken 優先、無ければ identityToken)。
    /// 有効性は見ない (送信前に止めると 401 → 自動リフレッシュ → 再送が死ぬ)。
    var bearerToken: String? {
        authBearerToken(sessionToken: sessionToken, identityToken: identityToken)
    }

    /// admin に開く操作。`isAdmin` を直に読まず、能力ごとに問う。
    var adminCapabilities: AdminCapabilities {
        authAdminCapabilities(isAdmin: isAdmin)
    }

    private static var nowEpochSeconds: Int64 { Int64(Date().timeIntervalSince1970) }

    private init() {
        // 旧バージョンが UserDefaults に保存していた場合は Keychain に移送して
        // UserDefaults 側を削除する (Critical: バックアップから token 流出を塞ぐ)。
        Self.migrateFromUserDefaultsIfNeeded(keys: [userIdKey, userNameKey, identityTokenKey, sessionTokenKey, isAdminKey, isBannedKey])

        let savedId = KeychainStore.get(userIdKey)
        let restored = authRestoreStoredState(
            stored: StoredAuthState(
                userId: savedId,
                identityToken: KeychainStore.get(identityTokenKey),
                sessionToken: KeychainStore.get(sessionTokenKey),
                isAdminFlag: KeychainStore.get(isAdminKey),
                isBannedFlag: KeychainStore.get(isBannedKey)),
            nowEpochSeconds: Self.nowEpochSeconds)
        guard restored.isSignedIn else { return }
        userId = savedId
        userName = KeychainStore.get(userNameKey)
        identityToken = restored.identityToken
        sessionToken = restored.sessionToken
        isAdmin = restored.isAdmin
        isBanned = restored.isBanned
        isSignedIn = true
        if restored.shouldDeleteStoredSessionToken {
            KeychainStore.delete(key: sessionTokenKey)
        }
        if restored.shouldRefreshSession {
            // 期限が近い / 切れているが再発行できる形 → Apple 再認証なしで再発行を試みる。
            Task { await refreshSession() }
        }
    }

    /// 旧 UserDefaults 保存値があれば Keychain に移送し、 UserDefaults からは削除する。
    /// 1.1.0 → 1.1.1 アップグレード時のワンショット移行。
    private static func migrateFromUserDefaultsIfNeeded(keys: [String]) {
        let ud = UserDefaults.standard
        for key in keys {
            guard let raw = ud.object(forKey: key) else { continue }
            let value: String? = (raw as? String) ?? (raw as? Bool).map { authStoredFlagValue(flag: $0) }
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

            if let name = authDisplayNameFromAppleName(
                familyName: credential.fullName?.familyName,
                givenName: credential.fullName?.givenName) {
                userName = name
                KeychainStore.set(name, forKey: userNameKey)
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
        // ローカル永続の投票履歴・投稿履歴も user 依存。残すと別アカウント切替後に
        // 前ユーザーの投票済み/投稿累計が漏れるので破棄する。
        LocalPollVoteLog.shared.clear()
        LocalContributionLog.shared.clear()
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
            "POST",
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
        KeychainStore.set(authStoredFlagValue(flag: true), forKey: isBannedKey)
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
            let displayName: String?
            let expiresIn: Int
        }
        var attempt: UInt32 = 0
        while true {
            let outcome: TokenExchangeOutcome
            do {
                let resp: Resp = try await APIClient.shared.request(
                    "POST",
                    path: "/auth/login",
                    body: Body(identityToken: token, displayName: userName)
                )
                // 再ログイン時 Apple は fullName を返さないので、サーバが返す正準 display_name で
                // userName を復元する (空なら既存名を保つ。規則はコア)。
                guard adoptSession(SessionResponse(
                    sessionToken: resp.sessionToken, isAdmin: resp.isAdmin,
                    displayName: resp.displayName)) else {
                    Logger.auth.error("session_token_rejected_invalid_claims")
                    return
                }
                Logger.auth.notice("session_token_issued isAdmin=\(resp.isAdmin, privacy: .public)")
                outcome = .succeeded
            } catch APIClientError.notAuthorized {
                // identityToken が無効 (期限切れ等) ならリトライしても無駄。
                Logger.auth.error("session_token_exchange_unauthorized")
                outcome = .unauthorized
            } catch {
                Logger.auth.error("session_token_exchange_failed (attempt \(attempt + 1)): \(error.localizedDescription, privacy: .public)")
                outcome = .failed
            }
            guard case .retryAfter(let delayMillis) = authTokenExchangeRetry(attempt: attempt, outcome: outcome) else {
                return
            }
            try? await Task.sleep(for: .milliseconds(delayMillis))
            attempt += 1
        }
    }

    /// `/auth/login` `/auth/refresh` が返したセッションを採用する。採用したら true。
    /// 採否と、何を書き換えるか (None = 変更しない) はコアが決める。
    private func adoptSession(_ response: SessionResponse) -> Bool {
        let adoption = authAdoptSessionResponse(response: response, nowEpochSeconds: Self.nowEpochSeconds)
        guard adoption.accepted else { return false }
        if let token = adoption.sessionToken {
            sessionToken = token
            KeychainStore.set(token, forKey: sessionTokenKey)
        }
        if let admin = adoption.isAdmin {
            isAdmin = admin
            KeychainStore.set(authStoredFlagValue(flag: admin), forKey: isAdminKey)
        }
        if let name = adoption.displayName {
            userName = name
            KeychainStore.set(name, forKey: userNameKey)
        }
        if let signedIn = adoption.isSignedIn {
            isSignedIn = signedIn
        }
        return true
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
        guard let token = authSessionRefreshCandidate(
            inMemoryToken: sessionToken, storedToken: KeychainStore.get(sessionTokenKey)) else { return false }
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
            // 401 で落としたサインイン状態も、採用できたらここで戻る (isSignedIn)。
            guard adoptSession(SessionResponse(
                sessionToken: resp.sessionToken, isAdmin: resp.isAdmin, displayName: nil)) else {
                Logger.auth.error("session_refresh_rejected_invalid_claims")
                return false
            }
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
            let refresh = authApplyMeResponse(
                me: MeResponse(isAdmin: me.isAdmin, isBanned: me.isBanned, displayName: me.displayName),
                currentDisplayName: userName)
            isAdmin = refresh.isAdmin
            isBanned = refresh.isBanned
            KeychainStore.set(authStoredFlagValue(flag: refresh.isAdmin), forKey: isAdminKey)
            KeychainStore.set(authStoredFlagValue(flag: refresh.isBanned), forKey: isBannedKey)
            if let name = refresh.displayName {
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

    func checkCredentialState() async {
        guard let userId else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            var isRecheck = false
            while true {
                let state = try await provider.credentialState(forUserID: userId)
                switch authCredentialCheckAction(state: Self.appleCredentialState(state), isRecheck: isRecheck) {
                case .keepSession:
                    return
                case .signOut:
                    signOut()
                    return
                case .recheckAfter(let delayMillis):
                    // 端末が一時的に revoked を返すことがあるので、少し待って問い合わせ直す。
                    try? await Task.sleep(for: .milliseconds(delayMillis))
                    isRecheck = true
                }
            }
        } catch {
            Logger.auth.error("credential_state_check_failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func appleCredentialState(
        _ state: ASAuthorizationAppleIDProvider.CredentialState
    ) -> AppleCredentialState {
        switch state {
        case .authorized: .authorized
        case .revoked: .revoked
        case .notFound: .notFound
        case .transferred: .transferred
        @unknown default: .unknown
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
