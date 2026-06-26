import Foundation

/// マスタ書き込みポート群の GRDB アダプタ (Strangler / AppDatabase 委譲)。
/// 4ドメインの Writing を共有 AppDatabase へまとめて委譲する 1 アダプタ。

struct GRDBEventWriting: EventWriting {
    let database: AppDatabase
    func upsertEvents(_ events: [Event]) async throws { try database.upsertEvents(events) }
}

struct GRDBShowWriting: ShowWriting {
    let database: AppDatabase
    func upsertShows(_ shows: [Show]) async throws { try database.upsertShows(shows) }
    func upsertSetlistItems(_ items: [SetlistItem]) async throws { try database.upsertSetlistItems(items) }
    func replaceSetlist(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) async throws {
        try database.replaceSetlist(showId: showId, items: items, performers: performers)
    }
}

struct GRDBIdolWriting: IdolWriting {
    let database: AppDatabase
    func upsertIdols(_ idols: [Idol]) async throws { try database.upsertIdols(idols) }
}

struct GRDBSongWriting: SongWriting {
    let database: AppDatabase
    func upsertSongs(_ songs: [Song]) async throws { try database.upsertSongs(songs) }
    func upsertSongArtists(_ songArtists: [SongArtist]) async throws { try database.upsertSongArtists(songArtists) }
    func upsertSongCalls(_ calls: [SongCall]) async throws { try database.upsertSongCalls(calls) }
    func upsertSongVideos(_ videos: [SongVideo]) async throws { try database.upsertSongVideos(videos) }
}
