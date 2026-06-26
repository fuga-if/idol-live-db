import Foundation

/// `ShowReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBShowRepository: ShowReading {
    let database: AppDatabase

    func shows(eventId: String) async throws -> [Show] {
        try database.fetchShows(eventId: eventId)
    }

    func show(id: String) async throws -> Show? {
        try database.fetchShow(id: id)
    }

    func latestShow() async throws -> Show? {
        try database.fetchLatestShow()
    }

    func setlist(showId: String) async throws -> [SetlistRow] {
        try database.fetchSetlist(showId: showId)
    }

    func allPerformers(showId: String) async throws -> [String: [PerformerRow]] {
        try database.fetchAllPerformers(showId: showId)
    }

    func showIdolIds(showId: String) async throws -> Set<String> {
        try database.fetchShowIdolIds(showId: showId)
    }

    func originalArtistIds(songIds: [String]) async throws -> [String: Set<String>] {
        try database.fetchOriginalArtistIds(songIds: songIds)
    }

    func shows(criterion: ShowFilterCriterion) async throws -> [Show] {
        try database.fetchShows(criterion: criterion)
    }

    func allShows(limit: Int) async throws -> [ShowWithEventName] {
        try database.fetchAllShows(limit: limit)
    }

    func searchShows(query: String, limit: Int) async throws -> [ShowWithEventName] {
        try database.searchShows(query: query, limit: limit)
    }
}
