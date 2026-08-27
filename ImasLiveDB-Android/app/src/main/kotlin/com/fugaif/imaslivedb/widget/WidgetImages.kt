package com.fugaif.imaslivedb.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * ウィジェットに載せる画像の読み出し。
 *
 * ## なぜサイズを絞るか
 *
 * ウィジェットの中身は RemoteViews としてランチャーのプロセスへ渡る。画像は Bitmap の
 * まま同梱されるので、原寸 (取り込み時に最長辺 1024px) をそのまま載せると 1 枚 4MB
 * (1024×1024×4byte) になる。システムは 1 更新あたりのビットマップ量に上限を持っており
 * (画面サイズ由来。超えると "exceeds maximum bitmap memory usage" で更新が捨てられる)、
 * 端末が小さいほど厳しい。ホーム画面のウィジェットは大きくても画面の半分程度なので、
 * [MAX_WIDGET_IMAGE_PX] まで落として載せる。
 *
 * ## なぜ URI ではなく Bitmap で渡すか
 *
 * `ImageProvider(uri)` ならランチャー側が読み込むのでビットマップ量の問題は消えるが、
 * 画像は `filesDir` (このアプリ専用領域) にあり、別 UID のランチャーからは読めない。
 * FileProvider + ランチャーへの URI 権限付与が要るうえ、権限はランチャーの再起動で
 * 消えるため画像が突然消えるウィジェットになる。Bitmap で渡す方が確実。
 */
object WidgetImages {

    private const val TAG = "ImasWidget"

    /** ウィジェット全面に出す画像の最長辺 (px)。上のコメントの上限に収めるための値。 */
    private const val MAX_WIDGET_IMAGE_PX = 512

    /** ジャケ写のような小さい枠に出す画像の最長辺 (px)。 */
    private const val MAX_THUMBNAIL_PX = 256

    /** ジャケ写のダウンロード上限。ウィジェット更新は goAsync の 10 秒制限の中で走るので短くする。 */
    private const val ARTWORK_TIMEOUT_MS = 3_000L

    private const val ARTWORK_CACHE_DIR = "widget_artwork"

    /**
     * ローカルの画像ファイルを、ウィジェットに載せられる大きさまで落として読む。
     * 壊れたファイル・巨大ファイルでも落ちないよう、まず境界だけ読んで粗デコードする。
     */
    fun decode(file: File, maxPixels: Int = MAX_WIDGET_IMAGE_PX): Bitmap? = runCatching {
        if (!file.isFile) return null
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.absolutePath, bounds)
        val longSide = maxOf(bounds.outWidth, bounds.outHeight)
        if (longSide <= 0) return null
        val options = BitmapFactory.Options().apply { inSampleSize = sampleSizeFor(longSide, maxPixels) }
        val decoded = BitmapFactory.decodeFile(file.absolutePath, options) ?: return null
        // inSampleSize は 2 の冪でしか刻めないので、最大 2 倍の余りが残る。仕上げに正確な倍率で縮める。
        scaleDown(decoded, maxPixels)
    }.onFailure { Log.w(TAG, "画像の読み込みに失敗: ${file.name}", it) }.getOrNull()

    /**
     * 「今日の1曲」のジャケ写。外部 CDN (mzstatic 等) にあるので、
     * 一度落としたら `cacheDir` に置いて次回以降はそこから読む。
     *
     * 取得に失敗しても null を返すだけ (ウィジェットは音符のプレースホルダで出る)。
     * 曲は日替わりなので、キャッシュは最新 1 曲分だけ残して他は消す。
     */
    suspend fun artwork(context: Context, songId: String, url: String?): Bitmap? {
        if (url.isNullOrBlank()) return null
        val dir = File(context.cacheDir, ARTWORK_CACHE_DIR)
        val cached = File(dir, "$songId.img")
        if (cached.isFile) return decode(cached, MAX_THUMBNAIL_PX)

        val bytes = withTimeoutOrNull(ARTWORK_TIMEOUT_MS) { download(url) } ?: return null
        return withContext(Dispatchers.IO) {
            runCatching {
                dir.mkdirs()
                // 日替わりで 1 枚しか要らないので、古い日の分はここで掃除する。
                dir.listFiles()?.forEach { if (it != cached) it.delete() }
                cached.writeBytes(bytes)
            }.onFailure { Log.w(TAG, "ジャケ写のキャッシュに失敗", it) }
            decode(cached, MAX_THUMBNAIL_PX)
        }
    }

    private suspend fun download(url: String): ByteArray? = withContext(Dispatchers.IO) {
        runCatching {
            // 平文 HTTP は許可していない (アプリの通信は全て https)。念のためここでも弾く。
            if (!url.startsWith("https://")) return@runCatching null
            val connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = ARTWORK_TIMEOUT_MS.toInt()
                readTimeout = ARTWORK_TIMEOUT_MS.toInt()
            }
            try {
                if (connection.responseCode != HttpURLConnection.HTTP_OK) return@runCatching null
                connection.inputStream.use { it.readBytes() }
            } finally {
                connection.disconnect()
            }
        }.onFailure { Log.w(TAG, "ジャケ写の取得に失敗", it) }.getOrNull()
    }

    private fun sampleSizeFor(longSide: Int, maxPixels: Int): Int {
        var sample = 1
        while (longSide / sample > maxPixels * 2) sample *= 2
        return sample
    }

    private fun scaleDown(bitmap: Bitmap, maxPixels: Int): Bitmap {
        val longSide = maxOf(bitmap.width, bitmap.height)
        if (longSide <= maxPixels) return bitmap
        val scale = maxPixels.toFloat() / longSide
        val width = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val height = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return Bitmap.createScaledBitmap(bitmap, width, height, true)
    }
}
