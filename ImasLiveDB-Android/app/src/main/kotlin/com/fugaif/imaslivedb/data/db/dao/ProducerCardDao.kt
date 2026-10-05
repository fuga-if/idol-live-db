package com.fugaif.imaslivedb.data.db.dao

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard

/** 名刺に出す公演 1 件の行 (表記はリポジトリがコアの `showDisplayTitle` で組む)。 */
data class ProducerCardShowRow(
    @ColumnInfo(name = "show_id") val showId: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "show_name") val showName: String?,
    @ColumnInfo(name = "event_name") val eventName: String?,
    @ColumnInfo(name = "date") val date: String?,
    @ColumnInfo(name = "venue") val venue: String?
)

/**
 * P名刺 (自分の名刺・名刺入れ) の読み書き。iOS `AppDatabase+ProducerCards` と対。
 * 名刺の組み立て・共通点・束ね方は共有コア (domain/producer_card.rs)。ここは行の出し入れだけ。
 */
@Dao
interface ProducerCardDao {

    // ---- 自分の名刺 ----

    @Query("SELECT * FROM my_producer_card WHERE id = :id")
    suspend fun myCard(id: String = MyProducerCard.SINGLETON_ID): MyProducerCard?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMyCard(card: MyProducerCard)

    @Query("SELECT COUNT(*) FROM my_producer_card")
    suspend fun myCardCount(): Int

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertMyCardIfAbsent(card: MyProducerCard): Long

    // ---- 名刺入れ ----

    @Query("SELECT * FROM received_producer_cards ORDER BY received_at DESC, id")
    suspend fun receivedCards(): List<ReceivedProducerCard>

    @Query("SELECT * FROM received_producer_cards WHERE id = :id")
    suspend fun receivedCard(id: String): ReceivedProducerCard?

    @Query("SELECT * FROM received_producer_cards WHERE payload = :payload LIMIT 1")
    suspend fun receivedCardByPayload(payload: String): ReceivedProducerCard?

    @Query("SELECT COUNT(*) FROM received_producer_cards")
    suspend fun receivedCount(): Int

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertReceived(card: ReceivedProducerCard)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertReceivedIfAbsent(card: ReceivedProducerCard): Long

    @Query("DELETE FROM received_producer_cards WHERE id = :id")
    suspend fun deleteReceived(id: String)

    /** バックアップ用の id 一覧 (重複判定はコアが id で行う)。 */
    @Query("SELECT id FROM received_producer_cards")
    suspend fun receivedIds(): List<String>

    /**
     * 同じ中身の名刺が無ければ入れる。あればそれを返す (探すのと入れるのを 1 つの書き込みで行い、
     * 同時に 2 回届いても 2 枚にしない)。
     */
    @Transaction
    suspend fun insertReceivedIfNew(card: ReceivedProducerCard): ReceivedProducerCard {
        receivedCardByPayload(card.payload)?.let { return it }
        upsertReceived(card)
        return card
    }

    /**
     * バックアップからの非破壊復元: id が同じもの、または同じ相手の名刺 (中身が同じ) が既にあれば
     * 入れない (機種変の前後で同じ相手から受け取っていても 2 枚にしない。メモを古いもので上書きしない)。
     */
    @Transaction
    suspend fun restoreReceivedIfAbsent(cards: List<ReceivedProducerCard>): Int {
        var inserted = 0
        for (card in cards) {
            if (receivedCard(card.id) != null || receivedCardByPayload(card.payload) != null) continue
            if (insertReceivedIfAbsent(card) != -1L) inserted++
        }
        return inserted
    }

    /** バックアップからの非破壊復元: 端末に自分の名刺が無いときだけ入れる。 */
    @Transaction
    suspend fun restoreMyCardIfAbsent(cards: List<MyProducerCard>): Int {
        for (card in cards) {
            if (myCardCount() > 0) break
            insertMyCardIfAbsent(card.copy(id = MyProducerCard.SINGLETON_ID))
            return 1
        }
        return 0
    }

    // ---- 公演の表記 ----

    /** 公演 id → 行。端末のマスタに無い公演 (相手の方が新しいデータを持っていた等) は返らない。 */
    @Query(
        """
        SELECT s.id AS show_id, s.event_id AS event_id, s.name AS show_name, s.date AS date,
               s.venue AS venue, e.name AS event_name
        FROM shows s JOIN events e ON e.id = s.event_id
        WHERE s.id IN (:ids)
        """
    )
    suspend fun showRows(ids: List<String>): List<ProducerCardShowRow>
}
