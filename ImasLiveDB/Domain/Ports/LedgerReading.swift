import Foundation

/// 家計簿 (端末にだけある支出の記録) の読み取りポート (driven port)。
///
/// 支出はクラウドにもサーバにも無い端末ローカルのデータなので、実装は端末の DB を読む
/// (`Adapters/Persistence/GRDBLedgerRepository`)。集計の規則はコア (`buildLedgerSummary` 等)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol LedgerReading: Sendable {
    /// すべての支出 (新しい日付順)。
    func expenses() async throws -> [Expense]
    /// その公演に紐づく支出。
    func expenses(showId: String) async throws -> [Expense]
    /// 支出を紐づけられる公演 (参加を付けた公演)。
    func attendedShowOptions() async throws -> [LedgerShowOption]
    /// 参加を付けた公演の id → 表示名。
    func attendedShowLabels() async throws -> [String: String]
}

/// 家計簿の書き込みポート (driven port)。
///
/// ⚠️ Domain 規約: このファイルは `SwiftUI` / `GRDB` / `CloudKit` を import しない。
protocol LedgerWriting: Sendable {
    /// 同じ id があれば上書きし、無ければ足す。
    func save(_ expense: Expense) async throws
    func delete(id: String) async throws
}
