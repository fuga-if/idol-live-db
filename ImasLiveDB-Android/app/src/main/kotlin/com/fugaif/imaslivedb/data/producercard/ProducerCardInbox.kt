package com.fugaif.imaslivedb.data.producercard

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
     * 名刺をしまう。同じ中身の名刺が既にあれば新しく足さず、その名刺に画像だけ足して返す
     * (同じ相手の QR を 2 回読んでも 2 枚にしない)。[dedupe] = false は QR の無い紙の名刺
     * (名前だけで中身を作るので、同じ名前の別人と重ならないように常に新しく足す)。
     * 画像を書けなくても名刺はしまえているので、失敗は記録だけにする。
     */
    suspend fun store(
        context: Context,
        payload: String,
        images: List<CardFileImage>,
        source: ReceivedProducerCard.Source,
        show: ProducerCardShowInfo?,
        dedupe: Boolean = true
    ): ReceivedProducerCard {
        val repo = AppModule.from(context).producerCardRepository
        val fresh = ReceivedProducerCard.make(payload, source, show?.id, show?.date)
        val saved = if (dedupe) {
            repo.insertReceivedIfNew(fresh)
        } else {
            repo.saveReceived(fresh)
            fresh
        }
        attachImages(context, saved.id, images)
        notifyChanged()
        return saved
    }

    /** 後から届いた担当の画像を、しまった名刺に足す (数 MB を書くのでメインの外で)。 */
    suspend fun attachImages(context: Context, cardId: String, images: List<CardFileImage>) {
        if (images.isEmpty()) return
        withContext(Dispatchers.IO) {
            runCatching { ProducerCardFiles.saveOshiImages(context, cardId, images) }
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
