import Foundation

/// `IdolReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBIdolRepository: IdolReading {
    let database: AppDatabase

    func idols(brandId: String?) async throws -> [Idol] {
        try database.fetchIdols(brandId: brandId)
    }

    func idol(id: String) async throws -> Idol? {
        try database.fetchIdol(id: id)
    }

    func idols(ids: [String]) async throws -> [Idol] {
        try database.fetchIdols(ids: ids)
    }

    func idols(criterion: IdolFilterCriterion) async throws -> [Idol] {
        try database.fetchIdols(criterion: criterion)
    }

    func idolCastNames() async throws -> [String: String] {
        try database.fetchIdolCastNames()
    }

    func idolsByVoiceActor(name: String) async throws -> [Idol] {
        try database.fetchIdolsByVoiceActor(name: name)
    }

    func searchIdols(query: String, limit: Int) async throws -> [Idol] {
        try database.searchIdols(query: query, limit: limit)
    }

    func idolSongs(idolId: String, role: String?) async throws -> [Song] {
        try database.fetchIdolSongs(idolId: idolId, role: role)
    }

    func idolPerformedSongs(idolId: String) async throws -> [IdolPerformedSong] {
        try database.fetchIdolPerformedSongs(idolId: idolId)
    }

    func idolUnits(idolId: String) async throws -> [Unit] {
        try database.fetchIdolUnits(idolId: idolId)
    }

    func idolShows(idolId: String) async throws -> [CastShowRow] {
        try database.fetchIdolShows(idolId: idolId)
    }

    func allIdolsForPicker() async throws -> [Idol] {
        try database.fetchAllIdolsForPicker()
    }

    func idolSongHistory(idolId: String, songId: String) async throws -> [CastShowRow] {
        try database.fetchIdolSongHistory(idolId: idolId, songId: songId)
    }
}
