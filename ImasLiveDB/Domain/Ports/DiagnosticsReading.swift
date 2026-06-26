import Foundation

/// DB メタ情報・診断の読み取りポート (driven port)。設定画面の情報表示用。
///
/// 実装は `Adapters/Persistence/GRDBDiagnosticsRepository`。
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol DiagnosticsReading: Sendable {
    /// メタテーブルの値 (schema_version / data_version 等)。
    func metaValue(forKey key: String) async throws -> String?
    /// テーブル件数などの DB 統計。
    func databaseStats() async throws -> DatabaseStats
    /// CloudKit 同期の診断情報。
    func syncDiagnostics() async throws -> SyncDiagnostics
}
