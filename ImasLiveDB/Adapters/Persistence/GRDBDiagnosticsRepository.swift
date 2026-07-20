import Foundation

/// `DiagnosticsReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
struct GRDBDiagnosticsRepository: DiagnosticsReading {
    let database: AppDatabase

    func metaValue(forKey key: String) async throws -> String? {
        try await database.fetchMetaValueAsync(forKey: key)
    }

    func databaseStats() async throws -> DatabaseStats {
        try await database.fetchDatabaseStatsAsync()
    }

    func syncDiagnostics() async throws -> SyncDiagnostics {
        try await database.fetchSyncDiagnosticsAsync()
    }
}
