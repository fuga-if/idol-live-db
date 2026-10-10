package com.fugaif.imaslivedb.data.producercard

import uniffi.imas_core.CardReceiveVia
import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.ProducerCardShowInfo
import com.fugaif.imaslivedb.data.model.ReceivedProducerCard
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import uniffi.imas_core.CardFileImage
import uniffi.imas_core.CardSamePersonChoice
import uniffi.imas_core.CardSamePersonConfirm
import uniffi.imas_core.cardExchangeShowCandidates

private const val TAG = "producer_card"

/**
 * 受け取った名刺を名刺入れにしまう。iOS `ProducerCardInbox` と対。入口 (QR・リンク・名刺ファイル・
 * 近くの端末) が複数あるので、しまい方はここ 1 か所にまとめる。
 */
object ProducerCardInbox {
    private val _changes = MutableSharedFlow<Unit>(extraBufferCapacity = 8)

    /** 名刺入れが変わった (受け取った・消した・メモを書いた)。名刺入れの画面と数の札が読み直す。 */
    val changes: SharedFlow<Unit> = _changes.asSharedFlow()

    private fun notifyChanged() {
        _changes.tryEmit(Unit)
    }

    /** 受け取った公演の候補 (今日 → 昨日の参加公演)。先頭が既定。選び方はコア。 */
    fun exchangeShowCandidates(record: ProducerCardMyRecord): List<String> =
        cardExchangeShowCandidates(JstDay.today(), record.attended)

    /**
     * 名刺をしまう。同じ人の名刺 (中身が同じ・名刺 id と名前が同じ、または確かめて同じ人を選んだ) が既にあれば
     * 新しく足さず、1 枚にまとめて中身を新しい方に替え、会った記録を積む (同じ相手の QR を同じ公演で 2 回読んでも
     * 記録は 1 つ)。確かめる名刺を [choice] = `UNDECIDED` のまま渡すと別の名刺として足す (確認は [samePersonConfirm])。
     * 届いた画像 (写真・担当の画像) はしまった名刺に書く。[dedupe] = false は QR の無い紙の名刺
     * (名前だけで中身を作るので、同じ名前の別人と重ならないように常に新しく足す)。
     * 画像を書けなくても名刺はしまえているので、失敗は記録だけにする。
     */
    suspend fun store(
        context: Context,
        payload: String,
        images: List<CardFileImage>,
        source: ReceivedProducerCard.Source,
        via: CardReceiveVia,
        show: ProducerCardShowInfo?,
        dedupe: Boolean = true,
        choice: CardSamePersonChoice = CardSamePersonChoice.UNDECIDED
    ): ReceivedProducerCard {
        val repo = AppModule.from(context).producerCardRepository
        val fresh = ReceivedProducerCard.make(payload, source, show?.id, show?.date, via = via)
        val saved = repo.receive(fresh, matchSamePerson = dedupe, choice = choice)
        attachImages(context, saved.id, images)
        notifyChanged()
        return saved
    }

    /** 届いた名刺が名刺入れのある名刺と同じ人か確かめる必要があれば、その確認の画面。 */
    suspend fun samePersonConfirm(context: Context, payload: String): CardSamePersonConfirm? =
        runCatching { AppModule.from(context).producerCardRepository.samePersonConfirm(payload) }.getOrNull()

    /** 後から届いた画像 (担当の画像・名刺の写真) を、しまった名刺に足す (数 MB を書くのでメインの外で)。 */
    suspend fun attachImages(context: Context, cardId: String, images: List<CardFileImage>) {
        if (images.isEmpty()) return
        withContext(Dispatchers.IO) {
            runCatching { ProducerCardFiles.saveImages(context, cardId, images) }
                .onFailure { Log.e(TAG, "producer_card_image_save_failed", it) }
        }
        notifyChanged()
    }

    suspend fun delete(context: Context, card: ReceivedProducerCard) {
        AppModule.from(context).producerCardRepository.deleteReceived(card.id)
        withContext(Dispatchers.IO) { ProducerCardFiles.deleteAll(context, card.id) }
        notifyChanged()
    }

    suspend fun update(context: Context, card: ReceivedProducerCard) {
        AppModule.from(context).producerCardRepository.saveReceived(card)
        notifyChanged()
    }

    /** 外から足した写真などを知らせる (紙の名刺の取り込み)。 */
    fun changed() = notifyChanged()
}
