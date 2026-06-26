import Foundation

/// ブランドマスタの読み取りポート (driven port)。
///
/// Presentation はこのポートに依存し、永続化の具象 (`AppDatabase` / GRDB) を知らない。
/// 実装は `Adapters/Persistence/GRDBBrandRepository`。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol BrandReading: Sendable {
    /// 表示順ソート済みの全ブランド。
    func brands() async throws -> [Brand]
}
