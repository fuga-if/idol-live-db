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
import uniffi.imas_core.CardOshiEntry
import uniffi.imas_core.CardFileImageKind
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
import uniffi.imas_core.producerCardOshiPickedIds
import com.fugaif.imaslivedb.ui.producercard.ProducerCardDirectory
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
    val songCount: Int,
    /**
     * 担当の名前とブランド (端末のマスタで引けた人だけ、アプリの並び)。名刺に載せる担当はここから
     * 本人の選択で選ぶ (選び方はコアの `producerCardOshiPickedIds`)。渡さなければ担当の id だけで組む
     * (ブランドが分からないので、上限まで並び順で載る)。
     */
    val oshiEntries: List<CardOshiEntry> = oshiIds.map { CardOshiEntry(idolId = it, name = "", brandId = "", brandLabel = "") }
) {
    /** 共通点に使う「行った公演」と「次の現場」。分け方はコア。 */
    val summary: CardRecordSummary get() = producerCardRecordSummary(JstDay.today(), attended)

    /** 名刺に載せる担当 (載せる順)。[choice] は本人の選択 (null はまだ選んでいない)。 */
    fun cardOshiIds(choice: List<String>?): List<String> = producerCardOshiPickedIds(choice, oshiEntries)
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

    suspend fun loadMyRecord(module: AppModule): ProducerCardMyRecord {
        val oshi = module.userMarkRepository.pickedIdolIdList()
        return ProducerCardMyRecord(
            oshiIds = oshi,
            attended = module.producerCardRepository.attendedShowRefs(),
            songCount = module.songRepository.fetchCollectedSongIds().size,
            oshiEntries = oshiEntries(module, oshi)
        )
    }

    /** 担当の名前とブランド (名刺に載せる担当を選ぶ材料。端末のマスタで引けない担当は入れない)。 */
    suspend fun oshiEntries(module: AppModule, oshi: List<String>): List<CardOshiEntry> =
        ProducerCardDirectory.load(module, oshi, emptyList()).oshiEntries(oshi)

    /** 名刺の入力。外した項目は空にする。担当は本人の選択 (まだ選んでいなければ自動の選び方) で。 */
    fun input(card: MyProducerCard, record: ProducerCardMyRecord): ProducerCardInput {
        val summary = record.summary
        val limits = producerCardLimits()
        return ProducerCardInput(
            name = card.name,
            message = if (card.shows(ProducerCardField.MESSAGE)) card.message else "",
            sinceYear = card.sinceYear?.takeIf { card.shows(ProducerCardField.SINCE) && it in 0..65535 }?.toUShort(),
            oshiIdolIds = if (card.shows(ProducerCardField.OSHI)) record.cardOshiIds(card.cardOshiChoice).take(limits.maxOshi.toInt()) else emptyList(),
            links = if (card.shows(ProducerCardField.LINKS)) card.links else emptyList(),
            showCount = if (card.shows(ProducerCardField.SHOW_COUNT)) summary.showCount else null,
            songCount = if (card.shows(ProducerCardField.SONG_COUNT)) record.songCount.toUInt() else null,
            nextShowId = if (card.shows(ProducerCardField.NEXT)) summary.nextShowId else null,
            attended = if (card.shows(ProducerCardField.ATTENDED)) summary.attendedPast else emptyList(),
            issuedOn = JstDay.today(),
            design = card.cardDesign,
            qrUrl = card.qrUrl,
            showBrandLabels = card.shows(ProducerCardField.BRAND_LABELS),
            cardId = card.cardId
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
            CardFileImage(idolId = id, jpeg = jpeg, kind = CardFileImageKind.OSHI)
        }

    /** 自分の名刺の写真 (切り抜いた JPEG をそのまま。元の画質で渡す)。 */
    fun myPhotoImage(context: Context): CardFileImage? {
        val jpeg = ProducerCardFiles.myPhotoFile(context)?.let { runCatching { it.readBytes() }.getOrNull() } ?: return null
        // 出どころも渡す (X のアイコンなら相手の端末でも丸く出る)。
        return CardFileImage(idolId = "", jpeg = jpeg, kind = CardFileImageKind.PHOTO, photoSource = ProducerCardFiles.myPhotoSource(context))
    }

    /**
     * 自作の名刺の画像 (表・裏。平らにした JPEG をそのまま渡す)。載せるかどうか
     * (デザインが自作の画像の名刺だけ・裏は表があるときだけ) はコアの `encodeCardFile` が決める。
     */
    fun myFaceImages(context: Context): List<CardFileImage> =
        listOf(ProducerCardFiles.Side.FRONT to CardFileImageKind.FACE_FRONT, ProducerCardFiles.Side.BACK to CardFileImageKind.FACE_BACK)
            .mapNotNull { (side, kind) ->
                val jpeg = ProducerCardFiles.myFaceFile(context, side)?.let { runCatching { it.readBytes() }.getOrNull() }
                    ?: return@mapNotNull null
                CardFileImage(idolId = "", jpeg = jpeg, kind = kind)
            }

    /**
     * 自分の名刺ファイル (名刺 + 担当の画像 + 名刺の写真 + 自作の名刺の画像)。画像を JPEG にするので
     * メインの外で呼ぶ。近くの端末との交換も同じファイルを渡す。
     */
    suspend fun myCardFile(context: Context, module: AppModule, encoded: EncodedProducerCard): ByteArray? =
        withContext(Dispatchers.Default) {
            val images = myOshiImages(module, encoded.card) + listOfNotNull(myPhotoImage(context)) + myFaceImages(context)
            encodeCardFile(payload(encoded), images)
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
