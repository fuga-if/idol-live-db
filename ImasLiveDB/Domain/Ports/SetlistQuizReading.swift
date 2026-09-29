import Foundation

/// セトリ当てクイズの読み取りポート (driven port)。
///
/// 出題 (公演の選び方・伏せる曲・誤答の選び方) はすべて imas-core の `domain/setlist_quiz.rs`
/// が持つ。ここは件数の見積りと 1 ゲームぶんの出題を受け取るだけ。
/// 実装は `Adapters/Persistence/CoreSetlistQuizRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol SetlistQuizReading: Sendable {
    /// 出題できる公演数。`brandIds` 空 = 全ブランド。
    func poolEstimate(brandIds: [String]) async throws -> SetlistQuizPoolEstimate
    /// 1 ゲームぶんの出題 (同じシードなら同じ出題)。
    func session(brandIds: [String], seed: UInt64) async throws -> [SetlistQuizQuestion]
}
