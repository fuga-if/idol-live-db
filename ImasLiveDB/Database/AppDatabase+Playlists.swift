//  プレイリストの読み書き。**端末ローカル唯一データ**なので、expenses と同じく破壊的な移行はしない。
//
//  並べ替え・足し方 (同じ曲を 2 回入れない) は共有コア (domain/play_queue.rs)。
//  ここは行の出し入れだけ。曲の並びは「全部書き直す」1 本にする (位置の付け直しを散らさない)。

import Foundation
import GRDB

extension AppDatabase {

    func playlistSummariesAsync() async throws -> [PlaylistSummary] {
        try await dbQueue.read { db in
            let playlists = try Playlist.order(Column("updated_at").desc).fetchAll(db)
            return try playlists.map { playlist in
                let ids = try Self.songIds(db, playlistId: playlist.id)
                return PlaylistSummary(playlist: playlist, songCount: ids.count, firstSongId: ids.first)
            }
        }
    }

    func playlistSongIdsAsync(playlistId: String) async throws -> [String] {
        try await dbQueue.read { db in try Self.songIds(db, playlistId: playlistId) }
    }

    func createPlaylist(name: String) throws -> Playlist {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        let playlist = Playlist(id: UUID().uuidString, name: name, createdAt: now, updatedAt: now)
        try dbQueue.write { db in try playlist.insert(db) }
        return playlist
    }

    func renamePlaylist(id: String, name: String) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE playlists SET name = ?, updated_at = ? WHERE id = ?",
                           arguments: [name, now, id])
        }
    }

    func deletePlaylist(id: String) throws {
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM playlist_items WHERE playlist_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM playlists WHERE id = ?", arguments: [id])
        }
    }

    /// 曲の並びを丸ごと書き直す (足す・外す・並べ替えはコアで並びを作ってからこれを呼ぶ)。
    func setPlaylistSongIds(playlistId: String, songIds: [String]) throws {
        let now = ISO8601DateFormatter.shared.string(from: Date())
        try dbQueue.write { db in
            try db.execute(sql: "DELETE FROM playlist_items WHERE playlist_id = ?", arguments: [playlistId])
            for (position, songId) in songIds.enumerated() {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO playlist_items (playlist_id, song_id, position) VALUES (?, ?, ?)",
                    arguments: [playlistId, songId, position])
            }
            try db.execute(sql: "UPDATE playlists SET updated_at = ? WHERE id = ?", arguments: [now, playlistId])
        }
    }

    private static func songIds(_ db: Database, playlistId: String) throws -> [String] {
        try String.fetchAll(db, sql: "SELECT song_id FROM playlist_items WHERE playlist_id = ? ORDER BY position",
                            arguments: [playlistId])
    }
}
