import Foundation

/// プレイリストの読み書き (端末ローカル)。並びの規則はコア (`playlistAppendSongs` / `playlistMoveSong`)。
protocol PlaylistStoring: Sendable {
    func summaries() async throws -> [PlaylistSummary]
    func songIds(playlistId: String) async throws -> [String]
    func create(name: String) async throws -> Playlist
    func rename(id: String, name: String) async throws
    func delete(id: String) async throws
    /// 曲の並びを丸ごと書き直す。
    func setSongIds(playlistId: String, songIds: [String]) async throws
}

extension PlaylistStoring {
    /// 曲を後ろに足す (既にある曲は足さない)。
    func append(playlistId: String, songIds adding: [String]) async throws {
        let existing = try await songIds(playlistId: playlistId)
        try await setSongIds(playlistId: playlistId,
                             songIds: playlistAppendSongs(existing: existing, adding: adding))
    }
}
