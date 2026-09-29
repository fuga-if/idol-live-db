package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Expense
import java.time.Instant
import uniffi.imas_core.showDisplayTitle

/**
 * 紐づけられる公演の候補 1 件。表記 (`label`) はコアの `showDisplayTitle` 一本
 * (イベント名と公演名の重なりの落とし方を各画面で書かない)。
 */
data class LedgerShowOption(
    val id: String,
    val eventId: String,
    val label: String,
    val date: String
)

/**
 * 収支 (家計簿) の読み書き。**端末ローカル唯一データ**なので、
 * user_marks / personal_tags と同じく破壊的な移行はしない。
 *
 * 集計・絞り込み・並びは共有コア (domain/ledger.rs)。ここは行の出し入れだけで、
 * 「どの支出を数えるか」の判断は 1 つも書かない。
 */
class ExpenseRepository(private val db: AppDatabase) {

    private val dao get() = db.expenseDao()

    suspend fun getAll(): List<Expense> = dao.getAll()

    suspend fun save(expense: Expense) {
        dao.upsert(expense.copy(updatedAt = Instant.now().toString()))
    }

    suspend fun delete(id: String) {
        dao.delete(id)
    }

    suspend fun forShow(showId: String): List<Expense> = dao.forShow(showId)

    /** バックアップ用の id 一覧 (重複判定はコアが id で行う)。 */
    suspend fun allIds(): List<String> = dao.allIds()

    /**
     * バックアップからの非破壊復元: ローカルに無い id の行だけ追加する。
     * 既にある id は**触らない** (同じ支出を 2 回足すと帳簿の額が倍になる)。
     */
    suspend fun restoreIfAbsent(expenses: List<Expense>): Int {
        if (expenses.isEmpty()) return 0
        val existing = dao.allIds().toSet()
        val toInsert = expenses.filter { it.id !in existing }
        if (toInsert.isEmpty()) return 0
        return dao.insertAllIfAbsent(toInsert).count { it != -1L }
    }

    /** 参加を付けた公演を新しい順で。 */
    suspend fun attendedShowOptions(): List<LedgerShowOption> =
        dao.attendedShowOptions().map { row ->
            LedgerShowOption(
                id = row.showId,
                eventId = row.eventId,
                label = showDisplayTitle(row.eventName.orEmpty(), row.showName.orEmpty(), row.date.orEmpty()),
                date = row.date.orEmpty()
            )
        }
}
