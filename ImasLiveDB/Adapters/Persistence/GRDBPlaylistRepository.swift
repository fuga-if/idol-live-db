import Foundation

/// `PlaylistStoring` の端末 DB アダプタ。プレイリストは端末にしか無い。
struct GRDBPlaylistRepository: PlaylistStoring {
    let database: AppDatabase

    func summaries() async throws -> [PlaylistSummary] { try await database.playlistSummariesAsync() }
    func songIds(playlistId: String) async throws -> [String] {
        try await database.playlistSongIdsAsync(playlistId: playlistId)
    }
    func create(name: String) async throws -> Playlist { try database.createPlaylist(name: name) }
    func rename(id: String, name: String) async throws { try database.renamePlaylist(id: id, name: name) }
    func delete(id: String) async throws { try database.deletePlaylist(id: id) }
    func setSongIds(playlistId: String, songIds: [String]) async throws {
        try database.setPlaylistSongIds(playlistId: playlistId, songIds: songIds)
    }
}
