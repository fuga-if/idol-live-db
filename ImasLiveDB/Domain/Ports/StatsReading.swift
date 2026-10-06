import Foundation

/// 統計 (ランキング/集計) の読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/CoreStatsRepository` (共有コアのスナップショット)。
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
    /// 回収ダッシュボード (回収率・未回収曲・聴けるかもしれない公演) を 1 回で組む。
    /// - Parameters:
    ///   - collectedSongIds: 回収済みの曲 (一覧の回収バッジと同じ集合)。
    ///   - pickIdolIds: 担当アイドル。
    ///   - today: JST の今日 (`yyyy-MM-dd`)。
    ///   - chanceLimit: 「聴けるかも」に出す公演の数。
    func collectionDashboard(
        collectedSongIds: Set<String>, pickIdolIds: Set<String>, today: String, chanceLimit: Int
    ) async throws -> CollectionDashboard
}
