package com.fugaif.imaslivedb.data.db.dao

import androidx.room.ColumnInfo
import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ReceivedCardMeeting
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import java.util.UUID
import uniffi.imas_core.CardIncoming
import uniffi.imas_core.CardSamePersonChoice
import uniffi.imas_core.CardSamePersonConfirm
import uniffi.imas_core.CardStoredRef
import uniffi.imas_core.cardFirstMeetingId
import uniffi.imas_core.cardLatestMeeting
import uniffi.imas_core.cardMeetingRestorable
import uniffi.imas_core.cardReceivePlan
import uniffi.imas_core.cardSamePersonConfirm
import java.time.Instant
import java.time.temporal.ChronoUnit

/** 名刺入れの名刺の id と中身 (同じ人を探す材料)。 */
data class ReceivedCardRef(
    @ColumnInfo(name = "id") val id: String,
    @ColumnInfo(name = "payload") val payload: String
)

/** 名刺に出す公演 1 件の行 (表記はリポジトリがコアの `showDisplayTitle` で組む)。 */
data class ProducerCardShowRow(
    @ColumnInfo(name = "show_id") val showId: String,
    @ColumnInfo(name = "event_id") val eventId: String,
    @ColumnInfo(name = "show_name") val showName: String?,
    @ColumnInfo(name = "event_name") val eventName: String?,
    @ColumnInfo(name = "date") val date: String?,
    @ColumnInfo(name = "venue") val venue: String?,
    @ColumnInfo(name = "brand_id") val brandId: String? = null
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
    suspend fun deleteReceivedRow(id: String)

    /** 名刺と会った記録を一緒に消す。 */
    @Transaction
    suspend fun deleteReceived(id: String) {
        deleteMeetings(id)
        deleteReceivedRow(id)
    }

    @Query("SELECT id, payload FROM received_producer_cards")
    suspend fun receivedRefs(): List<ReceivedCardRef>

    // ---- 会った記録 ----

    @Query("SELECT * FROM received_card_meetings")
    suspend fun meetings(): List<ReceivedCardMeeting>

    @Query("SELECT * FROM received_card_meetings WHERE card_id = :cardId")
    suspend fun meetings(cardId: String): List<ReceivedCardMeeting>

    @Query("SELECT * FROM received_card_meetings WHERE id = :id")
    suspend fun meeting(id: String): ReceivedCardMeeting?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertMeeting(meeting: ReceivedCardMeeting)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertMeetingIfAbsent(meeting: ReceivedCardMeeting): Long

    @Query("DELETE FROM received_card_meetings WHERE card_id = :cardId")
    suspend fun deleteMeetings(cardId: String)

    @Query("SELECT id FROM received_card_meetings")
    suspend fun meetingIds(): List<String>

    /**
     * 名刺をしまう。同じ人の名刺があれば 1 枚にまとめて中身を新しい方に替え、会った記録を積む
     * (同じ機会にもう一度読んだときは最後の記録を新しい方に書き換える)。しまい方はコアの `cardReceivePlan`
     * (中身が同じ・名刺 id と名前が同じなら黙って、名刺 id が同じで名前が違う・名前と担当が同じなら `choice` で)。
     * 確かめる名刺を `UNDECIDED` のまま渡すと別の名刺として足す (黙って中身を差し替えない)。
     * `matchSamePerson = false` は QR の無い紙の名刺 (常に新しく足す)。探すのと書くのを 1 つの書き込みで行う。
     * 書いた後、名刺の行に最後の会った記録を写す。iOS `AppDatabase.receiveProducerCard` と対。
     */
    @Transaction
    suspend fun receive(
        fresh: ReceivedProducerCard,
        matchSamePerson: Boolean,
        choice: CardSamePersonChoice = CardSamePersonChoice.UNDECIDED
    ): ReceivedProducerCard {
        val plan = cardReceivePlan(
            CardIncoming(payload = fresh.payload, showId = fresh.showId, showDate = fresh.showDate, via = fresh.receiveVia, metAt = fresh.receivedAt),
            storedRefs(), meetings().map { it.record }, matchSamePerson, choice
        )
        val existing = plan.existingCardId?.let { receivedCard(it) }
        val row = if (existing != null) {
            existing.copy(payload = fresh.payload, source = fresh.source, updatedAt = fresh.updatedAt).also { upsertReceived(it) }
        } else {
            fresh.also { upsertReceived(it) }
        }
        plan.lastMeetingUpdate?.let { upsertMeeting(ReceivedCardMeeting.from(it)) }
        if (plan.addMeeting) {
            val id = if (existing == null) cardFirstMeetingId(row.id) else UUID.randomUUID().toString()
            upsertMeeting(
                ReceivedCardMeeting(
                    id = id, cardId = row.id, showId = fresh.showId, showDate = fresh.showDate,
                    via = fresh.via, metAt = fresh.receivedAt, payload = fresh.payload
                )
            )
        }
        copyLatestMeeting(row.id)
        return receivedCard(row.id) ?: row
    }

    /** 届いた名刺が、名刺入れのある名刺と同じ人か確かめる必要があれば、その確認の画面 (コアの `cardSamePersonConfirm`)。 */
    suspend fun samePersonConfirm(payload: String): CardSamePersonConfirm? {
        val plan = cardReceivePlan(
            CardIncoming(payload = payload, showId = null, showDate = null, via = null, metAt = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()),
            storedRefs(), meetings().map { it.record }, true, CardSamePersonChoice.UNDECIDED
        )
        val id = plan.confirmCardId ?: return null
        val existing = receivedCard(id) ?: return null
        return cardSamePersonConfirm(existing.payload, payload)
    }

    /**
     * 詳細の「この時の名刺に戻す」: 名刺の中身を会った記録のときの中身に戻す (戻せるかはコアの
     * `cardMeetingRestorable`)。写真・担当の画像は今のまま。
     */
    @Transaction
    suspend fun restorePayload(cardId: String, meetingId: String, now: String) {
        val row = receivedCard(cardId) ?: return
        val meeting = meeting(meetingId) ?: return
        if (meeting.cardId != cardId) return
        val payload = meeting.payload ?: return
        if (!cardMeetingRestorable(meeting.payload, row.payload)) return
        upsertReceived(row.copy(payload = payload, updatedAt = now))
    }

    private suspend fun storedRefs(): List<CardStoredRef> = receivedRefs().map { CardStoredRef(id = it.id, payload = it.payload) }

    /** 名刺の行に最後の会った記録 (コアの `cardLatestMeeting`) の公演・受け取り方・日時・中身を写す。 */
    private suspend fun copyLatestMeeting(cardId: String) {
        val row = receivedCard(cardId) ?: return
        val latest = cardLatestMeeting(meetings(cardId).map { it.record }, cardId) ?: return
        val updated = row.copy(
            showId = latest.showId, showDate = latest.showDate, via = latest.via, receivedAt = latest.metAt,
            payload = latest.payload ?: row.payload
        )
        if (updated != row) upsertReceived(updated)
    }

    /** 最後に会った記録の公演を変え、名刺の行にも写す (詳細の「受け取った公演を変える」)。 */
    @Transaction
    suspend fun changeLatestMeetingShow(cardId: String, showId: String?, showDate: String?, now: String) {
        val row = receivedCard(cardId) ?: return
        // 最後の記録はコアの `cardLatestMeeting` と同じ並び (日時、同じ時刻は id の大きい方)。
        val latest = meetings(cardId).maxWithOrNull(compareBy<ReceivedCardMeeting> { it.metAt }.thenBy { it.id })
        upsertMeeting(
            latest?.copy(showId = showId, showDate = showDate) ?: ReceivedCardMeeting(
                id = cardFirstMeetingId(cardId), cardId = cardId, showId = showId, showDate = showDate,
                via = row.via, metAt = row.receivedAt, payload = row.payload
            )
        )
        upsertReceived(row.copy(showId = showId, showDate = showDate, updatedAt = now))
    }

    /**
     * バックアップからの非破壊復元: 無い id の会った記録だけ足す (名刺が端末に無い記録は飛ばす)。
     * 中身が同じ別 id の名刺の記録は、コアの計画 (`planBackupImport`) で端末の名刺に付け替えてある。
     * 足した名刺の行には最後の会った記録を写す。
     */
    @Transaction
    suspend fun restoreMeetingsIfAbsent(meetings: List<ReceivedCardMeeting>): Int {
        var inserted = 0
        val touched = mutableSetOf<String>()
        for (m in meetings) {
            if (receivedCard(m.cardId) == null) continue
            if (insertMeetingIfAbsent(m) != -1L) {
                touched += m.cardId
                inserted++
            }
        }
        for (cardId in touched) copyLatestMeeting(cardId)
        return inserted
    }

    /** バックアップ用の id 一覧 (重複判定はコアが id で行う)。 */
    @Query("SELECT id FROM received_producer_cards")
    suspend fun receivedIds(): List<String>

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
            insertMyCardIfAbsent(card.withCardId().copy(id = MyProducerCard.SINGLETON_ID))
            return 1
        }
        return 0
    }

    // ---- 公演の表記 ----

    /** 公演 id → 行。端末のマスタに無い公演 (相手の方が新しいデータを持っていた等) は返らない。 */
    @Query(
        """
        SELECT s.id AS show_id, s.event_id AS event_id, s.name AS show_name, s.date AS date,
               s.venue AS venue, e.name AS event_name, e.brand_id AS brand_id
        FROM shows s JOIN events e ON e.id = s.event_id
        WHERE s.id IN (:ids)
        """
    )
    suspend fun showRows(ids: List<String>): List<ProducerCardShowRow>
}
