import Foundation

/// マスタの書き込みポート (driven port)。
///
/// 編集/インポート系 View がローカル DB へ upsert する経路を抽象化する。
/// (CloudKit への反映は別経路。ここはローカル GRDB ミラーへの書き込み。)
/// 実装は `Adapters/Persistence/GRDB*Repository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。

protocol EventWriting: Sendable {
    func upsertEvents(_ events: [Event]) async throws
}

protocol ShowWriting: Sendable {
    func upsertShows(_ shows: [Show]) async throws
    func upsertSetlistItems(_ items: [SetlistItem]) async throws
    /// 公演のセトリ (曲 + 出演者) を丸ごと置き換える。
    func replaceSetlist(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) async throws
}

protocol IdolWriting: Sendable {
    func upsertIdols(_ idols: [Idol]) async throws
}

protocol SongWriting: Sendable {
    func upsertSongs(_ songs: [Song]) async throws
    func upsertSongArtists(_ songArtists: [SongArtist]) async throws
    func upsertSongCalls(_ calls: [SongCall]) async throws
    func upsertSongVideos(_ videos: [SongVideo]) async throws
}
