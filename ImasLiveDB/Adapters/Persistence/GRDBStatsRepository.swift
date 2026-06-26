import Foundation

/// `StatsReading` ポートの GRDB アダプタ。
///
/// 段階移行 (Strangler) のため、当面は `AppDatabase` の既存メソッドへ委譲する。
/// `nonisolated` な async メソッドなので MainActor から `await` で呼ぶとオフメインで実行される。
struct GRDBStatsRepository: StatsReading {
    let database: AppDatabase

    func brandSongCounts() async throws -> [BrandSongCount] {
        try database.fetchBrandSongCounts()
    }

    func songPlayCountRanking(limit: Int) async throws -> [SongPlayCount] {
        try database.fetchSongPlayCountRanking(limit: limit)
    }

    func castShowCountRanking(limit: Int) async throws -> [CastShowCount] {
        try database.fetchCastShowCountRanking(limit: limit)
    }

    func yearlyShowCounts() async throws -> [YearlyShowCount] {
        try database.fetchYearlyShowCounts()
    }
}
