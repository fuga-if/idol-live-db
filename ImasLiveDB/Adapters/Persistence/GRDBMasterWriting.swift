import Foundation

/// マスタ書き込みポート群の GRDB アダプタ (Strangler / AppDatabase 委譲)。
/// 4ドメインの Writing を共有 AppDatabase へまとめて委譲する 1 アダプタ。

struct GRDBEventWriting: EventWriting {
    let database: AppDatabase
    func upsertEvents(_ events: [Event]) async throws { try await database.upsertEventsAsync(events) }
}

struct GRDBShowWriting: ShowWriting {
    let database: AppDatabase
    func upsertShows(_ shows: [Show]) async throws { try await database.upsertShowsAsync(shows) }
    func upsertSetlistItems(_ items: [SetlistItem]) async throws { try await database.upsertSetlistItemsAsync(items) }
    func replaceSetlist(showId: String, items: [SetlistItem], performers: [SetlistPerformer]) async throws {
        try await database.replaceSetlistAsync(showId: showId, items: items, performers: performers)
    }
}

struct GRDBIdolWriting: IdolWriting {
    let database: AppDatabase
    func upsertIdols(_ idols: [Idol]) async throws { try await database.upsertIdolsAsync(idols) }
}

struct GRDBSongWriting: SongWriting {
    let database: AppDatabase
    func upsertSongs(_ songs: [Song]) async throws { try await database.upsertSongsAsync(songs) }
    func upsertSongArtists(_ songArtists: [SongArtist]) async throws { try await database.upsertSongArtistsAsync(songArtists) }
    func upsertSongCalls(_ calls: [SongCall]) async throws { try await database.upsertSongCallsAsync(calls) }
    func upsertSongVideos(_ videos: [SongVideo]) async throws { try await database.upsertSongVideosAsync(videos) }
}
