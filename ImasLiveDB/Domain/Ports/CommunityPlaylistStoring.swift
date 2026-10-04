import Foundation

/// みんなのプレイリスト (サーバ) の読み書き。公開・差し替え・取り下げはログインが要る。
protocol CommunityPlaylistStoring: Sendable {
    func page(before: String?) async throws -> CommunityPlaylistPage
    func playlist(id: String) async throws -> CommunityPlaylist
    func mine() async throws -> [CommunityPlaylist]
    func publish(_ input: CommunityPlaylistInput) async throws -> CommunityPlaylist
    func update(id: String, _ input: CommunityPlaylistInput) async throws -> CommunityPlaylist
    func remove(id: String) async throws
}
