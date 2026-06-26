import Foundation

/// 統計 (ランキング/集計) の読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/GRDBStatsRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol StatsReading: Sendable {
    /// ブランド別の曲数。
    func brandSongCounts() async throws -> [BrandSongCount]
    /// 披露回数ランキング。
    func songPlayCountRanking(limit: Int) async throws -> [SongPlayCount]
    /// 出演公演数ランキング (キャスト)。
    func castShowCountRanking(limit: Int) async throws -> [CastShowCount]
    /// 年別公演数。
    func yearlyShowCounts() async throws -> [YearlyShowCount]
}
