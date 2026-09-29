package com.fugaif.imaslivedb.data.model

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import java.time.Instant
import java.util.UUID
import uniffi.imas_core.ExpenseCategory
import uniffi.imas_core.expenseCategoryFromKey
import uniffi.imas_core.expenseCategoryKey

/**
 * アイマス関連の支出 1 件 (家計簿)。**端末ローカル唯一データ** (iOS `Expense` と同型)。
 *
 * クラウドにもサーバにも無く、機種変で持ち出せるのはバックアップ (引き継ぎコード/ファイル) だけ。
 * `user_marks` / `personal_tags` と同じ扱いで、破壊的な移行はしない。
 *
 * 費目・集計・金額の表記は共有コア (`domain/ledger.rs`) が持つ。ここは器だけ。
 * [category] には**英字キー**を入れる (ラベルを変えても記録が迷子にならない)。
 */
@Entity(
    tableName = "expenses",
    // 期間の集計と公演別の集計がそれぞれ全表走査にならないように (MIGRATION_16_17 と対)。
    indices = [
        Index(name = "idx_expenses_date", value = ["date"]),
        Index(name = "idx_expenses_show", value = ["show_id"])
    ]
)
data class Expense(
    @PrimaryKey
    @ColumnInfo(name = "id")
    val id: String,
    /** `YYYY-MM-DD`。 */
    @ColumnInfo(name = "date")
    val date: String,
    /** `expenseCategoryKey(category)` の値。 */
    @ColumnInfo(name = "category")
    val category: String,
    /** 円。整数だけ (小数を持つと集計のたびに誤差が乗る)。 */
    @ColumnInfo(name = "amount")
    val amount: Long,
    /** 紐づく公演。入っていれば遠征の費用として公演別に集計される。 */
    @ColumnInfo(name = "show_id")
    val showId: String? = null,
    /** 紐づく公演が属するイベント。イベントで束ねた集計に使う。 */
    @ColumnInfo(name = "event_id")
    val eventId: String? = null,
    @ColumnInfo(name = "note")
    val note: String? = null,
    @ColumnInfo(name = "updated_at")
    val updatedAt: String
) {
    /** 保存値 → 費目。知らないキーは「その他」に落ちる (コアの規則)。 */
    val categoryValue: ExpenseCategory get() = expenseCategoryFromKey(category)

    companion object {
        /** 新規作成。id と更新時刻はここで振る (画面ごとに違う振り方をしないため)。 */
        fun make(
            date: String,
            category: ExpenseCategory,
            amount: Long,
            showId: String?,
            eventId: String?,
            note: String?
        ): Expense = Expense(
            id = UUID.randomUUID().toString(),
            date = date,
            category = expenseCategoryKey(category),
            amount = amount,
            showId = showId,
            eventId = eventId,
            note = note?.takeIf { it.isNotEmpty() },
            updatedAt = Instant.now().toString()
        )
    }
}
