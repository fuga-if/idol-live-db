import Foundation

/// `SongReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行され、
/// 同期的な DB read がメインスレッドを塞がない。
struct GRDBSongRepository: SongReading {
    let database: AppDatabase

    func songs(filter: SongSearchFilter, sortOrder: SongSortOrder, ascending: Bool?) async throws -> [SongWithArtists] {
        try await database.fetchSongsAsync(filter: filter, sortOrder: sortOrder, ascending: ascending)
    }

    func song(id: String) async throws -> Song? {
        try await database.fetchSongAsync(id: id)
    }

    func songs(ids: [String]) async throws -> [Song] {
        try await database.fetchSongsAsync(ids: ids)
    }

    func songIdsWithAnyArtist(idolIds: Set<String>) async throws -> Set<String> {
        try await database.fetchSongIdsWithAnyArtistAsync(idolIds: idolIds)
    }

    func songPerformerIdolsMap(songIds: [String]) async throws -> [String: [Idol]] {
        try await database.fetchSongPerformerIdolsMapAsync(songIds: songIds)
    }

    func songCollectedCounts() async throws -> [String: Int] {
        try await database.fetchSongCollectedCountsAsync()
    }

    func songPerformanceCounts() async throws -> [String: Int] {
        try await database.fetchSongPerformanceCountsAsync()
    }

    func searchSongs(query: String, limit: Int) async throws -> [Song] {
        try await database.searchSongsAsync(query: query, limit: limit)
    }

    func songSpellings() async throws -> [SongSpelling] {
        try await database.fetchSongSpellingsAsync()
    }

    func songPerformanceHistory(songId: String) async throws -> [PerformanceHistoryRow] {
        try await database.fetchSongPerformanceHistoryAsync(songId: songId)
    }

    func songArtists(songId: String, role: String?) async throws -> [Idol] {
        try await database.fetchSongArtistsAsync(songId: songId, role: role)
    }

    func relatedSongs(to song: Song, limit: Int) async throws -> [Song] {
        try await database.fetchRelatedSongsAsync(to: song, limit: limit)
    }

    func listableSongs(ids: [String]) async throws -> [Song] {
        try await database.fetchListableSongsAsync(ids: ids)
    }

    func variantSongs(of song: Song) async throws -> [Song] {
        try await database.fetchVariantSongsAsync(of: song)
    }

    func collectedShows(for songId: String) async throws -> [ShowWithEventName] {
        try await database.fetchCollectedShowsAsync(for: songId)
    }

    func songs(criterion: SongFilterCriterion) async throws -> [SongWithArtists] {
        try await database.fetchSongsAsync(criterion: criterion)
    }

    func songsByCreator(_ name: String) async throws -> [SongWithRoles] {
        try await database.fetchSongsByCreatorAsync(name)
    }

    func allSongsForPicker() async throws -> [PickedSong] {
        try await database.fetchAllSongsForPickerAsync()
    }

    func albums(brandIds: Set<String>, query: String?) async throws -> [AlbumSummary] {
        try await database.fetchAlbumsAsync(brandIds: brandIds, query: query)
    }

    func series(brandIds: Set<String>, query: String?) async throws -> [SeriesSummary] {
        try await database.fetchSeriesAsync(brandIds: brandIds, query: query)
    }

    func cdSeriesList() async throws -> [String] {
        try await database.fetchCdSeriesListAsync()
    }

    func seriesGroups(brandIds: Set<String>) async throws -> [String] {
        try await database.fetchSeriesGroupsAsync(brandIds: brandIds)
    }

    func songIds(brandId: String, includeCovers: Bool, excludeRemixes: Bool) async throws -> [String] {
        try await database.fetchSongIdsAsync(brandId: brandId, includeCovers: includeCovers, excludeRemixes: excludeRemixes)
    }

    func originalSongIds(forShowCastOf showId: String) async throws -> Set<String> {
        try await database.fetchOriginalSongIdsAsync(forShowCastOf: showId)
    }

    func brandedSongIds() async throws -> Set<String> {
        try await database.fetchBrandedSongIdsAsync()
    }

    func songCalls(songId: String) async throws -> [SongCall] {
        try await database.fetchCallResponsesForSongAsync(songId: songId)
    }

    func songVideos(songId: String) async throws -> [SongVideo] {
        try await database.fetchVideosForSongAsync(songId: songId)
    }
}
