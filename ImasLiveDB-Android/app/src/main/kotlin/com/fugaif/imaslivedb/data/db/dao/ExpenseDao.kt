package com.fugaif.imaslivedb.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.fugaif.imaslivedb.data.model.Expense

/**
 * 収支に紐づけられる公演の候補 1 件 (iOS `LedgerShowOption` と同型)。
 *
 * 「参加を付けた公演」だけを出す。行ったことのない公演にチケット代を付ける場面が
 * 無いので、候補を全公演にすると数千件から探すことになる。
 */
data class LedgerShowOptionRow(
    @androidx.room.ColumnInfo(name = "show_id") val showId: String,
    @androidx.room.ColumnInfo(name = "event_id") val eventId: String,
    @androidx.room.ColumnInfo(name = "show_name") val showName: String?,
    @androidx.room.ColumnInfo(name = "event_name") val eventName: String?,
    @androidx.room.ColumnInfo(name = "date") val date: String?
)

@Dao
interface ExpenseDao {

    /** 全件。帳簿は数百〜数千件なので、まとめて読んでコアに 1 回で渡す。 */
    @Query("SELECT * FROM expenses ORDER BY date DESC, id")
    suspend fun getAll(): List<Expense>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(expense: Expense)

    @Query("DELETE FROM expenses WHERE id = :id")
    suspend fun delete(id: String)

    /** その公演に紐づく支出。公演の画面に「この公演でいくら使ったか」を出すのに使う。 */
    @Query("SELECT * FROM expenses WHERE show_id = :showId ORDER BY date, id")
    suspend fun forShow(showId: String): List<Expense>

    /** バックアップ用の id 一覧 (重複判定はコアが id で行う)。 */
    @Query("SELECT id FROM expenses")
    suspend fun allIds(): List<String>

    /** バックアップ復元用。既存 id は無視し、新規のみ追加する (非破壊)。 */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAllIfAbsent(expenses: List<Expense>): List<Long>

    /**
     * 参加を付けた公演を新しい順で (iOS `attendedShowOptionsQuery` と同じ SQL)。
     *
     * 参加は公演単位とイベント単位の両方で付く。イベントに付けた人の公演も候補に出さないと、
     * 遠征費を紐づける先が無くなる。
     */
    @Query(
        """
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
    )
    suspend fun attendedShowOptions(): List<LedgerShowOptionRow>
}
