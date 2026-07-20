import Foundation

/// コミュニティタグ機能 (曲/アイドル/ユニットの3プール) の書き込みポート (Domain)。
///
/// `CommunityTagReading` と対をなす。作成・更新・付与・通報を担う。適合
/// (`extension CommunityAPI: CommunityTagWriting`) は Data レイヤ側に置く。
///
/// ⚠️ Domain レイヤの規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol CommunityTagWriting: Sendable {
    // MARK: - 曲タグ (tags / tag_master)

    /// 新規タグを作成 (同名タグが既存なら既存タグを返して冪等)。
    func createTag(name: String, description: String?, category: String?, color: String?) async throws -> CommunityTag
    /// タグの説明/カテゴリ/色を更新。
    func updateTag(id: String, description: String?, category: String?, color: String?) async throws -> CommunityTag
    /// タグを不適切なコンテンツとして通報。
    func reportTag(id: String, reason: String?) async throws
    /// 曲へタグをまとめて付与。
    func applySongTags(songId: String, tagIds: [String]) async throws

    // MARK: - アイドルタグ (idol_tag_master — 曲タグとは別プール)

    /// 新規アイドルタグを作成。
    func createIdolTag(name: String, description: String?, category: String?, color: String?) async throws -> CommunityTag
    /// アイドルタグの説明/カテゴリ/色を更新。
    func updateIdolTag(id: String, description: String?, category: String?, color: String?) async throws -> CommunityTag
    /// アイドルタグを通報。
    func reportIdolTag(id: String, reason: String?) async throws
    /// アイドルへタグをまとめて付与。
    func applyIdolTags(idolId: String, tagIds: [String]) async throws

    // MARK: - ユニットタグ (unit_tag_master — 曲/アイドルタグとは別プール)

    /// 新規ユニットタグを作成。
    func createUnitTag(name: String, description: String?, category: String?, color: String?) async throws -> CommunityTag
    /// ユニットタグの説明/カテゴリ/色を更新。
    func updateUnitTag(id: String, description: String?, category: String?, color: String?) async throws -> CommunityTag
    /// ユニットタグを通報。
    func reportUnitTag(id: String, reason: String?) async throws
    /// ユニットへタグをまとめて付与。
    func applyUnitTags(unitId: String, tagIds: [String]) async throws
}
