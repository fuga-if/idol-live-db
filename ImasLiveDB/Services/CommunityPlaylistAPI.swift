import Foundation

/// `CommunityPlaylistStoring` の Worker 実装 (`/playlists`)。
/// 一覧と 1 つ取りはエッジにキャッシュされる (公開・取り下げは数分遅れて見える)。
struct CommunityPlaylistAPI: CommunityPlaylistStoring {
    func page(before: String?) async throws -> CommunityPlaylistPage {
        try await APIClient.shared.request("GET", path: "/playlists", query: before.map { ["before": $0] })
    }

    func playlist(id: String) async throws -> CommunityPlaylist {
        try await APIClient.shared.request("GET", path: "/playlists/\(id)")
    }

    func mine() async throws -> [CommunityPlaylist] {
        let page: CommunityPlaylistPage = try await APIClient.shared.request("GET", path: "/me/playlists", authorized: true)
        return page.playlists
    }

    func publish(_ input: CommunityPlaylistInput) async throws -> CommunityPlaylist {
        try await APIClient.shared.request("POST", path: "/playlists", body: input, authorized: true)
    }

    func update(id: String, _ input: CommunityPlaylistInput) async throws -> CommunityPlaylist {
        try await APIClient.shared.request("PUT", path: "/playlists/\(id)", body: input, authorized: true)
    }

    func remove(id: String) async throws {
        try await APIClient.shared.requestVoid("DELETE", path: "/playlists/\(id)", authorized: true)
    }
}
