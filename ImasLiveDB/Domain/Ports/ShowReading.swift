import Foundation

/// 公演 (Show) / セットリストの読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/GRDBShowRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol ShowReading: Sendable {
    /// イベント配下の公演一覧。
    func shows(eventId: String) async throws -> [Show]
    /// 単一公演。
    func show(id: String) async throws -> Show?
    /// 最新公演 (日付最大)。
    func latestShow() async throws -> Show?
    /// 公演のセットリスト。
    func setlist(showId: String) async throws -> [SetlistRow]
    /// セトリ項目 id → 出演者行。
    func allPerformers(showId: String) async throws -> [String: [PerformerRow]]
    /// 公演の全出演キャスト idol_id 集合 (「全員」表記の判定用)。
    func showIdolIds(showId: String) async throws -> Set<String>
    /// song_id → 原曲アーティスト idol_id 集合 (一部カバー判定用)。
    func originalArtistIds(songIds: [String]) async throws -> [String: Set<String>]
    /// フィルタ条件で絞った公演。
    func shows(criterion: ShowFilterCriterion) async throws -> [Show]
    /// ピッカー用の公演一覧 (イベント名つき・新しい順)。
    func allShows(limit: Int) async throws -> [ShowWithEventName]
    /// ピッカー用の公演検索 (イベント名つき)。
    func searchShows(query: String, limit: Int) async throws -> [ShowWithEventName]
}
