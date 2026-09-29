//  収支 (家計簿) の読み書き。**端末ローカル唯一データ**なので、
//  user_marks / personal_tags と同じく破壊的な移行はしない。
//
//  集計・絞り込み・並びは共有コア (domain/ledger.rs)。ここは行の出し入れだけで、
//  「どの支出を数えるか」の判断は 1 つも書かない。

import Foundation
import GRDB

extension AppDatabase {

    /// 全件。帳簿は数百〜数千件なので、まとめて読んでコアに 1 回で渡す。
    func allExpenses() throws -> [Expense] {
        try dbQueue.read { db in
            try Expense.order(Expense.Columns.date.desc, Expense.Columns.id).fetchAll(db)
        }
    }

    func allExpensesAsync() async throws -> [Expense] {
        try await dbQueue.read { db in
            try Expense.order(Expense.Columns.date.desc, Expense.Columns.id).fetchAll(db)
        }
    }

    func saveExpense(_ expense: Expense) throws {
        var row = expense
        row.updatedAt = ISO8601DateFormatter.shared.string(from: Date())
        try dbQueue.write { db in try row.save(db) }
    }

    func deleteExpense(id: String) throws {
        _ = try dbQueue.write { db in
            try Expense.filter(Expense.Columns.id == id).deleteAll(db)
        }
    }

    /// その公演に紐づく支出。公演の画面に「この公演でいくら使ったか」を出すのに使う。
    func expenses(showId: String) throws -> [Expense] {
        try dbQueue.read { db in
            try Expense
                .filter(Expense.Columns.showId == showId)
                .order(Expense.Columns.date, Expense.Columns.id)
                .fetchAll(db)
        }
    }

    /// バックアップ用の id 一覧 (重複判定はコアが id で行う)。
    func allExpenseIds() throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT id FROM expenses")
        }
    }

    /// バックアップからの非破壊復元: ローカルに無い id の行だけ追加する。
    /// 既にある id は**触らない** (同じ支出を 2 回足すと帳簿の額が倍になる)。
    @discardableResult
    func restoreExpensesIfAbsent(_ expenses: [Expense]) throws -> Int {
        try dbQueue.write { db in
            var inserted = 0
            for expense in expenses {
                let exists = try Expense.filter(Expense.Columns.id == expense.id).fetchCount(db) > 0
                if !exists {
                    try expense.insert(db)
                    inserted += 1
                }
            }
            return inserted
        }
    }
}

/// 収支に紐づけられる公演の候補 1 件。
///
/// 「参加を付けた公演」だけを出す。行ったことのない公演にチケット代を付ける場面が
/// 無いので、候補を全公演にすると数千件から探すことになる。
struct LedgerShowOption: Identifiable, Hashable {
    let id: String
    let eventId: String
    let label: String
    let date: String
}

extension AppDatabase {

    /// 参加を付けた公演を新しい順で。表記はコアの `showDisplayTitle` 一本
    /// (イベント名と公演名の重なりの落とし方を各画面で書かない)。
    func attendedShowOptionsAsync() async throws -> [LedgerShowOption] {
        try await dbQueue.read(Self.attendedShowOptionsQuery)
    }

    /// 明細に出す公演名の辞書 (公演 id → 表記)。
    func attendedShowLabelsAsync() async throws -> [String: String] {
        let options = try await attendedShowOptionsAsync()
        return Dictionary(options.map { ($0.id, $0.label) }, uniquingKeysWith: { a, _ in a })
    }

    private static func attendedShowOptionsQuery(_ db: Database) throws -> [LedgerShowOption] {
        // 参加は公演単位とイベント単位の両方で付く (fetchAttendedEventsWithDate と同じ事情)。
        // イベントに付けた人の公演も候補に出さないと、遠征費を紐づける先が無くなる。
        let sql = """
            SELECT s.id AS show_id, s.event_id AS event_id, s.name AS show_name,
                   s.date AS date, e.name AS event_name
            FROM shows s
            JOIN events e ON e.id = s.event_id
            WHERE s.id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'show' AND kind = 'attended' AND bool_value = 1
            )
            OR s.event_id IN (
                SELECT entity_id FROM user_marks
                WHERE entity_type = 'event' AND kind = 'attended' AND bool_value = 1
            )
            ORDER BY s.date DESC, s.sort_order
            """
        return try Row.fetchAll(db, sql: sql).map { row in
            let date: String = row["date"] ?? ""
            return LedgerShowOption(
                id: row["show_id"],
                eventId: row["event_id"],
                label: showDisplayTitle(eventName: row["event_name"] ?? "",
                                        showName: row["show_name"] ?? "",
                                        date: date),
                date: date
            )
        }
    }
}
