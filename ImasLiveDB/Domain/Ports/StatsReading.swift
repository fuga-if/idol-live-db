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
    /// 未回収一覧の画面 1 つぶん (範囲の回収率と、未回収を披露済み/未披露に分けたもの)。原曲単位。
    func uncollectedSongs(collectedSongIds: Set<String>, scope: CollectionScope) async throws -> UncollectedSongList
    /// 回収した原曲の数 (P名刺・プロフィール帳の「回収曲」。ダッシュボードの全体の回収数と同じ)。
    func collectedOriginalSongCount(collectedSongIds: Set<String>) async throws -> Int
    /// 回収した原曲の id (プロデュースの「回収した楽曲」)。数は `collectedOriginalSongCount` と同じ。
    func collectedOriginalSongIds(collectedSongIds: Set<String>) async throws -> [String]
    /// 聴いた曲に、その一族 (ver 違い) の原曲を足した集合。「この曲は回収済みか」を引く所が使う。
    func collectedFamilySongIds(collectedSongIds: Set<String>) async throws -> Set<String>
    /// 歌詞の投稿状況 (全体とブランド別)。`publishedSongIds` はサーバの公開曲 id。
    func lyricCoverage(publishedSongIds: [String]) async throws -> LyricCoverageRecord
    /// 歌詞のある曲の id (`lyricCoverage` と同じ母集合)。`brandId` が nil なら全ブランド。
    func lyricSongIds(publishedSongIds: [String], brandId: String?) async throws -> [String]
}
