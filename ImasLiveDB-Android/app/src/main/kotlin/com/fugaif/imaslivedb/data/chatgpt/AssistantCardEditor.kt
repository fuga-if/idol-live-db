package com.fugaif.imaslivedb.data.chatgpt

import android.content.Context
import android.graphics.Bitmap
import com.fugaif.imaslivedb.data.model.MyProducerCard
import com.fugaif.imaslivedb.data.model.ProducerCardField
import com.fugaif.imaslivedb.data.producercard.ProducerCardAssembler
import com.fugaif.imaslivedb.data.producercard.ProducerCardFiles
import com.fugaif.imaslivedb.data.producercard.StickerCutout
import com.fugaif.imaslivedb.data.producercard.XAvatarFetcher
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasPortraitCrop
import com.fugaif.imaslivedb.ui.producercard.PaperCardRectifier
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import uniffi.imas_core.AiProducerCardEdit
import uniffi.imas_core.CardPhotoSource
import uniffi.imas_core.CardSticker
import uniffi.imas_core.cardStickersAdd
import uniffi.imas_core.producerCardInputErrorMessage
import uniffi.imas_core.validateProducerCard

/**
 * チャットから頼まれた P名刺の直し 1 回ぶんを、名刺の行と画像のファイルに書く。iOS `AssistantCardEditor`。
 *
 * 何を変えるか・どの画像を何に使うか・上限は、コアが検査して [AiProducerCardEdit] に詰めてある
 * (`domain::ai_producer_card`)。ここは編集画面と同じ保存の口を呼ぶだけ。
 * 画像は、発言に添えた手元の画像をそのまま使う (モデルから画像は受け取らない)。
 */
class AssistantCardEditor(
    private val context: Context,
    private val module: AppModule,
) {
    /** 書き込む前にそろえた画像 (どれか 1 枚でも欠けたら、名刺を半端に書き換えない)。 */
    private class Prepared(
        val photo: Pair<Bitmap, CardPhotoSource>?,
        val face: Bitmap?,
        val stickers: List<CardSticker>,
        val stickerData: Map<String, ByteArray>,
    )

    /** @param images その番の発言に添えた画像 (番号は 1 始まりで、この並び)。 */
    suspend fun apply(edit: AiProducerCardEdit, images: List<Bitmap>) {
        val repository = module.producerCardRepository
        var card = repository.myCard() ?: MyProducerCard.empty()
        edit.name?.let { card = card.copy(name = it) }
        edit.message?.let { card = card.copy(message = it) }
        edit.sinceYear?.let { card = card.copy(sinceYear = it.toInt()) }
        edit.links?.let { card = card.withLinks(it) }
        edit.design?.let { card = card.withCardDesign(it) }
        edit.inkKey?.let { card = card.copy(ink = it.ifEmpty { null }) }
        edit.oshiIdolIds?.let { card = card.withCardOshiChoice(it) }
        // 中身を渡された項目は、名刺から外していたら載せ直す (どれを載せ直すかはコアが決めてある)。
        val show = edit.showFields.mapNotNull { ProducerCardField.fromKey(it) }.toSet()
        card = card.withHidden(card.hidden - show)

        // QR に収まるか (リンクの長さと記録の数しだい) は、編集画面の保存と同じ検査で確かめる。
        val record = ProducerCardAssembler.loadMyRecord(module)
        validateProducerCard(ProducerCardAssembler.input(card, record))?.let {
            throw AssistantExecutor.Failure(producerCardInputErrorMessage(it))
        }

        // 画像は先に全部そろえる (取れない・切り抜けないなら、名刺を半端に書き換えない)。
        val prepared = prepare(edit, images)

        withContext(Dispatchers.IO) {
            prepared.photo?.let { (image, origin) ->
                ProducerCardFiles.saveMyPhoto(context, image, ImasPortraitCrop(), origin)
            }
            prepared.face?.let { ProducerCardFiles.saveMyFace(context, it, ProducerCardFiles.Side.FRONT) }
            if (prepared.stickerData.isNotEmpty()) {
                ProducerCardFiles.saveMyStickers(context, prepared.stickers, prepared.stickerData)
            }
        }
        // 行は保存する時点の最新に重ねて書く (名刺の変更の通知も保存の口が出す)。
        val edited = card
        repository.updateMyCard { latest -> edited.applyingEdit(latest) }
    }

    private suspend fun prepare(edit: AiProducerCardEdit, images: List<Bitmap>): Prepared {
        val photo: Pair<Bitmap, CardPhotoSource>? = when {
            edit.photoImage != null -> attached(edit.photoImage!!, images) to CardPhotoSource.PICKED
            edit.photoXHandle != null -> when (val outcome = XAvatarFetcher.fetch(edit.photoXHandle!!)) {
                is XAvatarFetcher.Outcome.Image -> outcome.bitmap to CardPhotoSource.X_ICON
                is XAvatarFetcher.Outcome.Failed ->
                    throw AssistantExecutor.Failure(outcome.message.ifEmpty { "X のアイコンを取れませんでした" })
            }
            else -> null
        }
        val face = edit.faceImage?.let { PaperCardRectifier.bounded(attached(it, images), 3000) }
        var stickers = ProducerCardFiles.myStickers(context)
        val stickerData = mutableMapOf<String, ByteArray>()
        for (number in edit.stickerImages) {
            var image = attached(number, images)
            if (edit.stickerCutout) {
                image = try {
                    StickerCutout.cutout(image)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    throw AssistantExecutor.Failure("素材の背景を切り抜けませんでした。切り抜かずに置くか、別の画像で試してください")
                }
            }
            val png = ProducerCardFiles.stickerPng(image) ?: throw AssistantExecutor.Failure("素材の画像を読み込めませんでした")
            val id = UUID.randomUUID().toString().take(8).lowercase()
            val next = cardStickersAdd(stickers, id)
            if (next.size <= stickers.size) throw AssistantExecutor.Failure("素材はこれ以上置けません")
            stickers = next
            stickerData[id] = png
        }
        return Prepared(photo, face, stickers, stickerData)
    }

    private fun attached(number: UInt, images: List<Bitmap>): Bitmap =
        images.getOrNull(number.toInt() - 1)
            ?: throw AssistantExecutor.Failure("添えた画像が見つかりませんでした。画像を添えて、もう一度頼んでください")
}
