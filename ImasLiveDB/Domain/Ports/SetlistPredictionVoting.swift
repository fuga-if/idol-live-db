import Foundation

/// セトリ予想 (みんなの予想) への投票のポート (driven port)。
///
/// 実装は Worker の `POST /shows/:id/predictions` (`PredictionService`)。
/// 送信前にトークンの有無を確かめないこと (401 の自動リフレッシュに委ねる)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol SetlistPredictionVoting: Sendable {
    /// その曲に 1 票入れる。3 票の上限は `PredictionError.voteLimitReached` で投げる。
    func vote(showId: String, songId: String) async throws -> PredictionVoteResult
}
