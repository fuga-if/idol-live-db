package com.fugaif.imaslivedb.data.producercard

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.core.content.FileProvider
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ProducerCardField
import com.fugaif.imaslivedb.di.AppModule
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.CardFileImage
import uniffi.imas_core.CardRecordSummary
import uniffi.imas_core.CardShowRef
import uniffi.imas_core.EncodedProducerCard
import uniffi.imas_core.ProducerCard
import uniffi.imas_core.ProducerCardInput
import uniffi.imas_core.cardFileName
import uniffi.imas_core.cardFileTypeInfo
import uniffi.imas_core.encodeCardFile
import uniffi.imas_core.encodeProducerCard
import uniffi.imas_core.producerCardLimits
import uniffi.imas_core.producerCardPayload
import uniffi.imas_core.producerCardRecordSummary
import uniffi.imas_core.validateProducerCard

private const val TAG = "producer_card"

/** 自分の記録 (担当・参加した公演)。名刺を組むのにも、受け取った名刺との共通点にも使う。 */
data class ProducerCardMyRecord(
    /** 担当 (アプリの担当の印)。 */
    val oshiIds: List<String>,
    /** 参加を付けた公演 (今後の参加予定も含む)。 */
    val attended: List<CardShowRef>,
    /** 回収した曲の数。 */
    val songCount: Int
) {
    /** 共通点に使う「行った公演」と「次の現場」。分け方はコア。 */
    val summary: CardRecordSummary get() = producerCardRecordSummary(JstDay.today(), attended)
}

/**
 * 自分の P名刺を組み立てる。名前などは端末の表、担当・記録の数はアプリの記録から毎回。
 * iOS `ProducerCardAssembler` と対。
 *
 * 何を載せるか (外した項目を落とす) だけをここで決め、名刺の形・QR の中身・公演の縮め方・
 * 収まらない分の落とし方はコア (`encodeProducerCard`)。
 */
object ProducerCardAssembler {
    /** 共有シートに渡す名刺ファイルの置き場所 (res/xml/provider_paths.xml の cache-path と対)。 */
    private const val SHARE_DIR = "producer_card_share"

    suspend fun loadMyRecord(module: AppModule): ProducerCardMyRecord = ProducerCardMyRecord(
        oshiIds = module.userMarkRepository.pickedIdolIdList(),
        attended = module.producerCardRepository.attendedShowRefs(),
        songCount = module.songRepository.fetchCollectedSongIds().size
    )

    /** 名刺の入力。外した項目は空にする。 */
    fun input(card: MyProducerCard, record: ProducerCardMyRecord): ProducerCardInput {
        val summary = record.summary
        val limits = producerCardLimits()
        return ProducerCardInput(
            name = card.name,
            message = if (card.shows(ProducerCardField.MESSAGE)) card.message else "",
            sinceYear = card.sinceYear?.takeIf { card.shows(ProducerCardField.SINCE) && it in 0..65535 }?.toUShort(),
            oshiIdolIds = if (card.shows(ProducerCardField.OSHI)) record.oshiIds.take(limits.maxOshi.toInt()) else emptyList(),
            links = if (card.shows(ProducerCardField.LINKS)) card.links else emptyList(),
            showCount = if (card.shows(ProducerCardField.SHOW_COUNT)) summary.showCount else null,
            songCount = if (card.shows(ProducerCardField.SONG_COUNT)) record.songCount.toUInt() else null,
            nextShowId = if (card.shows(ProducerCardField.NEXT)) summary.nextShowId else null,
            attended = if (card.shows(ProducerCardField.ATTENDED)) summary.attendedPast else emptyList(),
            issuedOn = JstDay.today()
        )
    }

    /** 自分の名刺。まだ作っていない (名前が無い) なら null。 */
    fun encode(card: MyProducerCard, record: ProducerCardMyRecord): EncodedProducerCard? {
        val input = input(card, record)
        if (validateProducerCard(input) != null) return null
        return encodeProducerCard(input)
    }

    /** `#` の後ろ。 */
    fun payload(encoded: EncodedProducerCard): String = producerCardPayload(encoded.card)

    /** 自分の担当の画像 (代表の 1 枚) を送る形にする。画像を設定していない担当は入れない (判子で出る)。 */
    fun myOshiImages(module: AppModule, card: ProducerCard): List<CardFileImage> =
        card.oshiIdolIds.mapNotNull { id ->
            val file = module.customImageStore.primaryImageFile(id) ?: return@mapNotNull null
            val jpeg = ProducerCardFiles.jpeg(file) ?: return@mapNotNull null
            CardFileImage(idolId = id, jpeg = jpeg)
        }

    /** 自分の名刺ファイル (名刺 + 担当の画像)。画像を JPEG にするのでメインの外で呼ぶ。 */
    suspend fun myCardFile(module: AppModule, encoded: EncodedProducerCard): ByteArray? =
        withContext(Dispatchers.Default) {
            encodeCardFile(payload(encoded), myOshiImages(module, encoded.card))
        }

    /** 共有シートに渡す名刺ファイル (キャッシュに名刺の名前で書き、content:// にする)。 */
    suspend fun writeShareFile(context: Context, data: ByteArray, card: ProducerCard): Uri =
        withContext(Dispatchers.IO) {
            val dir = File(context.cacheDir, SHARE_DIR).apply { mkdirs() }
            val file = File(dir, cardFileName(card))
            file.writeBytes(data)
            FileProvider.getUriForFile(context, "${context.packageName}.shareprovider", file)
        }

    /** 名刺ファイルを共有シートで送る (Quick Share で Android にも、AirDrop を持つ iPhone にも届く)。 */
    fun shareFile(context: Context, uri: Uri): Boolean {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = cardFileTypeInfo().mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = ClipData.newUri(context.contentResolver, "producer_card", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        return runCatching {
            context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.onFailure { Log.e(TAG, "producer_card_share_failed", it) }.isSuccess
    }
}
