import Foundation

/// 横断検索 (曲/アイドル/イベント等をまとめて) の読み取りポート (driven port)。
///
/// 実装は `Adapters/Persistence/GRDBGlobalSearchRepository`。
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol GlobalSearchReading: Sendable {
    /// クエリにマッチする各種エンティティをまとめて返す。
    func search(query: String) async throws -> SearchResults
}
