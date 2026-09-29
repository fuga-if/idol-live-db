import Foundation
import GRDB

/// アイマス関連の支出 1 件 (家計簿)。**端末ローカル唯一データ**。
///
/// クラウドにもサーバにも無く、機種変で持ち出せるのはバックアップ (引き継ぎコード /
/// ファイル) だけ。`user_marks` と同じ扱いで、破壊的な移行はしない。
///
/// 費目・集計・金額の表記は共有コア (`domain/ledger.rs`) が持つ。ここは器だけ。
/// `category` には**英字キー**を入れる (ラベルを変えても記録が迷子にならない)。
struct Expense: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "expenses"

    var id: String
    /// `YYYY-MM-DD`。
    var date: String
    /// `expenseCategoryKey(category:)` の値。
    var category: String
    /// 円。整数だけ (小数を持つと集計のたびに誤差が乗る)。
    var amount: Int64
    /// 紐づく公演。入っていれば遠征の費用として公演別に集計される。
    var showId: String?
    /// 紐づく公演が属するイベント。イベントで束ねた集計に使う。
    var eventId: String?
    var note: String?
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, category, amount, note
        case showId = "show_id"
        case eventId = "event_id"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let date = Column(CodingKeys.date)
        static let showId = Column(CodingKeys.showId)
    }

    /// 新規作成。id と更新時刻はここで振る (画面ごとに違う振り方をしないため)。
    static func make(
        date: String,
        category: ExpenseCategory,
        amount: Int64,
        showId: String?,
        eventId: String?,
        note: String?
    ) -> Expense {
        Expense(
            id: UUID().uuidString,
            date: date,
            category: expenseCategoryKey(category: category),
            amount: amount,
            showId: showId,
            eventId: eventId,
            note: note?.isEmpty == true ? nil : note,
            updatedAt: ISO8601DateFormatter.shared.string(from: Date())
        )
    }

    /// 今日の日付 (`YYYY-MM-DD`)。日付が分からない支出の既定値。
    static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }

    /// 保存値 → 費目。知らないキーは「その他」に落ちる (コアの規則)。
    var categoryValue: ExpenseCategory { expenseCategoryFromKey(key: category) }
}
