import Foundation
import Observation
import Security
import UIKit

/// Sign in with ChatGPT のサインイン状態と資格情報。
///
/// 利用者の ChatGPT プラン (Plus / Pro) で推論を回すための口。このアプリのアカウント
/// (Apple でサインイン) とは別物で、ここで得た識別子をサーバへ送ることはない。
///
/// どの client_id で入るか・認可 URL・callback とトークン応答の読み方・いつ更新するかは
/// 全部コア (`chatgpt_plan.rs`)。ここは待ち受けを立て、ブラウザを開き、フォームを POST し、
/// コアが返したものを Keychain に置くだけ。
///
/// 保存は Keychain (この端末のみ・iCloud 同期なし)。登録 (発行済み client_id と
/// アカウント) とトークンは分けて持つ: サインアウトではトークンだけ消し、次のサインインで
/// 同じ client_id を使い回す (新しいクライアントを作らない)。
@MainActor
@Observable
final class ChatGPTPlanSession {
    static let shared = ChatGPTPlanSession()

    private enum Key {
        static let hostID = "chatgpt_plan.host_id"
        static let registration = "chatgpt_plan.registration.v2"
        static let tokens = "chatgpt_plan.tokens.v2"
        /// 初回登録で発行されたが、交換・検証まで済んでいない client_id。
        static let pendingClientID = "chatgpt_plan.pending_client_id"
        /// 選んだモデル (秘密ではないので UserDefaults)。
        static let model = "chatgpt_plan.model"
    }

    enum SessionError: LocalizedError {
        case notSignedIn
        case message(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "ChatGPT にログインしていません"
            case .message(let text): text
            }
        }
    }

    private(set) var registration: ChatGptRegistration?
    private(set) var tokens: ChatGptTokens?
    private(set) var isSigningIn = false
    /// サインイン中のアカウントで選べるモデル (サーバの並び順)。
    private(set) var models: [ChatGptModel] = []

    var isSignedIn: Bool { tokens != nil }
    var canUsePlan: Bool { tokens.map { chatgptCanUsePlan(tokens: $0) } ?? false }

    private let browser = ChatGPTPlanBrowser()
    private var activeServer: LoopbackCallbackServer?
    private var refreshTask: Task<ChatGptTokens, Error>?

    private init() {
        registration = Self.load(StoredRegistration.self, key: Key.registration)?.value
        tokens = Self.load(StoredTokens.self, key: Key.tokens)?.value
    }

    /// 端末ごとに 1 回だけ作って以後ずっと同じ値を送る。
    private var hostID: String {
        if let saved = KeychainStore.get(Key.hostID) { return saved }
        let created = chatgptHostId(uuid: UUID().uuidString)
        KeychainStore.set(created, forKey: Key.hostID)
        return created
    }

    // MARK: - サインイン

    func signIn(intent: ChatGptSignInIntent = .signIn) async throws {
        do {
            try await performSignIn(intent: intent)
        } catch let error as ChatGptAuthError {
            // コアの文言をそのまま出す (生成された型の説明は型名つきの開発者向け表記なので使わない)。
            throw SessionError.message(error.message)
        }
    }

    private func performSignIn(intent: ChatGptSignInIntent) async throws {
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }

        // ログイン中にメールの確認コードを見に行くとアプリが裏に回る。その間も待ち受けが
        // 生きているよう、callback を受けるまでバックグラウンド実行を延ばしておく。
        let background = UIApplication.shared.beginBackgroundTask(withName: "chatgpt-plan.signin")
        defer { UIApplication.shared.endBackgroundTask(background) }

        let server = LoopbackCallbackServer()
        let attempt = try chatgptBeginSignIn(
            intent: intent,
            registration: registration,
            pendingClientId: KeychainStore.get(Key.pendingClientID),
            idToken: tokens?.idToken,
            hostId: hostID,
            port: server.port,
            random: try Self.secureRandom(count: Int(chatgptAttemptRandomBytes()))
        )
        server.isExpected = { target in chatgptIsExpectedCallback(target: target, attempt: attempt) }
        activeServer = server
        defer {
            server.stop()
            activeServer = nil
        }
        try await server.start()

        guard let url = URL(string: attempt.authorizeUrl),
              browser.open(url, onUserCancel: { server.stop() }) else {
            throw LoopbackCallbackServer.ServerError.listenerFailed("ブラウザを開けませんでした")
        }
        let target: String
        do {
            target = try await server.waitForCallback()
        } catch {
            browser.close()
            throw error
        }
        browser.close()

        let callback: ChatGptCallback
        do {
            callback = try chatgptReadCallback(target: target, attempt: attempt)
        } catch let error as ChatGptAuthError {
            // 途中で残った client_id がもう使えないなら捨てる (次は新規登録からやり直せる)。
            var isOAuthError = false
            if case .OAuth = error { isOAuthError = true }
            if chatgptShouldForgetPending(attempt: attempt, isOauthError: isOAuthError) {
                KeychainStore.delete(key: Key.pendingClientID)
            }
            throw error
        }
        if callback.rememberAsPending {
            // 交換や検証で落ちても、発行された ID は次の試行で使い回す (連携アプリを増やさない)。
            KeychainStore.set(callback.clientId, forKey: Key.pendingClientID)
        }

        let endpoints = chatgptEndpoints()
        let (status, body) = try await ChatGPTPlanClient.postForm(endpoints.tokenUrl, body: callback.exchangeForm)
        let outcome = try chatgptFinishSignIn(
            attempt: attempt, callback: callback, status: status, body: body,
            registration: registration, nowEpochSeconds: JSTDay.nowEpochSeconds()
        )
        switch outcome {
        case .differentAccount(let revokeForm, let message):
            // 既存の登録は書き換えず、受け取ったばかりのセッションは失効させる。
            if let revokeForm { await Self.revoke(form: revokeForm) }
            throw SessionError.message(message)
        case .accepted(let newRegistration, let newTokens, let revokePrevious):
            // 別アカウントに切り替えるなら、前のアカウントのセッションは閉じておく。
            if revokePrevious, let old = tokens, let oldRegistration = registration,
               let form = chatgptRevokeForm(tokens: old, registration: oldRegistration) {
                await Self.revoke(form: form)
            }
            save(registration: newRegistration)
            save(tokens: newTokens)
            models = []
            KeychainStore.delete(key: Key.pendingClientID)
        }
    }

    func cancelSignIn() {
        activeServer?.stop()
        browser.close()
    }

    // MARK: - トークン

    /// 期限が近ければ更新してから返す (いつ更新するかはコア)。更新は直列化する
    /// (更新用トークンは使い捨て)。
    func validAccessToken() async throws -> String {
        guard let tokens else { throw SessionError.notSignedIn }
        if !chatgptNeedsRefresh(tokens: tokens, nowEpochSeconds: JSTDay.nowEpochSeconds()) { return tokens.accessToken }
        return try await refresh().accessToken
    }

    @discardableResult
    func refresh() async throws -> ChatGptTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let current = tokens, let registration else { throw SessionError.notSignedIn }
        guard let form = chatgptRefreshForm(tokens: current, registration: registration) else {
            // 更新用トークンが無い。持っていても使えないトークンは消して、ログインし直してもらう
            // (残すと画面は「連携中」のまま、探すたびに失敗する)。
            dropTokens()
            throw SessionError.message(chatgptSignInExpiredMessage())
        }
        let task = Task { () throws -> ChatGptTokens in
            let (status, body) = try await ChatGPTPlanClient.postForm(chatgptEndpoints().tokenUrl, body: form)
            // 待っている間にサインアウトや別のサインインが入ったら、古いものを書き戻さない。
            guard self.tokens?.refreshToken == current.refreshToken else { throw SessionError.notSignedIn }
            switch chatgptReadRefresh(status: status, body: body, previous: current,
                                      nowEpochSeconds: JSTDay.nowEpochSeconds()) {
            case .renewed(let renewed):
                self.save(tokens: renewed)
                return renewed
            case .signInAgain(let message):
                // 使えない更新用トークンは消して、同じ client_id でログインし直してもらう。
                self.clearTokens()
                throw SessionError.message(message)
            case .failed(let message):
                throw SessionError.message(message)
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    // MARK: - モデル

    func loadModelsIfNeeded() async throws {
        guard models.isEmpty, canUsePlan else { return }
        do {
            models = try await ChatGPTPlanClient.listModels(accessToken: validAccessToken())
        } catch let error as ChatGPTPlanClient.Failure {
            settle(error.failure)
            throw error
        }
    }

    /// 利用者が選んだモデル。選んでいなければ nil。
    var savedModel: String? {
        get { UserDefaults.standard.string(forKey: Key.model) }
        set { UserDefaults.standard.set(newValue, forKey: Key.model) }
    }

    /// 推論に使うモデル。どれにするか (選んだものが一覧に残っているか・無ければどれか) はコア。
    func resolvedModel() async throws -> String {
        try await loadModelsIfNeeded()
        guard let slug = naturalSearchPickModel(available: models.map(\.slug), saved: savedModel) else {
            throw SessionError.message("この ChatGPT アカウントで使えるモデルがありません")
        }
        return slug
    }

    // MARK: - サインアウト

    /// 失効を試してからローカルのトークンを消す。登録 (client_id / アカウント) は残す。
    /// - Returns: リモートの失効を確認できたか。
    @discardableResult
    func signOut() async -> Bool {
        // 更新中なら差し替わった後の更新用トークンを失効させる。
        _ = try? await refreshTask?.value
        var revoked = false
        if let tokens, let registration, let form = chatgptRevokeForm(tokens: tokens, registration: registration) {
            revoked = await Self.revoke(form: form)
        }
        clearTokens()
        models = []
        return revoked
    }

    /// 失敗を受けた後始末。「ログインし直し」の失敗 (コアの判断) ならトークンを消す
    /// (残すと画面は「連携中」のまま、探すたびに同じ失敗になる)。
    func settle(_ failure: ChatGptFailure) {
        if failure.signInAgain { dropTokens() }
    }

    /// トークンだけ消す。登録は残す。
    private func dropTokens() {
        clearTokens()
        models = []
    }

    /// 失効エンドポイント (discovery から引く。採ってよいかはコア) へ POST する。空の 200 が成功。
    @discardableResult
    private static func revoke(form: String) async -> Bool {
        guard let discovery = try? await ChatGPTPlanClient.get(chatgptEndpoints().discoveryUrl),
              let endpoint = chatgptRevocationEndpoint(discoveryBody: discovery),
              let (status, _) = try? await ChatGPTPlanClient.postForm(endpoint, body: form) else { return false }
        return status == 200
    }

    // MARK: - 保存

    private func save(registration: ChatGptRegistration) {
        self.registration = registration
        Self.store(StoredRegistration(registration), key: Key.registration)
    }

    private func save(tokens: ChatGptTokens) {
        self.tokens = tokens
        Self.store(StoredTokens(tokens), key: Key.tokens)
    }

    private func clearTokens() {
        tokens = nil
        KeychainStore.delete(key: Key.tokens)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let json = KeychainStore.get(key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private static func store<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        KeychainStore.set(String(decoding: data, as: UTF8.self), forKey: key)
    }

    private static func secureRandom(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw SessionError.message("乱数を作れませんでした")
        }
        return Data(bytes)
    }
}

// MARK: - Keychain に置く形

/// コアの型は Codable でないので、置くときだけ写す。
private struct StoredRegistration: Codable {
    let clientID: String
    let subject: String
    let email: String?

    init(_ r: ChatGptRegistration) {
        clientID = r.clientId
        subject = r.subject
        email = r.email
    }

    var value: ChatGptRegistration { ChatGptRegistration(clientId: clientID, subject: subject, email: email) }
}

private struct StoredTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let idToken: String?
    let scopes: [String]
    let expiresAt: Int64

    init(_ t: ChatGptTokens) {
        accessToken = t.accessToken
        refreshToken = t.refreshToken
        idToken = t.idToken
        scopes = t.scopes
        expiresAt = t.expiresAt
    }

    var value: ChatGptTokens {
        ChatGptTokens(accessToken: accessToken, refreshToken: refreshToken, idToken: idToken,
                      scopes: scopes, expiresAt: expiresAt)
    }
}

private extension ChatGptAuthError {
    /// コアが組んだ文言。どの case も `message` 1 つを持つ。
    var message: String {
        let payload = Mirror(reflecting: self).children.first?.value
        if let text = payload as? String { return text }
        if let payload, let text = Mirror(reflecting: payload).children.first?.value as? String { return text }
        return "ChatGPT とつなげませんでした"
    }
}
