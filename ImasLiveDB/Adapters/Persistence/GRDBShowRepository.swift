import Foundation

/// `ShowReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBShowRepository: ShowReading {
    let database: AppDatabase

    func shows(eventId: String) async throws -> [Show] {
        try await database.fetchShowsAsync(eventId: eventId)
    }

    func show(id: String) async throws -> Show? {
        try await database.fetchShowAsync(id: id)
    }

    func latestShow() async throws -> Show? {
        try await database.fetchLatestShowAsync()
    }

    func setlist(showId: String) async throws -> [SetlistRow] {
        try await database.fetchSetlistAsync(showId: showId)
    }

    func allPerformers(showId: String) async throws -> [String: [PerformerRow]] {
        try await database.fetchAllPerformersAsync(showId: showId)
    }

    func showIdolIds(showId: String) async throws -> Set<String> {
        try await database.fetchShowIdolIdsAsync(showId: showId)
    }

    func originalArtistIds(songIds: [String]) async throws -> [String: Set<String>] {
        try await database.fetchOriginalArtistIdsAsync(songIds: songIds)
    }

    func shows(criterion: ShowFilterCriterion) async throws -> [Show] {
        try await database.fetchShowsAsync(criterion: criterion)
    }

    func allShows(limit: Int) async throws -> [ShowWithEventName] {
        try await database.fetchAllShowsAsync(limit: limit)
    }

    func searchShows(query: String, limit: Int) async throws -> [ShowWithEventName] {
        try await database.searchShowsAsync(query: query, limit: limit)
    }

    func showCastIdols(showId: String) async throws -> [Idol] {
        try await database.fetchShowCastIdolsAsync(showId: showId)
    }

    func venueDirectory() async throws -> VenueDirectory {
        try await database.fetchVenueDirectoryAsync()
    }

    /// 公演 id 群 → 所属イベント id 集合。AppDatabase の一括クエリへ委譲する。
    func eventIds(forShows showIds: [String]) async throws -> Set<String> {
        try await database.fetchEventIdsForShowsAsync(showIds: showIds)
    }

    func eventIdsAtVenue(_ venueId: String) async throws -> Set<String> {
        try await database.fetchEventIdsAtVenueAsync(venueId)
    }

    func venuesMatching(query: String, eventIds: [String]) async throws -> [String: String] {
        try await database.fetchVenuesMatchingAsync(query: query, eventIds: eventIds)
    }
}
