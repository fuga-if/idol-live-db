import Foundation

/// `GlobalSearchReading` ポートの共有コア (imas-core インメモリスナップショット) アダプタ。
///
/// 呼び出し単位でスナップショットの有無を見て切り替える (スライス並走の原則)。
struct CoreGlobalSearchRepository: GlobalSearchReading {
    let snapshot: CoreSnapshotManager
    /// 未ロード時の受け皿 (Strangler の旧経路)。
    let fallback: GRDBGlobalSearchRepository

    func search(query: String) async throws -> SearchResults {
        try await snapshot.withStore(fallbackTo: { try await fallback.search(query: query) }) { store in
            // core が返すのはヒットした id 列 (各 20 件まで・rowid 順)。実体化はここで行う。
            let hits = try store.globalSearch(query: query)
            return SearchResults(
                songs: try CoreRecordMapping.songs(store: store, orderedIds: hits.songIds),
                idols: try CoreRecordMapping.idols(store: store, orderedIds: hits.idolIds),
                events: try events(store: store, hitIds: hits.eventIds)
            )
        }
    }

    /// イベントは「入力 id 順で引く」API が無く `eventsWithDateByIds` は公演日降順で返すが、
    /// ここで `hitIds` 順に組み直すので core 側の並びは影響しない (SQL 時代の rowid 順が復元される)。
    /// 公演なしイベントも落とさずに返る API なので、ヒット分 (最大 20 件) だけ FFI で受け取れば足りる。
    private func events(store: SnapshotStore, hitIds: [String]) throws -> [Event] {
        guard !hitIds.isEmpty else { return [] }
        let byId = Dictionary(
            try store.eventsWithDateByIds(ids: hitIds).map { ($0.event.id, $0.event) },
            uniquingKeysWith: { first, _ in first }
        )
        return hitIds.compactMap { byId[$0] }.map(CoreRecordMapping.event(from:))
    }
}
