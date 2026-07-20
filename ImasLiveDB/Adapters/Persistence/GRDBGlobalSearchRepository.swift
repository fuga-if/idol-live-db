import Foundation

/// `GlobalSearchReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
struct GRDBGlobalSearchRepository: GlobalSearchReading {
    let database: AppDatabase

    func search(query: String) async throws -> SearchResults {
        try await database.searchAsync(query: query)
    }
}
