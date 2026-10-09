package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ProducerCardShowInfo
import com.fugaif.imaslivedb.data.model.ReceivedCardMeeting
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import java.time.Instant
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.temporal.ChronoUnit
import uniffi.imas_core.CardShowRef
import uniffi.imas_core.showDisplayTitle

/**
 * P名刺 (自分の名刺と名刺入れ) の読み書き。iOS `ProducerCardStoring` / `GRDBProducerCardRepository` と対。
 *
 * 名刺は端末にしか無い (クラウドにもサーバにも上げない)。**端末ローカル唯一データ**なので
 * 破壊的な移行はしない。名刺の組み立て・共通点・束ね方はコア。ここは行の出し入れだけ。
 */
class ProducerCardRepository(private val db: AppDatabase) {

    private val dao get() = db.producerCardDao()

    private fun now(): String = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString()

    /** 自分の名刺。まだ作っていなければ null。 */
    suspend fun myCard(): MyProducerCard? = dao.myCard()

    suspend fun saveMyCard(card: MyProducerCard) {
        dao.upsertMyCard(card.withCardId().copy(id = MyProducerCard.SINGLETON_ID, updatedAt = now()))
    }

    /** 自分の名刺の行を読んで直して書くのを 1 本ずつ流す ([updateMyCard])。 */
    private val myCardLock = Mutex()

    /**
     * 自分の名刺の行を、今の行 (まだ無ければ null) から組み直して書く。読んでから書くまでを 1 本ずつ流すので、
     * P名刺の編集の保存と P名刺の画像の選択の保存が並んでも、片方の変更をもう片方が古い行で消さない。
     * [transform] が null を返したら書かない。書いた行を返す。
     */
    suspend fun updateMyCard(transform: (MyProducerCard?) -> MyProducerCard?): MyProducerCard? =
        myCardLock.withLock {
            val next = transform(dao.myCard()) ?: return@withLock null
            next.withCardId().copy(id = MyProducerCard.SINGLETON_ID, updatedAt = now()).also { dao.upsertMyCard(it) }
        }

    /** 受け取った名刺 (新しく受け取った順)。 */
    suspend fun receivedCards(): List<ReceivedProducerCard> = dao.receivedCards()

    suspend fun receivedCard(id: String): ReceivedProducerCard? = dao.receivedCard(id)

    /** 同じ中身の名刺が既にあればそれを返す (同じ相手を 2 回読んでも 2 枚にしない)。 */
    suspend fun receivedCardByPayload(payload: String): ReceivedProducerCard? = dao.receivedCardByPayload(payload)

    /**
     * 名刺をしまう。同じ人の名刺があれば 1 枚にまとめて中身を新しい方に替え、会った記録を積む
     * (しまい方はコアの `cardReceivePlan`。探すのと書くのは 1 つの書き込み)。
     */
    suspend fun receive(card: ReceivedProducerCard, matchSamePerson: Boolean): ReceivedProducerCard =
        dao.receive(card, matchSamePerson)

    /** 会った記録 ([cardId] が null なら全部。並べ方・何回目かはコアの `cardMeetingViews`)。 */
    suspend fun meetings(cardId: String? = null): List<ReceivedCardMeeting> =
        if (cardId == null) dao.meetings() else dao.meetings(cardId)

    /** 最後に会った記録の公演を変える (名刺の行にも写す)。 */
    suspend fun changeLatestMeetingShow(cardId: String, showId: String?, showDate: String?) =
        dao.changeLatestMeetingShow(cardId, showId, showDate, now())

    /** 同じ id があれば上書きし、無ければ足す。 */
    suspend fun saveReceived(card: ReceivedProducerCard) {
        dao.upsertReceived(card.copy(updatedAt = now()))
    }

    suspend fun deleteReceived(id: String) = dao.deleteReceived(id)

    suspend fun receivedCount(): Int = dao.receivedCount()

    // ---- バックアップ ----

    suspend fun receivedIds(): List<String> = dao.receivedIds()

    suspend fun restoreReceivedIfAbsent(cards: List<ReceivedProducerCard>): Int =
        if (cards.isEmpty()) 0 else dao.restoreReceivedIfAbsent(cards)

    suspend fun meetingIds(): List<String> = dao.meetingIds()

    suspend fun restoreMeetingsIfAbsent(meetings: List<ReceivedCardMeeting>): Int =
        if (meetings.isEmpty()) 0 else dao.restoreMeetingsIfAbsent(meetings)

    suspend fun restoreMyCardIfAbsent(cards: List<MyProducerCard>): Int =
        if (cards.isEmpty()) 0 else dao.restoreMyCardIfAbsent(cards)

    // ---- 公演 ----

    /**
     * 公演 id → 表記・日付・会場。表記はコアの `showDisplayTitle` 一本。
     * 端末のマスタに無い公演 (相手の方が新しいデータを持っていた等) は返さない。
     */
    suspend fun showInfos(ids: List<String>): Map<String, ProducerCardShowInfo> {
        val unique = ids.filter { it.isNotEmpty() }.distinct()
        if (unique.isEmpty()) return emptyMap()
        // SQLite の引数の上限 (999) を超えないように分けて引く。
        return unique.chunked(500).flatMap { dao.showRows(it) }.associate { row ->
            val date = row.date.orEmpty()
            row.showId to ProducerCardShowInfo(
                id = row.showId,
                eventId = row.eventId,
                date = date,
                label = showDisplayTitle(row.eventName.orEmpty(), row.showName.orEmpty(), date),
                venue = row.venue,
                brandId = row.brandId
            )
        }
    }

    /** 参加を付けた公演 (今後の参加予定も含む) の id と日付。名刺の記録と共通点の材料。 */
    suspend fun attendedShowRefs(): List<CardShowRef> =
        db.expenseDao().attendedShowOptions().map { CardShowRef(showId = it.showId, date = it.date.orEmpty()) }
}
