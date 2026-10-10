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
        /// 許された権限 (空白区切り)。プレイリストだけの頃に保存した鍵には無い。
        var scope: String?
    }

    /// `GET /me/player` の要るところだけ。
    struct PlayerState: Sendable {
        let trackId: String?
        let progressMs: Int
        let durationMs: Int?
        let isPlaying: Bool
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
            let scope: String?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        // 更新で新しい鍵が返らなければ前の鍵を使い続ける。
        guard let refresh = payload.refresh_token ?? previousRefreshToken else { throw Failure(kind: .other) }
        return Tokens(accessToken: payload.access_token, refreshToken: refresh,
                      expiresAt: Date().addingTimeInterval(payload.expires_in - 60),
                      scope: payload.scope)
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

    // MARK: - 鳴らす (Spotify アプリを操作する。Premium が要る)

    static func devices(accessToken: String) async throws -> [SpotifyDevice] {
        struct Response: Decodable {
            struct Device: Decodable { let id: String?; let is_active: Bool; let is_restricted: Bool; let type: String }
            let devices: [Device]
        }
        let data = try await api("me/player/devices", accessToken: accessToken)
        return try JSONDecoder().decode(Response.self, from: data).devices.map {
            SpotifyDevice(id: $0.id, isActive: $0.is_active, isRestricted: $0.is_restricted, kind: $0.type)
        }
    }

    /// 曲を並べて、`offset` 番目から鳴らし始める。
    ///
    /// 後ろの曲は Spotify の「次に再生」(`POST /me/player/queue`) には積まない。そちらは鳴らし直しても
    /// 消えず (空にする口が無い)、次の再生に前の残りが割り込むため。並べる曲はすべてここで渡す。
    static func play(uris: [String], offset: Int, deviceId: String, accessToken: String) async throws {
        _ = try await api("me/player/play", method: "PUT", query: ["device_id": deviceId],
                          json: ["uris": uris, "offset": ["position": offset]], accessToken: accessToken)
    }

    static func pause(accessToken: String) async throws {
        _ = try await api("me/player/pause", method: "PUT", accessToken: accessToken)
    }

    static func resume(accessToken: String) async throws {
        _ = try await api("me/player/play", method: "PUT", accessToken: accessToken)
    }

    static func seek(ms: Int, accessToken: String) async throws {
        _ = try await api("me/player/seek", method: "PUT", query: ["position_ms": "\(max(0, ms))"], accessToken: accessToken)
    }

    static func next(accessToken: String) async throws {
        _ = try await api("me/player/next", method: "POST", accessToken: accessToken)
    }

    static func previous(accessToken: String) async throws {
        _ = try await api("me/player/previous", method: "POST", accessToken: accessToken)
    }

    /// 今鳴っているもの。何も鳴らしていなければ nil (204)。
    static func playerState(accessToken: String) async throws -> PlayerState? {
        struct Response: Decodable {
            struct Item: Decodable { let id: String?; let duration_ms: Int? }
            let is_playing: Bool
            let progress_ms: Int?
            let item: Item?
        }
        let data = try await api("me/player", accessToken: accessToken)
        guard !data.isEmpty else { return nil }
        let r = try JSONDecoder().decode(Response.self, from: data)
        return PlayerState(trackId: r.item?.id, progressMs: r.progress_ms ?? 0,
                           durationMs: r.item?.duration_ms, isPlaying: r.is_playing)
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
            case 403: throw Failure(kind: forbiddenKind(data))
            // 鳴らす口の 404 は「鳴らす先が無い」(NO_ACTIVE_DEVICE)。
            case 404 where path.hasPrefix("me/player"): throw Failure(kind: .noDevice)
            case 429 where attempt == 0:
                let wait = Double(response.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2
                try await Task.sleep(for: .seconds(min(wait, 10)))
            case 429: throw Failure(kind: .rateLimited)
            default: throw Failure(kind: .other)
            }
        }
        throw Failure(kind: .other)
    }

    /// 403 の中身で分ける: Premium が要る / 権限が足りない / アプリに登録されていない。
    private static func forbiddenKind(_ data: Data) -> SpotifyFailure {
        let body = String(data: data, encoding: .utf8) ?? ""
        if body.contains("PREMIUM_REQUIRED") { return .premiumRequired }
        // 「今はできない」(再生中に再生・先頭で前へ など)。失敗として伝えず、状態を読み直せば足りる。
        if body.contains("Restriction") { return .other }
        if body.localizedCaseInsensitiveContains("scope") { return .playbackNotAllowed }
        return .notRegistered
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
