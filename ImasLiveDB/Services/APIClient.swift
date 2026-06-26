import Foundation
import OSLog

private let logger = Logger(subsystem: "com.fugaif.ImasLiveDB", category: "api_client")

// MARK: - APIClientError

enum APIClientError: LocalizedError, Sendable {
    case notAuthorized
    case rateLimited(retryAfter: Int?)
    case conflict(message: String?)
    case notFound
    case server(status: Int, body: String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "認証エラー"
        case .rateLimited:
            return "1日の上限に達しました。明日また試してください"
        case .conflict(let m):
            return m ?? "重複しています"
        case .notFound:
            return "見つかりませんでした"
        case .server(let s, let body):
            // Workers の catch ハンドラは {"error": "..."} 形式で詳細を返すので、本文を抽出して見せる
            let detail = (body?.data(using: .utf8))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                .flatMap { $0["error"] as? String }
                ?? body?.prefix(120).description
            if let detail, !detail.isEmpty {
                return "サーバーエラー (\(s)): \(detail)"
            }
            return "サーバーエラー (\(s))"
        case .decoding:
            return "レスポンス形式エラー"
        case .transport:
            return "通信エラー"
        }
    }
}

// MARK: - APIClient

actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        dec.dateDecodingStrategy = .secondsSince1970
        self.decoder = dec

        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .secondsSince1970
        self.encoder = enc
    }

    // MARK: - Request with Decodable response

    /// - Parameter treatConflictAsSuccess: 409 を成功扱いし、本文を T としてデコードして返す。
    ///   名前で一意なリソース (タグ等) の冪等作成に使う (サーバは 409 で既存リソースを返す)。
    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        query: [String: String]? = nil,
        authorized: Bool = false,
        deviceIdHeader: Bool = true,
        treatConflictAsSuccess: Bool = false
    ) async throws -> T {
        let data = try await performRequest(
            method,
            path: path,
            body: body,
            queryItems: query.map { $0.map { URLQueryItem(name: $0.key, value: $0.value) } },
            authorized: authorized,
            deviceIdHeader: deviceIdHeader,
            treatConflictAsSuccess: treatConflictAsSuccess
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    /// Multi-value query params (e.g. repeated `type=` keys).
    func request<T: Decodable>(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        queryItems: [URLQueryItem],
        authorized: Bool = false,
        deviceIdHeader: Bool = true
    ) async throws -> T {
        let data = try await performRequest(
            method,
            path: path,
            body: body,
            queryItems: queryItems,
            authorized: authorized,
            deviceIdHeader: deviceIdHeader
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    // MARK: - Void request

    func requestVoid(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        query: [String: String]? = nil,
        authorized: Bool = false,
        deviceIdHeader: Bool = true
    ) async throws {
        _ = try await performRequest(
            method,
            path: path,
            body: body,
            queryItems: query.map { $0.map { URLQueryItem(name: $0.key, value: $0.value) } },
            authorized: authorized,
            deviceIdHeader: deviceIdHeader
        )
    }

    // MARK: - Raw data (for custom deserialization)

    func requestData(
        _ method: String,
        path: String,
        body: (any Encodable)? = nil,
        query: [String: String]? = nil,
        authorized: Bool = false,
        deviceIdHeader: Bool = true
    ) async throws -> Data {
        try await performRequest(
            method,
            path: path,
            body: body,
            queryItems: query.map { $0.map { URLQueryItem(name: $0.key, value: $0.value) } },
            authorized: authorized,
            deviceIdHeader: deviceIdHeader
        )
    }

    /// 明示した Bearer トークンでリクエストする (sliding refresh 専用)。
    /// 通常の authorized 経路 (AuthService.bearerToken) とは独立し、401 でも再 refresh しない。
    func requestWithBearer<T: Decodable>(
        _ method: String,
        path: String,
        bearer: String,
        body: (any Encodable)? = nil
    ) async throws -> T {
        let data = try await performRequest(
            method, path: path, body: body, queryItems: nil,
            authorized: false, deviceIdHeader: true,
            bearerOverride: bearer, allowRefresh: false
        )
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }

    // MARK: - Core

    private func performRequest(
        _ method: String,
        path: String,
        body: (any Encodable)?,
        queryItems: [URLQueryItem]?,
        authorized: Bool,
        deviceIdHeader: Bool,
        treatConflictAsSuccess: Bool = false,
        bearerOverride: String? = nil,
        allowRefresh: Bool = true
    ) async throws -> Data {
        var components = URLComponents(
            url: APIEndpoints.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        if let queryItems {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw APIClientError.transport(URLError(.badURL))
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if deviceIdHeader {
            req.setValue(DeviceIdentity.shared, forHTTPHeaderField: "X-Device-Id")
        }

        if let bearerOverride {
            req.setValue("Bearer \(bearerOverride)", forHTTPHeaderField: "Authorization")
        } else if authorized, let token = await AuthService.shared.bearerToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // 正規アプリ証明 (クローンただ乗り対策)。取得済みなら毎リクエストに載せる。
        if let appToken = await AppAttestService.shared.token() {
            req.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        }

        if let body {
            do {
                req.httpBody = try encoder.encode(body)
            } catch {
                throw APIClientError.transport(error)
            }
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIClientError.transport(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let bodyString = String(data: data, encoding: .utf8)
            let status = http.statusCode
            logger.warning("HTTP \(status) \(method) \(path)")
            switch status {
            case 401, 403:
                // 401 (期限切れ等) は Apple 再認証なしの sliding refresh を 1 回試み、
                // 成功したら同じリクエストをリトライする (自動再ログイン)。
                // 403 (BAN) や refresh 経路自身 (bearerOverride) は対象外。
                if status == 401, authorized, allowRefresh, bearerOverride == nil,
                   await AuthService.shared.refreshSession() {
                    return try await performRequest(
                        method, path: path, body: body, queryItems: queryItems,
                        authorized: authorized, deviceIdHeader: deviceIdHeader,
                        treatConflictAsSuccess: treatConflictAsSuccess,
                        allowRefresh: false
                    )
                }
                if authorized {
                    // 401 = セッション失効 (リフレッシュ不可) → ログイン導線を出すため isSignedIn も落とす。
                    // 403 = BAN 等でトークンは有効なので従来どおりトークンだけ破棄。
                    if status == 401 {
                        await AuthService.shared.handleSessionExpired()
                    } else {
                        await AuthService.shared.invalidateToken()
                    }
                }
                throw APIClientError.notAuthorized
            case 404:
                throw APIClientError.notFound
            case 409:
                // 名前で一意なリソースの冪等作成: サーバは 409 で既存リソースを本文に返すので成功扱い。
                if treatConflictAsSuccess { return data }
                let message = extractErrorMessage(from: data)
                throw APIClientError.conflict(message: message)
            case 429:
                let retryAfter = (response as? HTTPURLResponse)?
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap { Int($0) }
                throw APIClientError.rateLimited(retryAfter: retryAfter)
            default:
                throw APIClientError.server(status: status, body: bodyString)
            }
        }

        return data
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["error"] as? String
    }
}
