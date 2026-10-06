import Foundation

/// `MarkReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
struct GRDBMarkRepository: MarkReading {
    let database: AppDatabase

    func markedEntityIds(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String] {
        try await database.fetchMarkedEntityIdsAsync(entity: entity, kind: kind)
    }

    func markedTimes(entity: UserMarkEntity, kind: UserMarkKind) async throws -> [String: String] {
        try await database.fetchMarkedTimesAsync(entity: entity, kind: kind)
    }

    func autoCollectedSongIds() async throws -> Set<String> {
        try await database.fetchAutoCollectedSongIdsAsync()
    }
}
