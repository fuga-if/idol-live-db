import Foundation

/// `UnitReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBUnitRepository: UnitReading {
    let database: AppDatabase

    func unitIndex() async throws -> UnitIndex {
        try database.fetchUnitIndex()
    }

    func unit(id: String) async throws -> Unit? {
        try database.fetchUnit(id: id)
    }

    func unitMembers(unitId: String) async throws -> [Idol] {
        try database.fetchUnitMembers(unitId: unitId)
    }

    func unitSongs(unitId: String) async throws -> [Song] {
        try database.fetchUnitSongs(unitId: unitId)
    }

    func unitIdsWithSongs(unitIds: [String]) async throws -> Set<String> {
        try database.fetchUnitIdsWithSongs(unitIds: unitIds)
    }

    func performedUnitIds(eventId: String) async throws -> Set<String> {
        try database.fetchPerformedUnitIds(eventId: eventId)
    }

    func allUnits() async throws -> [Unit] {
        try database.fetchAllUnits()
    }
}
