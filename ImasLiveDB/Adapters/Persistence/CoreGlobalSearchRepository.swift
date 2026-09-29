import Foundation

/// `GlobalSearchReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
/// スナップショットがまだなら、ロードを待ってから答える (`CoreSnapshotManager.withStore`)。
struct CoreGlobalSearchRepository: GlobalSearchReading {
    let snapshot: CoreSnapshotManager

    func counts(query: String) async throws -> CrossTabSearchCounts? {
        try await snapshot.withStore { store in
            let c = try store.searchCounts(query: query)
            return CrossTabSearchCounts(
                songs: Int(c.songs), idols: Int(c.idols), events: Int(c.events))
        }
    }

    func eventSides(query: String, todayKey: String) async throws -> EventSearchSideCounts? {
        try await snapshot.withStore { store in
            let s = try store.eventSearchSides(query: query, todayKey: todayKey)
            return EventSearchSideCounts(upcoming: Int(s.upcoming), past: Int(s.past))
        }
    }
}
