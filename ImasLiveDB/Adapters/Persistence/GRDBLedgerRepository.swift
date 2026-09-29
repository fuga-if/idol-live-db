import Foundation

/// `LedgerReading` / `LedgerWriting` の端末 DB アダプタ。
///
/// 支出は端末にしか無いので、スナップショットではなく端末の DB を読み書きする。
struct GRDBLedgerRepository: LedgerReading, LedgerWriting {
    let database: AppDatabase

    func expenses() async throws -> [Expense] {
        try await database.allExpensesAsync()
    }

    func expenses(showId: String) async throws -> [Expense] {
        try database.expenses(showId: showId)
    }

    func attendedShowOptions() async throws -> [LedgerShowOption] {
        try await database.attendedShowOptionsAsync()
    }

    func attendedShowLabels() async throws -> [String: String] {
        try await database.attendedShowLabelsAsync()
    }

    func save(_ expense: Expense) async throws {
        try database.saveExpense(expense)
    }

    func delete(id: String) async throws {
        try database.deleteExpense(id: id)
    }
}
