package com.fugaif.imaslivedb.ui.lyrics

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.suspendCancellableCoroutine
import uniffi.imas_core.OcrPiece
import uniffi.imas_core.lyricOcrLayout

/**
 * 歌詞カード (ブックレット・歌詞カード・その写真) の文字を端末の中で読む。iOS `LyricsCardOCR` の移植。
 *
 * 認識は ML Kit の日本語テキスト認識 (端末内の bundled モデル。画像はどこにも送らず、保存もしない)。
 * 読み順の作り直し (縦書き・段組み・ルビ外し・空行) はコアの `lyricOcrLayout` が決める。
 * 結果は入力欄に入れるだけで、本人が見直してから送る。認識した字は直さない。
 */
object LyricsCardOcr {
    /** 写真を順に読み、1 枚ずつ並べ直した本文を空行でつないで返す。 */
    suspend fun read(images: List<Bitmap>): String {
        val pages = mutableListOf<String>()
        for (image in images) {
            val pieces = recognize(prepared(image))
            val text = lyricOcrLayout(pieces).text
            if (text.isNotEmpty()) pages += text
        }
        return pages.joinToString("\n\n")
    }

    /**
     * 読み取りの前の下ごしらえ。色を抜いて明暗をはっきりさせ (色の地や写真の上の文字に効く)、
     * 小さい画像 (スクリーンショットの切り抜きなど) は短辺 2,000px まで拡大する。字の形は変えない。
     */
    private fun prepared(image: Bitmap): Bitmap {
        val shortSide = minOf(image.width, image.height)
        val scaled = if (shortSide > 0 && shortSide < 2000) {
            val scale = minOf(2000f / shortSide, 3f)
            Bitmap.createScaledBitmap(image, (image.width * scale).toInt(), (image.height * scale).toInt(), true)
        } else {
            image
        }

        val result = Bitmap.createBitmap(scaled.width, scaled.height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        val saturation = ColorMatrix().apply { setSaturation(0f) }
        saturation.postConcat(contrastMatrix(1.3f))
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { colorFilter = ColorMatrixColorFilter(saturation) }
        canvas.drawBitmap(scaled, 0f, 0f, paint)
        return result
    }

    /** コントラストだけを動かす行列 (明暗をはっきりさせる。色味や透明度は動かさない)。 */
    private fun contrastMatrix(contrast: Float): ColorMatrix {
        val translate = (1f - contrast) * 0.5f * 255f
        return ColorMatrix(
            floatArrayOf(
                contrast, 0f, 0f, 0f, translate,
                0f, contrast, 0f, 0f, translate,
                0f, 0f, contrast, 0f, translate,
                0f, 0f, 0f, 1f, 0f
            )
        )
    }

    /** 1 枚の文字の片 (左上原点の画素の枠)。 */
    private suspend fun recognize(image: Bitmap): List<OcrPiece> {
        val recognizer = TextRecognition.getClient(JapaneseTextRecognizerOptions.Builder().build())
        return try {
            val result = recognizer.process(InputImage.fromBitmap(image, 0)).await()
            result.textBlocks.flatMap { block -> block.lines.mapNotNull(::piece) }
        } catch (e: Exception) {
            emptyList()
        } finally {
            recognizer.close()
        }
    }

    private fun piece(line: Text.Line): OcrPiece? {
        val box = line.boundingBox ?: return null
        return OcrPiece(
            text = line.text,
            x = box.left.toDouble(),
            y = box.top.toDouble(),
            width = box.width().toDouble(),
            height = box.height().toDouble()
        )
    }

    private suspend fun <T> com.google.android.gms.tasks.Task<T>.await(): T =
        suspendCancellableCoroutine { cont ->
            addOnCompleteListener { task ->
                val exception = task.exception
                when {
                    exception != null -> cont.resumeWithException(exception)
                    task.isCanceled -> cont.cancel()
                    else -> cont.resume(task.result)
                }
            }
        }
}
