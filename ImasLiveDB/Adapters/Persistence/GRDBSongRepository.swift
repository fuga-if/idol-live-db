import Foundation

/// `SongReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行され、
/// 同期的な DB read がメインスレッドを塞がない。
struct GRDBSongRepository: SongReading {
    let database: AppDatabase

    func songs(filter: SongSearchFilter, sortOrder: SongSortOrder, ascending: Bool?) async throws -> [SongWithArtists] {
        try database.fetchSongs(filter: filter, sortOrder: sortOrder, ascending: ascending)
    }

    func song(id: String) async throws -> Song? {
        try database.fetchSong(id: id)
    }

    func songs(ids: [String]) async throws -> [Song] {
        try database.fetchSongs(ids: ids)
    }

    func songIdsWithAnyArtist(idolIds: Set<String>) async throws -> Set<String> {
        try database.fetchSongIdsWithAnyArtist(idolIds: idolIds)
    }

    func songPerformerIdolsMap(songIds: [String]) async throws -> [String: [Idol]] {
        try database.fetchSongPerformerIdolsMap(songIds: songIds)
    }

    func songCollectedCounts() async throws -> [String: Int] {
        try database.fetchSongCollectedCounts()
    }

    func songSuggestions(query: String, limit: Int) async throws -> [SearchSuggestionItem] {
        try database.fetchSongSuggestions(query: query, limit: limit)
    }

    func searchSongs(query: String, limit: Int) async throws -> [Song] {
        try database.searchSongs(query: query, limit: limit)
    }

    func songPerformanceHistory(songId: String) async throws -> [PerformanceHistoryRow] {
        try database.fetchSongPerformanceHistory(songId: songId)
    }

    func songArtists(songId: String, role: String?) async throws -> [Idol] {
        try database.fetchSongArtists(songId: songId, role: role)
    }

    func relatedSongs(to song: Song, limit: Int) async throws -> [Song] {
        try database.fetchRelatedSongs(to: song, limit: limit)
    }

    func collectedShows(for songId: String) async throws -> [ShowWithEventName] {
        try database.fetchCollectedShows(for: songId)
    }

    func songs(criterion: SongFilterCriterion) async throws -> [SongWithArtists] {
        try database.fetchSongs(criterion: criterion)
    }

    func songsByCreator(_ name: String) async throws -> [SongWithRoles] {
        try database.fetchSongsByCreator(name)
    }

    func allSongsForPicker() async throws -> [PickedSong] {
        try database.fetchAllSongsForPicker()
    }

    func albums(brandIds: Set<String>, query: String?) async throws -> [AlbumSummary] {
        try database.fetchAlbums(brandIds: brandIds, query: query)
    }

    func series(brandIds: Set<String>, query: String?) async throws -> [SeriesSummary] {
        try database.fetchSeries(brandIds: brandIds, query: query)
    }

    func cdSeriesList() async throws -> [String] {
        try database.fetchCdSeriesList()
    }

    func seriesGroups(brandIds: Set<String>) async throws -> [String] {
        try database.fetchSeriesGroups(brandIds: brandIds)
    }

    func songIds(brandId: String, includeCovers: Bool, excludeRemixes: Bool) async throws -> [String] {
        try database.fetchSongIds(brandId: brandId, includeCovers: includeCovers, excludeRemixes: excludeRemixes)
    }

    func originalSongIds(forShowCastOf showId: String) async throws -> Set<String> {
        try database.fetchOriginalSongIds(forShowCastOf: showId)
    }

    func brandedSongIds() async throws -> Set<String> {
        try database.fetchBrandedSongIds()
    }

    func songCalls(songId: String) async throws -> [SongCall] {
        try database.fetchCallResponsesForSong(songId: songId)
    }

    func songVideos(songId: String) async throws -> [SongVideo] {
        try database.fetchVideosForSong(songId: songId)
    }
}
