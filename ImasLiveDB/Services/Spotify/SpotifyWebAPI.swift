import Foundation

/// Spotify の認可と Web API の通信だけ。状態は持たない (`SpotifyService` が持つ)。
///
/// 使う口は開発者モード (2026-02 改定後) で残っているものだけ:
/// `/me`・`/search` (limit は 10 まで)・`POST /me/playlists`・`POST /playlists/{id}/items`。
enum SpotifyWebAPI {
    static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!
    static let apiBase = URL(string: "https://api.spotify.com/v1/")!

    struct Tokens: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    struct Track: Sendable {
        let id: String
        let name: String
        let artists: [String]
        let album: String
        let uri: String
    }

    /// 失敗の種類。文言はコア (`spotifyFailureMessage`) が決める。
    struct Failure: LocalizedError {
        let kind: SpotifyFailure
        var errorDescription: String? { spotifyFailureMessage(failure: kind) }
    }

    // MARK: - 認可 (PKCE)

    static func authorizeURL(clientId: String, redirectURI: String, scopes: String,
                             state: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: scopes),
            .init(name: "state", value: state),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: codeChallenge),
        ]
        return components.url!
    }

    static func exchangeCode(_ code: String, verifier: String, clientId: String, redirectURI: String) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientId,
            "code_verifier": verifier,
        ], previousRefreshToken: nil)
    }

    static func refresh(_ refreshToken: String, clientId: String) async throws -> Tokens {
        try await tokenRequest([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId,
        ], previousRefreshToken: refreshToken)
    }

    private static func tokenRequest(_ form: [String: String], previousRefreshToken: String?) async throws -> Tokens {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        // `+` は URLComponents が符号化しないので、フォームとして読まれると空白に化ける。
        request.httpBody = body.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
            .data(using: .utf8)
        let (data, response) = try await send(request)
        guard response.statusCode == 200 else {
            // 400 invalid_grant = 更新用の鍵が失効した (連携の解除・パスワード変更)。
            throw Failure(kind: response.statusCode == 400 ? .sessionExpired : .other)
        }
        struct Payload: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        // 更新で新しい鍵が返らなければ前の鍵を使い続ける。
        guard let refresh = payload.refresh_token ?? previousRefreshToken else { throw Failure(kind: .other) }
        return Tokens(accessToken: payload.access_token, refreshToken: refresh,
                      expiresAt: Date().addingTimeInterval(payload.expires_in - 60))
    }

    // MARK: - Web API

    static func displayName(accessToken: String) async throws -> String? {
        struct Me: Decodable { let display_name: String?; let id: String }
        let data = try await api("me", accessToken: accessToken)
        let me = try JSONDecoder().decode(Me.self, from: data)
        return me.display_name ?? me.id
    }

    static func searchTracks(_ query: String, accessToken: String) async throws -> [Track] {
        struct Response: Decodable {
            struct Tracks: Decodable { let items: [Item] }
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable { let name: String }
                let id: String
                let name: String
                let uri: String
                let artists: [Artist]
                let album: Album
            }
            let tracks: Tracks
        }
        let data = try await api("search", query: [
            "q": query, "type": "track", "limit": "10", "market": "from_token",
        ], accessToken: accessToken)
        return try JSONDecoder().decode(Response.self, from: data).tracks.items.map {
            Track(id: $0.id, name: $0.name, artists: $0.artists.map(\.name), album: $0.album.name, uri: $0.uri)
        }
    }

    /// 非公開のプレイリストを作る。返すのは (id, 開く URL)。
    static func createPlaylist(name: String, description: String, accessToken: String) async throws -> (id: String, url: URL) {
        struct Created: Decodable {
            struct Links: Decodable { let spotify: String }
            let id: String
            let external_urls: Links
        }
        let data = try await api("me/playlists", method: "POST", json: [
            "name": name, "description": description, "public": false,
        ], accessToken: accessToken)
        let created = try JSONDecoder().decode(Created.self, from: data)
        guard let url = URL(string: created.external_urls.spotify) else { throw Failure(kind: .other) }
        return (created.id, url)
    }

    /// 曲を足す。1 回で 100 曲までなので分けて送る。
    static func addItems(playlistId: String, uris: [String], accessToken: String) async throws {
        for start in stride(from: 0, to: uris.count, by: 100) {
            let chunk = Array(uris[start..<min(start + 100, uris.count)])
            _ = try await api("playlists/\(playlistId)/items", method: "POST", json: ["uris": chunk],
                              accessToken: accessToken)
        }
    }

    static func trackURL(id: String) -> URL { URL(string: "https://open.spotify.com/track/\(id)")! }

    // MARK: - 通信

    private static func api(_ path: String, method: String = "GET", query: [String: String] = [:],
                            json: [String: Any]? = nil, accessToken: String) async throws -> Data {
        var components = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        // 429 は Retry-After だけ待って 1 回だけやり直す。
        for attempt in 0..<2 {
            let (data, response) = try await send(request)
            switch response.statusCode {
            case 200..<300: return data
            case 401: throw Failure(kind: .sessionExpired)
            case 403: throw Failure(kind: .notRegistered)
            case 429 where attempt == 0:
                let wait = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
                try await Task.sleep(for: .seconds(min(wait, 10)))
            case 429: throw Failure(kind: .rateLimited)
            default: throw Failure(kind: .other)
            }
        }
        throw Failure(kind: .other)
    }

    private static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure(kind: .other) }
            return (data, http)
        } catch let failure as Failure {
            throw failure
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw Failure(kind: .network)
        }
    }
}
