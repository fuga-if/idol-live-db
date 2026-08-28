package com.fugaif.imaslivedb.ui.events

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.community.DeviceIdentity
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/**
 * 公演ごとの「この曲良かった」 like をサーバから取得 / 投票するクライアント。
 * iOS `SetlistLikeService` の移植。
 *
 * star toggle なので idempotent — 多重 POST しても 1 票、DELETE は 0 票まで。
 *
 * 集計レスポンスは `has_user_liked` (自分の like か) を含む**ユーザー固有**データなので、
 * 共有キャッシュには絶対載せない。ここが持つのは端末内メモリの短命 TTL キャッシュだけで、
 * 同じ公演のセトリを開き直すたびにサーバを叩くのを抑えるためのもの。like 数は他人の操作でも
 * 増減するので TTL は短く (60 秒)、自分の like/unlike は該当曲だけその場で patch する。
 */
class SetlistLikeService private constructor(private val appContext: Context) {

    /** 1 曲ぶんの集計 + 自分の like 状態。 */
    data class LikeEntry(val songId: String, val likeCount: Int, val hasUserLiked: Boolean)

    /** like / unlike が「認証されていない」で弾かれたことを表す。呼び出し側はログイン誘導に使う。 */
    class Unauthorized : Exception("Like するにはログインが必要です")

    private class CacheHit(val entries: List<LikeEntry>, val atMillis: Long)

    private val cache = HashMap<String, CacheHit>()

    /** 公演の全曲ぶんの集計。TTL 内なら再取得しない。 */
    suspend fun fetch(showId: String): List<LikeEntry> = withContext(Dispatchers.IO) {
        synchronized(cache) {
            cache[showId]?.takeIf { System.currentTimeMillis() - it.atMillis < CACHE_TTL_MS }
        }?.let { return@withContext it.entries }

        val (code, body) = request("GET", "/shows/${enc(showId)}/likes")
        if (code !in 200..299 || body.isNullOrEmpty()) return@withContext emptyList()
        val entries = runCatching {
            val arr = JSONArray(body)
            (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                LikeEntry(o.optString("song_id"), o.optInt("like_count"), o.optBoolean("has_user_liked"))
            }
        }.getOrDefault(emptyList())
        synchronized(cache) { cache[showId] = CacheHit(entries, System.currentTimeMillis()) }
        entries
    }

    suspend fun like(showId: String, songId: String): LikeEntry =
        toggle("POST", showId, songId)

    suspend fun unlike(showId: String, songId: String): LikeEntry =
        toggle("DELETE", showId, songId)

    private suspend fun toggle(method: String, showId: String, songId: String): LikeEntry =
        withContext(Dispatchers.IO) {
            val (code, body) = request(method, "/shows/${enc(showId)}/songs/${enc(songId)}/like")
            // 401 は「トークンが無い / 失効」。ここで isSignedIn を先読みして弾かないのは、
            // セッション更新中の一瞬でも投票を無言で落としたくないため (iOS と同じ判断)。
            if (code == 401 || code == 403) throw Unauthorized()
            if (code !in 200..299 || body.isNullOrEmpty()) throw IllegalStateException("like failed: HTTP $code")
            val json = JSONObject(body)
            val entry = LikeEntry(
                songId = json.optString("song_id").ifEmpty { songId },
                likeCount = json.optInt("like_count"),
                hasUserLiked = json.optBoolean("liked")
            )
            patchCache(showId, entry)
            entry
        }

    /**
     * 自分の操作の結果だけキャッシュに反映する。取得時刻 (atMillis) は据え置きで、
     * 集計そのものの鮮度 (他人の票) は延ばさない。
     */
    private fun patchCache(showId: String, entry: LikeEntry) {
        synchronized(cache) {
            val hit = cache[showId] ?: return
            val entries = hit.entries.filter { it.songId != entry.songId } + entry
            cache[showId] = CacheHit(entries, hit.atMillis)
        }
    }

    /** サインアウト / アカウント切替時に呼ぶ。has_user_liked は利用者ごとの値なので全部捨てる。 */
    fun clearCache() {
        synchronized(cache) { cache.clear() }
    }

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    /** ステータスとレスポンス本文を返す最小の HTTP。通信自体が失敗したら code = -1。 */
    private fun request(method: String, path: String): Pair<Int, String?> = try {
        val conn = (URL(BASE + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
            AppModule.from(appContext).authService.sessionToken
                ?.let { setRequestProperty("Authorization", "Bearer $it") }
        }
        val code = conn.responseCode
        val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
            ?.bufferedReader()?.use { it.readText() }
        conn.disconnect()
        code to text
    } catch (e: Exception) {
        Log.w(TAG, "$method $path failed: ${e.message}")
        -1 to null
    }

    companion object {
        private const val BASE = "https://imas-live-api.tokata3011.workers.dev"
        private const val TAG = "SetlistLike"
        private const val CACHE_TTL_MS = 60_000L

        @Volatile
        private var instance: SetlistLikeService? = null

        /** 集計キャッシュを画面をまたいで共有するため単一インスタンスにする。 */
        fun get(context: Context): SetlistLikeService =
            instance ?: synchronized(this) {
                instance ?: SetlistLikeService(context.applicationContext).also { instance = it }
            }
    }
}
