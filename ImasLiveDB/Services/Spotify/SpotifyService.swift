import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Spotify 連携の状態 (Client ID・ログイン) と、曲を探す・プレイリストに書き出す操作。
///
/// Client ID は利用者が自分の Spotify のアプリで発行したもの (理由は imas-core `domain/spotify.rs`)。
/// 更新用の鍵は Keychain、Client ID と表示名は UserDefaults。端末の外には出さない。
/// どの検索結果を同じ曲と見なすかはコア (`spotifyPickTrack`) が決める。
@MainActor
@Observable
final class SpotifyService {
    static let shared = SpotifyService()

    private enum Key {
        static let clientId = "spotify.client_id"
        static let accountName = "spotify.account_name"
        static let tokens = "spotify.tokens"
        static let trackIds = "spotify.track_ids"
    }

    private(set) var clientId: String?
    private(set) var accountName: String?
    private(set) var isSigningIn = false
    private var tokens: SpotifyWebAPI.Tokens?
    /// 曲 id → Spotify の曲 id。一度見つけた曲は探し直さない。
    private var trackIds: [String: String]

    var isConnected: Bool { tokens != nil }

    private let guide = spotifySetupGuide()
    private var authSession: ASWebAuthenticationSession?
    private let presentation = PresentationAnchor()

    private init() {
        let defaults = UserDefaults.standard
        clientId = defaults.string(forKey: Key.clientId)
        accountName = defaults.string(forKey: Key.accountName)
        trackIds = defaults.dictionary(forKey: Key.trackIds) as? [String: String] ?? [:]
        tokens = KeychainStore.get(Key.tokens)
            .flatMap { $0.data(using: .utf8) }
            .flatMap { try? JSONDecoder().decode(SpotifyWebAPI.Tokens.self, from: $0) }
    }

    // MARK: - ログイン

    /// ブラウザで Spotify にログインして許可をもらう。利用者が閉じたら何もせずに戻る。
    func signIn(clientId: String) async throws {
        isSigningIn = true
        defer { isSigningIn = false }
        let verifier = Self.randomURLSafe(64)
        let state = Self.randomURLSafe(16)
        let url = SpotifyWebAPI.authorizeURL(
            clientId: clientId, redirectURI: guide.redirectUri, scopes: guide.scopes,
            state: state, codeChallenge: Self.codeChallenge(for: verifier)
        )
        guard let callback = try await openBrowser(url) else { return }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        // access_denied = 利用者が「同意しない」を押した。
        if value("error") == "access_denied" { return }
        guard value("state") == state, let code = value("code") else {
            throw SpotifyWebAPI.Failure(kind: .other)
        }
        let tokens = try await SpotifyWebAPI.exchangeCode(
            code, verifier: verifier, clientId: clientId, redirectURI: guide.redirectUri
        )
        // 名前が引けない = このアカウントがアプリに登録されていない (403)。ここで止めて伝える。
        let name = try await SpotifyWebAPI.displayName(accessToken: tokens.accessToken)
        self.clientId = clientId
        accountName = name
        store(tokens)
        UserDefaults.standard.set(clientId, forKey: Key.clientId)
        UserDefaults.standard.set(name, forKey: Key.accountName)
    }

    /// 連携をやめる。Client ID は残す (ログインし直すときに貼り直さなくてよい)。
    func signOut() {
        store(nil)
        accountName = nil
        UserDefaults.standard.removeObject(forKey: Key.accountName)
    }

    /// Client ID も忘れる (別のアプリで作り直すとき)。
    func forgetClientId() {
        signOut()
        clientId = nil
        UserDefaults.standard.removeObject(forKey: Key.clientId)
    }

    private func openBrowser(_ url: URL) async throws -> URL? {
        let scheme = URL(string: guide.redirectUri)?.scheme
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: callback)
                }
            }
            // Safari で Spotify にログイン済みなら、その続きで許可だけ押せばよいように。
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = presentation
            authSession = session
            if !session.start() { continuation.resume(returning: nil) }
        }
    }

    // MARK: - 鍵

    private func store(_ tokens: SpotifyWebAPI.Tokens?) {
        self.tokens = tokens
        let json = tokens.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        KeychainStore.set(json, forKey: Key.tokens)
    }

    /// 使える鍵。切れていれば更新する。更新もできなければログアウトして投げる。
    private func accessToken() async throws -> String {
        guard let tokens, let clientId else { throw SpotifyWebAPI.Failure(kind: .sessionExpired) }
        if tokens.expiresAt > Date() { return tokens.accessToken }
        do {
            let fresh = try await SpotifyWebAPI.refresh(tokens.refreshToken, clientId: clientId)
            store(fresh)
            return fresh.accessToken
        } catch let failure as SpotifyWebAPI.Failure where failure.kind == .sessionExpired {
            signOut()
            throw failure
        }
    }

    // MARK: - 曲

    /// 曲の Spotify のページ。見つからなければ nil。
    func trackURL(songId: String) async throws -> URL? {
        try await findTrack(songId: songId).map { SpotifyWebAPI.trackURL(id: $0.id) }
    }

    private struct FoundTrack { let id: String; let uri: String }

    private func findTrack(songId: String) async throws -> FoundTrack? {
        if let id = trackIds[songId] { return FoundTrack(id: id, uri: "spotify:track:\(id)") }
        let queries = try await Self.searchQueries(songId: songId)
        for query in queries {
            let token = try await accessToken()
            let results = try await SpotifyWebAPI.searchTracks(query, accessToken: token)
            let candidates = results.map { SpotifyTrackCandidate(name: $0.name, artists: $0.artists, album: $0.album) }
            let picked = try await Self.pickTrack(songId: songId, candidates: candidates)
            if let picked {
                let track = results[Int(picked)]
                trackIds[songId] = track.id
                UserDefaults.standard.set(trackIds, forKey: Key.trackIds)
                return FoundTrack(id: track.id, uri: track.uri)
            }
        }
        return nil
    }

    // コアへの問い合わせは main の外で (スナップショットの読み取りは nonisolated の口から)。
    nonisolated private static func searchQueries(songId: String) async throws -> [String] {
        try await AppContainer.shared.coreSnapshot.withStore { try $0.spotifySearchQueries(songId: songId) }
    }

    nonisolated private static func pickTrack(songId: String, candidates: [SpotifyTrackCandidate]) async throws -> UInt32? {
        try await AppContainer.shared.coreSnapshot.withStore {
            try $0.spotifyPickTrack(songId: songId, candidates: candidates)
        }
    }

    // MARK: - 書き出し

    struct ExportResult: Sendable {
        let playlistURL: URL?
        let added: Int
        /// Spotify で見つからなかった曲 (並びは元のまま)。
        let missingSongIds: [String]
    }

    /// 曲を探して、見つかった曲で非公開のプレイリストを作る。1 曲も無ければ作らない。
    /// 同じ曲が 2 回あれば 2 回入れる (セトリの再披露・メドレーの順を崩さない)。
    func exportPlaylist(name: String, songIds: [String],
                        progress: @MainActor (_ done: Int, _ total: Int) -> Void) async throws -> ExportResult {
        var uris: [String] = []
        var missing: [String] = []
        var found: [String: FoundTrack?] = [:]
        for (index, songId) in songIds.enumerated() {
            try Task.checkCancellation()
            progress(index, songIds.count)
            let track: FoundTrack?
            if let cached = found[songId] {
                track = cached
            } else {
                track = try await findTrack(songId: songId)
                found[songId] = track
            }
            if let track { uris.append(track.uri) } else { missing.append(songId) }
        }
        progress(songIds.count, songIds.count)
        guard !uris.isEmpty else { return ExportResult(playlistURL: nil, added: 0, missingSongIds: missing) }
        let token = try await accessToken()
        let playlist = try await SpotifyWebAPI.createPlaylist(
            name: name, description: spotifyPlaylistDescription(), accessToken: token
        )
        try await SpotifyWebAPI.addItems(playlistId: playlist.id, uris: uris, accessToken: token)
        return ExportResult(playlistURL: playlist.url, added: uris.count, missingSongIds: missing)
    }

    // MARK: - PKCE

    private static func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private final class PresentationAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .keyWindow ?? ASPresentationAnchor()
        }
    }
}
