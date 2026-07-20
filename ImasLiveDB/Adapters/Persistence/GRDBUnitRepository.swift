import Foundation

/// `UnitReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBUnitRepository: UnitReading {
    let database: AppDatabase

    func unitIndex() async throws -> UnitIndex {
        try await database.fetchUnitIndexAsync()
    }

    func unit(id: String) async throws -> Unit? {
        try await database.fetchUnitAsync(id: id)
    }

    func unitMembers(unitId: String) async throws -> [Idol] {
        try await database.fetchUnitMembersAsync(unitId: unitId)
    }

    func unitSongs(unitId: String) async throws -> [Song] {
        try await database.fetchUnitSongsAsync(unitId: unitId)
    }

    func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> {
        try await database.fetchUnitIdsWithSongsAsync(unitIds: unitIds)
    }

    func performedUnitIds(eventId: String) async throws -> Set<String> {
        try await database.fetchPerformedUnitIdsAsync(eventId: eventId)
    }

    func allUnits() async throws -> [Unit] {
        try await database.fetchAllUnitsAsync()
    }
}
