import Foundation
import GRDB

/// プレイリスト 1 つ。**端末ローカル唯一データ** (クラウドにもサーバにも無い)。
///
/// 中身の曲は `playlist_items` に id と並びだけで持つ。並べ替え・足し方の規則は
/// 共有コア (`domain/play_queue.rs`)。
struct Playlist: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "playlists"

    var id: String
    var name: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// 一覧に出す 1 行 (プレイリストと曲数・先頭の曲)。
struct PlaylistSummary: Identifiable, Hashable {
    let playlist: Playlist
    let songCount: Int
    /// 先頭の曲 (ジャケに使う)。空なら nil。
    let firstSongId: String?
    var id: String { playlist.id }
}
