import Foundation
import Observation
import UIKit

/// Sign in with ChatGPT のサインイン状態と資格情報 (試作)。
///
/// 保存は Keychain (この端末のみ・iCloud 同期なし)。登録 (発行済み client_id と
/// アカウント) とトークンは分けて持つ: サインアウトではトークンだけ消し、次のサインインで
/// 同じ client_id を使い回す (新しいクライアントを作らない)。
@MainActor
@Observable
final class ChatGPTPlanSession {
    static let shared = ChatGPTPlanSession()

    struct Registration: Codable {
        let clientID: String
        let subject: String
        let email: String?
    }

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String?
        var idToken: String?
        var tokenType: String
        var scopes: [String]
        var expiresAt: Date
    }

    private enum Key {
        static let hostID = "chatgpt_plan.host_id"
        static let registration = "chatgpt_plan.registration"
        static let tokens = "chatgpt_plan.tokens"
        /// 初回登録で発行されたが、交換・検証まで済んでいない client_id。
        static let pendingClientID = "chatgpt_plan.pending_client_id"
    }

    private(set) var registration: Registration?
    private(set) var tokens: Tokens?
    private(set) var isSigningIn = false
    /// 試作の確認用。どこまで進んだかを画面に出す (トークンの値は書かない)。
    private(set) var log: [String] = []

    var isSignedIn: Bool { tokens != nil }
    var canUsePlan: Bool { tokens?.scopes.contains(ChatGPTPlanAuth.planScope) ?? false }

    private let browser = ChatGPTPlanBrowser()
    private var activeServer: LoopbackCallbackServer?
    private var refreshTask: Task<Tokens, Error>?

    private init() {
        registration = Self.load(Registration.self, key: Key.registration)
        tokens = Self.load(Tokens.self, key: Key.tokens)
    }

    /// 端末ごとに 1 回だけ作って以後ずっと同じ値を送る。
    private var hostID: String {
        if let saved = KeychainStore.get(Key.hostID) { return saved }
        let created = "urn:uuid:\(UUID().uuidString.lowercased())"
        KeychainStore.set(created, forKey: Key.hostID)
        return created
    }

    // MARK: - サインイン

    enum Intent {
        /// 保存済みの登録があればそれで入る。無ければ新規登録。
        case signIn
        /// 外したプラン利用の許可を、同意画面を出して取り直す。
        case enablePlan
        /// 今の登録を使わず、別のアカウントとして新規登録する。
        case newAccount
    }

    func signIn(mode: ChatGPTPlanBrowser.Mode, intent: Intent = .signIn) async throws {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        log.removeAll()

        // ログイン中にメールの確認コードを見に行くとアプリが裏に回る。その間も待ち受けが
        // 生きているよう、callback を受けるまでバックグラウンド実行を延ばしておく。
        let background = UIApplication.shared.beginBackgroundTask(withName: "chatgpt-plan.signin")
        defer { UIApplication.shared.endBackgroundTask(background) }

        // 登録途中で落ちた client_id があれば、新規登録を重ねずにそれで再認可する。
        let reusableClientID: String? = switch intent {
        case .newAccount: nil
        case .signIn, .enablePlan: registration?.clientID ?? KeychainStore.get(Key.pendingClientID)
        }
        let isSameRegistration = reusableClientID != nil && reusableClientID == registration?.clientID

        let server = LoopbackCallbackServer()
        let attempt = ChatGPTPlanAuth.newAttempt(
            savedClientID: reusableClientID,
            redirectURI: server.redirectURI,
            forceConsent: intent == .enablePlan
        )
        server.expectedState = attempt.state
        activeServer = server
        defer {
            server.stop()
            activeServer = nil
        }
        try await server.start()
        note("127.0.0.1:\(server.port) で待ち受け開始")

        let url = ChatGPTPlanAuth.authorizeURL(
            for: attempt,
            hostID: hostID,
            idTokenHint: isSameRegistration ? tokens?.idToken : nil,
            loginHint: isSameRegistration ? registration?.email : nil
        )
        note(attempt.isNewRegistration ? "初回登録 (dynamic_agent_client)" : "再認可 (\(attempt.clientID))")
        if attempt.forceConsent { note("同意画面を出して許可を取り直す") }

        guard browser.open(url, mode: mode, onUserCancel: { server.stop() }) else {
            throw LoopbackCallbackServer.ServerError.listenerFailed("ブラウザを開けませんでした")
        }
        note("\(mode.label) を開いた")

        let callback: URLComponents
        do {
            callback = try await server.waitForCallback()
        } catch {
            browser.close()
            note("callback を受け取る前に終了")
            throw error
        }
        browser.close()
        note("ループバックで callback を受信 ✓")

        let result = try ChatGPTPlanAuth.parseCallback(callback, attempt: attempt)
        note("発行済み client_id: \(result.issuedClientID)")
        if attempt.isNewRegistration {
            // 交換や検証で落ちても、発行された ID は次の試行で使い回す (連携アプリを増やさない)。
            KeychainStore.set(result.issuedClientID, forKey: Key.pendingClientID)
        }

        let response = try await ChatGPTPlanAuth.exchange(code: result.code, clientID: result.issuedClientID, attempt: attempt)
        note("トークン交換 OK")

        guard let idToken = response.idToken else { throw ChatGPTPlanAuth.AuthError.idToken("ID トークンが返りませんでした") }
        let claims = try ChatGPTPlanAuth.validateIDToken(idToken, clientID: result.issuedClientID, nonce: attempt.nonce)
        if isSameRegistration, let registration, registration.subject != claims.subject {
            // 再認可で別アカウントが返ったら、既存の登録を上書きせず、受け取ったものは失効させる。
            if let refreshToken = response.refreshToken {
                try? await ChatGPTPlanAuth.revoke(refreshToken: refreshToken, clientID: result.issuedClientID)
            }
            throw ChatGPTPlanAuth.AuthError.differentAccount
        }
        note("ID トークン検証 OK (\(claims.email ?? claims.subject))")

        // 別アカウントに切り替えるなら、前のアカウントのセッションは閉じておく。
        if !isSameRegistration, let oldRefresh = tokens?.refreshToken, let oldClient = registration?.clientID {
            try? await ChatGPTPlanAuth.revoke(refreshToken: oldRefresh, clientID: oldClient)
        }

        let newRegistration = Registration(clientID: result.issuedClientID, subject: claims.subject, email: claims.email)
        let newTokens = Self.tokens(
            from: response,
            idToken: idToken,
            refreshToken: nil,
            scopes: result.callbackScope.map(Self.splitScopes) ?? []
        )
        save(registration: newRegistration)
        save(tokens: newTokens)
        KeychainStore.delete(key: Key.pendingClientID)
        note("scope: \(newTokens.scopes.joined(separator: " "))")
        if !canUsePlan {
            note("chatgpt.tokens.use.direct が付与されていません")
        }
    }

    func cancelSignIn() {
        activeServer?.stop()
        browser.close()
    }

    // MARK: - トークン

    /// 期限 5 分前を切っていたら更新してから返す。更新は直列化する (refresh_token は使い捨て)。
    func validAccessToken() async throws -> String {
        guard let tokens else { throw ChatGPTPlanAuth.AuthError.notSignedIn }
        if tokens.expiresAt.timeIntervalSinceNow > 300 { return tokens.accessToken }
        return try await refresh().accessToken
    }

    @discardableResult
    func refresh() async throws -> Tokens {
        if let refreshTask { return try await refreshTask.value }
        guard let current = tokens, let refreshToken = current.refreshToken, let clientID = registration?.clientID else {
            throw ChatGPTPlanAuth.AuthError.noRefreshToken
        }
        let task = Task { () throws -> Tokens in
            let response = try await ChatGPTPlanAuth.refresh(refreshToken: refreshToken, clientID: clientID)
            // 更新の応答は scope を省くことがある。省かれたら付与範囲は前のまま。
            return Self.tokens(from: response, idToken: current.idToken, refreshToken: refreshToken, scopes: current.scopes)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let renewed = try await task.value
            // 待っている間にサインアウトや別のサインインが入ったら、古いものを書き戻さない。
            guard tokens?.refreshToken == refreshToken else { throw ChatGPTPlanAuth.AuthError.notSignedIn }
            save(tokens: renewed)
            return renewed
        } catch let ChatGPTPlanAuth.AuthError.tokenEndpoint(status, body) where Self.isUnusableRefresh(body) {
            // 使えない refresh_token は消して、同じ client_id でサインインし直してもらう。
            if tokens?.refreshToken == refreshToken { clearTokens() }
            throw ChatGPTPlanAuth.AuthError.tokenEndpoint(status: status, body: body)
        }
    }

    // MARK: - サインアウト

    /// 失効を試してからローカルのトークンを消す。登録 (client_id / アカウント) は残す。
    /// - Returns: リモートの失効を確認できたか。
    @discardableResult
    func signOut() async -> Bool {
        // 更新中なら差し替わった後の refresh_token を失効させる。
        _ = try? await refreshTask?.value
        var revoked = false
        if let refreshToken = tokens?.refreshToken, let clientID = registration?.clientID {
            revoked = (try? await ChatGPTPlanAuth.revoke(refreshToken: refreshToken, clientID: clientID)) != nil
        }
        clearTokens()
        return revoked
    }

    // MARK: - 保存

    /// 応答に無い項目は引数の値 (直前のもの) を引き継ぐ。
    private static func tokens(from response: ChatGPTPlanAuth.TokenResponse, idToken: String?, refreshToken: String?, scopes: [String]) -> Tokens {
        Tokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            idToken: response.idToken ?? idToken,
            tokenType: response.tokenType ?? "Bearer",
            scopes: response.scope.map(splitScopes) ?? scopes,
            expiresAt: Date().addingTimeInterval(response.expiresIn ?? 3600)
        )
    }

    private static func splitScopes(_ scope: String) -> [String] {
        scope.split(separator: " ").map(String.init).sorted()
    }

    private static func isUnusableRefresh(_ body: String) -> Bool {
        ["invalid_grant", "invalid_refresh_token", "token_expired", "refresh_token_expired",
         "refresh_token_invalidated", "refresh_token_reused"].contains { body.contains($0) }
    }

    private func save(registration: Registration) {
        self.registration = registration
        Self.store(registration, key: Key.registration)
    }

    private func save(tokens: Tokens) {
        self.tokens = tokens
        Self.store(tokens, key: Key.tokens)
    }

    private func clearTokens() {
        tokens = nil
        KeychainStore.delete(key: Key.tokens)
    }

    private func note(_ message: String) {
        let time = Date().formatted(date: .omitted, time: .standard)
        log.append("\(time)  \(message)")
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let json = KeychainStore.get(key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static func store<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        KeychainStore.set(String(decoding: data, as: UTF8.self), forKey: key)
    }
}
