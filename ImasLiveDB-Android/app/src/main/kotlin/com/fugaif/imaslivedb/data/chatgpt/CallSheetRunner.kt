package com.fugaif.imaslivedb.data.chatgpt

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Rect
import android.util.Base64
import com.fugaif.imaslivedb.ui.lyrics.LyricsCardOcr
import java.io.ByteArrayOutputStream
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import uniffi.imas_core.CallSheetReading
import uniffi.imas_core.callSheetAnswer
import uniffi.imas_core.callSheetMaxImages
import uniffi.imas_core.callSheetRequest

/**
 * コール表の画像を、利用者の ChatGPT プランに書き写してもらう。iOS `CallSheetRunner`。
 *
 * 頼み方・答えの検証・歌詞への直し方は全部コア (`agent::tools::call_sheet_reader` / `domain::call_guide_import`)。
 * ここは画像を縮めて運び、同じ画像を端末の文字認識にも通して、突き合わせの材料をコアに渡すだけ。
 */
class CallSheetRunner(private val tasks: ChatGptPlanTaskRunner) {
    suspend fun read(images: List<Bitmap>, onProgress: (String) -> Unit): CallSheetReading {
        val picked = images.take(callSheetMaxImages().toInt())
        // 端末の中の文字認識。モデルが画像に無い歌詞を覚えで補っていないかを、コアがこれと突き合わせる。
        onProgress("画像の字を確かめています…")
        val ocrText = LyricsCardOcr.read(picked).text
        currentCoroutineContext().ensureActive()

        val encoded = withContext(Dispatchers.Default) { picked.mapNotNull(::jpegBase64) }
        val request = callSheetRequest(encoded) ?: throw ChatGptPlanTaskException("画像を読み込めませんでした")
        onProgress("ChatGPT が書き写しています…")
        return tasks.run(request, onProgress) { _, _, text ->
            val reading = callSheetAnswer(text, ocrText)
                ?: throw ChatGptPlanTaskException("歌詞とコールを読み取れませんでした。字がはっきり写った画像で試してください")
            ChatGptPlanTaskRunner.Outcome.Finished(reading)
        }
    }

    /** 長辺を上限に縮めて JPEG にし、base64 にする。 */
    private fun jpegBase64(image: Bitmap): String? {
        val longest = max(image.width, image.height)
        val ratio = if (longest > MAX_SIDE) MAX_SIDE.toFloat() / longest else 1f
        val width = max(1, (image.width * ratio).roundToInt())
        val height = max(1, (image.height * ratio).roundToInt())
        val resized = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(resized)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(image, null, Rect(0, 0, width, height), null)
        val out = ByteArrayOutputStream()
        val ok = resized.compress(Bitmap.CompressFormat.JPEG, 80, out)
        resized.recycle()
        return if (ok) Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP) else null
    }

    private companion object {
        /** 送る画像の長辺の上限 (画素)。縦長のコール表でも字が潰れない大きさ。 */
        const val MAX_SIDE = 2048
    }
}
