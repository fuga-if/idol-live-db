package com.fugaif.imaslivedb.data.producercard

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import uniffi.imas_core.XAvatarLookup
import uniffi.imas_core.xAvatarLookup
import uniffi.imas_core.xAvatarLookupMessage
import uniffi.imas_core.xProfileApiUrl

/**
 * 名刺の写真の欄の「X のアイコンを使う」。名刺のリンクの X の ID から、公開のプロフィールを
 * 端末が読み、アイコンの画像を取ってくる (ログインはしない・サーバを通さない)。iOS `XAvatarFetcher` と対。
 *
 * どの ID を使うか・どこを読むか・返事の分け方・画像の大きさの選び方・取れなかったときの案内は
 * コア (`cardXAvatarHandle` / `xProfileApiUrl` / `xAvatarLookup` / `xAvatarLookupMessage`)。
 * ここは通信だけ。控えを残さず (他人のプロフィールの返事・画像を端末に貯めない)、大きさに上限を設けて
 * 超えたら読むのをやめる。
 */
private const val TAG = "producer_card"

object XAvatarFetcher {
    sealed interface Outcome {
        data class Image(val bitmap: Bitmap) : Outcome
        /** 取れなかった。[message] は画面に出す案内 (写真から選ぶ形に戻る)。 */
        data class Failed(val message: String) : Outcome
    }

    /** 1 回の読み込みの時間の上限 (つなぐ・待つ)。 */
    private const val TIMEOUT_MS = 15_000
    /** 全体の時間の上限。 */
    private const val TOTAL_TIMEOUT_MS = 30_000L
    /** 画像の大きさの上限 (アイコンは数百 KB まで。誤って大きなものを受け取らない)。 */
    private const val MAX_IMAGE_BYTES = 8 * 1024 * 1024
    /** プロフィールの返事の大きさの上限 (数 KB のもの)。 */
    private const val MAX_PROFILE_BYTES = 512 * 1024

    suspend fun fetch(handle: String): Outcome = withContext(Dispatchers.IO) {
        withTimeoutOrNull(TOTAL_TIMEOUT_MS) { fetchNow(handle) }
            ?: Outcome.Failed(xAvatarLookupMessage(XAvatarLookup.Unavailable, handle).orEmpty())
    }

    private fun fetchNow(handle: String): Outcome {
        val lookup = lookup(handle)
        if (lookup is XAvatarLookup.Found) {
            for (raw in lookup.imageUrls) {
                image(raw)?.let { return Outcome.Image(it) }
            }
            return Outcome.Failed(xAvatarLookupMessage(XAvatarLookup.Unavailable, handle).orEmpty())
        }
        return Outcome.Failed(xAvatarLookupMessage(lookup, handle).orEmpty())
    }

    private fun lookup(handle: String): XAvatarLookup {
        val raw = xProfileApiUrl(handle) ?: return XAvatarLookup.NotFound
        val (status, body) = limitedGet(raw, MAX_PROFILE_BYTES, accept = "application/json")
            ?: return XAvatarLookup.Unavailable
        return xAvatarLookup(handle, status.coerceIn(0, UShort.MAX_VALUE.toInt()).toUShort(), body.toString(Charsets.UTF_8))
    }

    private fun image(raw: String): Bitmap? {
        val (status, body) = limitedGet(raw, MAX_IMAGE_BYTES, accept = "image/*") ?: return null
        if (status != 200) return null
        return runCatching { BitmapFactory.decodeByteArray(body, 0, body.size) }.getOrNull()
    }

    /** 上限を超えたら読むのをやめる (大きすぎる返事を最後まで受け取らない)。読めなければ null。 */
    private fun limitedGet(raw: String, maxBytes: Int, accept: String): Pair<Int, ByteArray>? = runCatching {
        val connection = URL(raw).openConnection() as HttpURLConnection
        try {
            connection.useCaches = false
            connection.instanceFollowRedirects = false
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.setRequestProperty("Accept", accept)
            val status = connection.responseCode
            if (connection.contentLengthLong > maxBytes) return@runCatching null
            val stream = if (status >= 400) connection.errorStream else connection.inputStream
            val out = ByteArrayOutputStream()
            stream?.use { input ->
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    out.write(buffer, 0, n)
                    if (out.size() > maxBytes) return@runCatching null
                }
            }
            status to out.toByteArray()
        } finally {
            connection.disconnect()
        }
    }.onFailure { Log.w(TAG, "x_avatar_fetch_failed ${it.javaClass.simpleName}") }.getOrNull()
}
