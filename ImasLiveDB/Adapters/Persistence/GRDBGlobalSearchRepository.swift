import Foundation

/// `GlobalSearchReading` ポートの GRDB アダプタ (Strangler / AppDatabase 委譲)。
struct GRDBGlobalSearchRepository: GlobalSearchReading {
    let database: AppDatabase

    func search(query: String) async throws -> SearchResults {
        try await database.searchAsync(query: query)
    }

    /// 数えない (nil = まだ分からない)。
    ///
    /// ここはスナップショット未ロード時の受け皿で、SQL で数え直すと**当たり方が
    /// 変わる**。LIKE はひらがな↔カタカナを畳まないので、「ライブに 8 件」と出して
    /// 切り替えたら 12 件だった、が起きる。根拠にならない数字なら出さない方がよい。
    ///
    /// 0 ではなく nil を返すのが要点。0 だと「どこにも無い」と読めて、呼び出し側が
    /// 待たずに諦めてしまう。スナップショットは起動直後に載るので、待てば答えが出る。
    func counts(query: String) async throws -> CrossTabSearchCounts? {
        nil
    }

    /// 同上 (nil = まだ分からない)。着地先を決められないので既定のままにする。
    func eventSides(query: String, todayKey: String) async throws -> EventSearchSideCounts? {
        nil
    }
}
