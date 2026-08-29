import Foundation

/// `GlobalSearchReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
struct GRDBGlobalSearchRepository: GlobalSearchReading {
    let database: AppDatabase

    func search(query: String) async throws -> SearchResults {
        try await database.searchAsync(query: query)
    }

    /// 件数は出さない (全部 0 = チップを 1 つも出さない)。
    ///
    /// ここはスナップショット未ロード時の受け皿で、SQL で数え直すと**当たり方が
    /// 変わる**。LIKE はひらがな↔カタカナを畳まないので、「ライブに 8 件」と出して
    /// 切り替えたら 12 件だった、が起きる。切り替える判断の根拠にならない数字なら、
    /// 出さない方がよい。スナップショットは起動直後に載るので、実際に見えるのは一瞬。
    func counts(query: String) async throws -> CrossTabSearchCounts {
        CrossTabSearchCounts()
    }
}
