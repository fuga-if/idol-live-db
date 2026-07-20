import Foundation

/// コミュニティタグ機能 (曲/アイドル/ユニットの3プール) の読み取りポート (Domain)。
///
/// Presentation はこのプロトコルにのみ依存し、Worker D1 集計 API の具象 (`CommunityAPI`) を知らない。
/// `CommunityVoting` と同じ役割分担: 適合 (`extension CommunityAPI: CommunityTagReading`) は Data レイヤ側に置く。
///
/// ⚠️ Domain レイヤの規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol CommunityTagReading: Sendable {
    // MARK: - 曲タグ (tags / tag_master)

    /// タグ一覧 (人気/新着/名前順、検索・カテゴリ絞り込み可)。
    func tags(search: String, category: String, sort: String, limit: Int, offset: Int) async throws -> [CommunityTag]
    /// タグ詳細 (付いた曲ランキングつき)。
    func tag(id: String) async throws -> TagDetailResponse
    /// タグの編集履歴。
    func tagHistory(id: String) async throws -> [TagHistoryEntry]
    /// タグ付けの盛り上がり (直近フィード/トレンドタグ/急上昇コンテンツ)。
    func tagActivity(windowDays: Int) async throws -> TagActivityResponse
    /// 指定曲に付いたタグ一覧 (自分が付けたタグを含む)。
    func songTags(songId: String) async throws -> SongTagListResponse

    // MARK: - アイドルタグ (idol_tag_master — 曲タグとは別プール)

    /// 指定アイドルに付いたタグ一覧 (自分が付けたタグを含む)。
    func idolTags(idolId: String) async throws -> IdolTagListResponse
    /// アイドルタグマスタ一覧。
    func idolTagCatalog(search: String, category: String, sort: String, limit: Int, offset: Int) async throws -> [CommunityTag]
    /// アイドルタグ詳細 (付いたアイドルランキングつき)。
    func idolTagDetail(id: String) async throws -> IdolTagDetailResponse
    /// アイドルタグの編集履歴。
    func idolTagHistory(id: String) async throws -> [TagHistoryEntry]

    // MARK: - ユニットタグ (unit_tag_master — 曲/アイドルタグとは別プール)

    /// 指定ユニットに付いたタグ一覧 (自分が付けたタグを含む)。
    func unitTags(unitId: String) async throws -> UnitTagListResponse
    /// ユニットタグマスタ一覧。
    func unitTagCatalog(search: String, category: String, sort: String, limit: Int, offset: Int) async throws -> [CommunityTag]
    /// ユニットタグ詳細 (付いたユニットランキングつき)。
    func unitTagDetail(id: String) async throws -> UnitTagDetailResponse
    /// ユニットタグの編集履歴。
    func unitTagHistory(id: String) async throws -> [TagHistoryEntry]
}
