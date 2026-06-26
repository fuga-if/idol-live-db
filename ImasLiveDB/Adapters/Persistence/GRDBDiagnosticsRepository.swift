import Foundation

/// `DiagnosticsReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
struct GRDBDiagnosticsRepository: DiagnosticsReading {
    let database: AppDatabase

    func metaValue(forKey key: String) async throws -> String? {
        try database.fetchMetaValue(forKey: key)
    }

    func databaseStats() async throws -> DatabaseStats {
        try database.fetchDatabaseStats()
    }

    func syncDiagnostics() async throws -> SyncDiagnostics {
        try database.fetchSyncDiagnostics()
    }
}
