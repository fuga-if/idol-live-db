import Foundation

/// 「みんなの投票」のユースケース境界 (Domain)。
///
/// Presentation (ViewModel) はこのプロトコルにのみ依存し、具象 (Worker D1 集計 API) を知らない。
/// これにより ViewModel をフェイク実装で単体テストでき、Preview も安定化できる。
///
/// ⚠️ Domain レイヤの規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
/// 具象への適合 (`extension CommunityAPI: CommunityVoting`) は Data レイヤ側に置く。
protocol CommunityVoting: Sendable {
    /// お題一覧。status は "active" / "past" など。
    func polls(status: String) async throws -> [Poll]
    /// お題詳細 (ランキング + 自分の投票数)。
    func poll(id: String) async throws -> PollDetail
    /// 終了お題の優勝者一覧 (殿堂)。
    func pollResults() async throws -> [PollResult]
    /// ある曲/アイドルが終了お題で取った順位 (詳細バッジ用)。
    func pollAchievements(entityId: String) async throws -> [PollAchievement]
    /// 新しいお題を作成。
    func createPoll(title: String, description: String?, targetType: PollTargetType, days: Int) async throws -> Poll
    /// 既存候補へ1票投じる。
    func votePoll(pollId: String, entityId: String) async throws -> PollVoteResult
    /// 自分の票を取り消す。
    func unvotePoll(pollId: String, entityId: String) async throws -> PollVoteResult
    /// お題を削除 (作成者/管理者)。
    func deletePoll(id: String) async throws
}
