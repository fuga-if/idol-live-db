import Foundation

/// `IdolReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBIdolRepository: IdolReading {
    let database: AppDatabase

    func idols(brandId: String?) async throws -> [Idol] {
        try await database.fetchIdolsAsync(brandId: brandId)
    }

    func idol(id: String) async throws -> Idol? {
        try await database.fetchIdolAsync(id: id)
    }

    func idols(ids: [String]) async throws -> [Idol] {
        try await database.fetchIdolsAsync(ids: ids)
    }

    func idols(criterion: IdolFilterCriterion) async throws -> [Idol] {
        try await database.fetchIdolsAsync(criterion: criterion)
    }

    func idolCastNames() async throws -> [String: String] {
        try await database.fetchIdolCastNamesAsync()
    }

    func idolsByVoiceActor(name: String) async throws -> [Idol] {
        try await database.fetchIdolsByVoiceActorAsync(name: name)
    }

    func searchIdols(query: String, limit: Int) async throws -> [Idol] {
        try await database.searchIdolsAsync(query: query, limit: limit)
    }

    func idolSongs(idolId: String, role: String?) async throws -> [Song] {
        try await database.fetchIdolSongsAsync(idolId: idolId, role: role)
    }

    func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong] {
        try await database.fetchIdolPerformedSongsAsync(idolId: idolId)
    }

    func idolUnits(idolId: String) async throws -> [Unit] {
        try await database.fetchIdolUnitsAsync(idolId: idolId)
    }

    func idolShows(idolId: String) async throws -> [CastShowRow] {
        try await database.fetchIdolShowsAsync(idolId: idolId)
    }

    func allIdolsForPicker() async throws -> [Idol] {
        try await database.fetchAllIdolsForPickerAsync()
    }

    func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow] {
        try await database.fetchIdolSongHistoryAsync(idolId: idolId, songId: songId)
    }
}
