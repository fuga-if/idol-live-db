import CryptoKit
import Foundation

/// Sign in with ChatGPT (オープンソース向けの ChatGPT プラン利用フロー) の OAuth 部分。
///
/// 試作。仕様は developers.openai.com/siwc/token-sharing-open-source の
/// sign-in / profiles-and-sessions / errors-and-recovery が正。
/// - 初回は `client_id=dynamic_agent_client` で登録し、callback で返る `oaiapp_...` を以後使う
/// - リダイレクトは `http://127.0.0.1:<port>/auth/callback` 固定 (ポートだけ可変)
/// - クライアントシークレットは無い (PKCE S256)
enum ChatGPTPlanAuth {
    static let issuer = "https://auth.openai.com"
    static let authorizeEndpoint = URL(string: "https://auth.openai.com/api/accounts/authorize")!
    static let tokenEndpoint = URL(string: "https://auth.openai.com/api/accounts/oauth/token")!
    static let discoveryURL = URL(string: "https://auth.openai.com/.well-known/openid-configuration")!
    static let resource = "https://api.openai.com/v1"
    static let dynamicClientID = "dynamic_agent_client"
    static let planScope = "chatgpt.tokens.use.direct"
    static let scope = "openid profile email offline_access resource.invoke \(planScope)"
    /// 同意画面に出るアプリ名。インストールをまたいで同じ名前を使う。
    static let agentName = "アイドルライブDB"

    // MARK: - 認可 URL

    struct PendingAttempt: Sendable {
        let clientID: String
        let isNewRegistration: Bool
        /// プラン利用を外した後に許可し直すとき。保存済み client_id の再認可は同意画面を
        /// 飛ばすので、`prompt=consent` で出させないと scope を足せない。
        let forceConsent: Bool
        let state: String
        let nonce: String
        let codeVerifier: String
        let redirectURI: String
    }

    static func newAttempt(savedClientID: String?, redirectURI: String, forceConsent: Bool = false) -> PendingAttempt {
        PendingAttempt(
            clientID: savedClientID ?? dynamicClientID,
            isNewRegistration: savedClientID == nil,
            forceConsent: forceConsent && savedClientID != nil,
            state: randomURLSafe(32),
            nonce: randomURLSafe(32),
            codeVerifier: randomURLSafe(64),
            redirectURI: redirectURI
        )
    }

    static func authorizeURL(
        for attempt: PendingAttempt,
        hostID: String,
        idTokenHint: String?,
        loginHint: String?
    ) -> URL {
        var items: [URLQueryItem] = [
            .init(name: "client_id", value: attempt.clientID),
            .init(name: "ext_agent_host_id", value: hostID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: attempt.redirectURI),
            .init(name: "scope", value: scope),
            .init(name: "resource", value: resource),
            .init(name: "state", value: attempt.state),
            .init(name: "nonce", value: attempt.nonce),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: codeChallenge(for: attempt.codeVerifier)),
        ]
        if attempt.isNewRegistration {
            // 名前のヒントは初回登録だけ。再認可では送らない。
            items.append(.init(name: "agent_name_hint", value: agentName))
        } else {
            if let idTokenHint { items.append(.init(name: "id_token_hint", value: idTokenHint)) }
            if let loginHint { items.append(.init(name: "login_hint", value: loginHint)) }
            if attempt.forceConsent { items.append(.init(name: "prompt", value: "consent")) }
        }
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        // URLQueryItem は `+` や `@` を素通しするので、値を自前で符号化する。
        components.percentEncodedQuery = items
            .map { "\($0.name)=\(formEncode($0.value ?? ""))" }
            .joined(separator: "&")
        return components.url!
    }

    // MARK: - callback

    struct CallbackResult: Sendable {
        let code: String
        let issuedClientID: String
        let callbackScope: String?
    }

    enum AuthError: LocalizedError {
        case accessDenied(String?)
        case oauth(String, String?)
        case stateMismatch
        case missingCode
        case registrationIncomplete
        case clientMismatch(expected: String, got: String)
        case tokenEndpoint(status: Int, body: String)
        case idToken(String)
        case planScopeMissing([String])
        case notSignedIn
        case noRefreshToken
        case differentAccount

        var errorDescription: String? {
            switch self {
            case .accessDenied(let detail):
                "ChatGPT 側で許可されませんでした\(detail.map { " (\($0))" } ?? "")"
            case .oauth(let code, let detail):
                "認可エラー: \(code)\(detail.map { " — \($0)" } ?? "")"
            case .stateMismatch:
                "state が一致しません (別の試行の callback の可能性)"
            case .missingCode:
                "callback に code がありません"
            case .registrationIncomplete:
                "初回登録の callback に発行済み client_id がありません"
            case .clientMismatch(let expected, let got):
                "callback の client_id が違います (期待 \(expected) / 実際 \(got))"
            case .tokenEndpoint(let status, let body):
                "トークン交換に失敗しました (HTTP \(status)): \(body)"
            case .idToken(let reason):
                "ID トークンの検証に失敗しました: \(reason)"
            case .planScopeMissing(let scopes):
                "ChatGPT プランの利用が許可されていません (scope: \(scopes.joined(separator: " ")))"
            case .notSignedIn:
                "ChatGPT にサインインしていません"
            case .noRefreshToken:
                "更新用のトークンがありません。サインインし直してください"
            case .differentAccount:
                "前回と別の ChatGPT アカウントでサインインされました。別のアカウントを使うときは「別のアカウントで登録」から入ってください"
            }
        }
    }

    static func parseCallback(_ components: URLComponents, attempt: PendingAttempt) throws -> CallbackResult {
        let query = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        // エラーでも state は先に照合する (他の試行の結果を拾わない)。
        guard query["state"] == attempt.state else { throw AuthError.stateMismatch }
        if let error = query["error"] {
            if error == "access_denied" { throw AuthError.accessDenied(query["error_description"]) }
            throw AuthError.oauth(error, query["error_description"])
        }
        guard let code = query["code"], !code.isEmpty else { throw AuthError.missingCode }

        let callbackClient = query["client_id"].flatMap { $0.isEmpty ? nil : $0 }
        let issued: String
        if attempt.isNewRegistration {
            guard let callbackClient, callbackClient != dynamicClientID else {
                throw AuthError.registrationIncomplete
            }
            issued = callbackClient
        } else {
            // 再認可では省略されうる。違う ID が来たら登録を差し替えずに弾く。
            if let callbackClient, callbackClient != attempt.clientID {
                throw AuthError.clientMismatch(expected: attempt.clientID, got: callbackClient)
            }
            issued = attempt.clientID
        }
        return CallbackResult(code: code, issuedClientID: issued, callbackScope: query["scope"])
    }

    // MARK: - トークンエンドポイント

    struct TokenResponse: Decodable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let idToken: String?
        let tokenType: String?
        let expiresIn: Double?
        let scope: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case idToken = "id_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case scope
        }
    }

    static func exchange(code: String, clientID: String, attempt: PendingAttempt) async throws -> TokenResponse {
        try await postToken([
            "grant_type": "authorization_code",
            "client_id": clientID,
            "code": code,
            "code_verifier": attempt.codeVerifier,
            "redirect_uri": attempt.redirectURI,
            "resource": resource,
        ])
    }

    /// `scope` は送らない (送ると付与範囲が変わりうる)。refresh_token は毎回差し替わる。
    static func refresh(refreshToken: String, clientID: String) async throws -> TokenResponse {
        try await postToken([
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
            "resource": resource,
        ])
    }

    /// サインアウト時に更新可能なセッションを失効させる。空の 200 が成功。
    static func revoke(refreshToken: String, clientID: String) async throws {
        let (discovery, _) = try await URLSession.shared.data(from: discoveryURL)
        let object = try JSONSerialization.jsonObject(with: discovery) as? [String: Any]
        guard let endpoint = (object?["revocation_endpoint"] as? String).flatMap(URL.init(string:)) else {
            throw URLError(.badServerResponse)
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "token": refreshToken,
            "token_type_hint": "refresh_token",
            "client_id": clientID,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw AuthError.tokenEndpoint(status: status, body: String(decoding: data, as: UTF8.self))
        }
    }

    private static func postToken(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AuthError.tokenEndpoint(status: status, body: String(decoding: data, as: UTF8.self))
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    // MARK: - ID トークン

    struct IDTokenClaims: Sendable {
        let subject: String
        let email: String?
    }

    /// 署名検証は省いている (試作)。トークンエンドポイントから TLS で直接受け取った
    /// ID トークンなので OIDC Core 3.1.3.7 の範囲で許容されるが、本実装では JWKS で検証する。
    /// iss / aud / exp / nonce は照合する。
    static func validateIDToken(_ token: String, clientID: String, nonce: String?) throws -> IDTokenClaims {
        let segments = token.split(separator: ".")
        guard segments.count == 3, let payload = base64URLDecode(String(segments[1])),
              let claims = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { throw AuthError.idToken("JWT として読めません") }

        guard claims["iss"] as? String == issuer else { throw AuthError.idToken("iss が違います") }
        let audiences: [String] = (claims["aud"] as? [String]) ?? [(claims["aud"] as? String)].compactMap { $0 }
        guard audiences.contains(clientID) else { throw AuthError.idToken("aud に client_id がありません") }
        if let exp = claims["exp"] as? Double, Date(timeIntervalSince1970: exp) < Date().addingTimeInterval(-60) {
            throw AuthError.idToken("期限切れです")
        }
        if let nonce, claims["nonce"] as? String != nonce { throw AuthError.idToken("nonce が一致しません") }
        guard let subject = claims["sub"] as? String else { throw AuthError.idToken("sub がありません") }

        let profile = claims["https://api.openai.com/profile"] as? [String: Any]
        let email = (claims["email"] as? String) ?? (profile?["email"] as? String)
        return IDTokenClaims(subject: subject, email: email)
    }

    // MARK: - 小物

    static func codeChallenge(for verifier: String) -> String {
        base64URLEncode(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafe(_ byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for i in bytes.indices { bytes[i] = UInt8.random(in: .min ... .max) }
        return base64URLEncode(Data(bytes))
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func formEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? value
    }

    private static func formBody(_ fields: [String: String]) -> Data {
        Data(fields.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").utf8)
    }
}
