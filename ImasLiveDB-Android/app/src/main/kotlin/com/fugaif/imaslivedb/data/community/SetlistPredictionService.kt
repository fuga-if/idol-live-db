package com.fugaif.imaslivedb.data.community

import android.util.Log
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.voteLimitPerTarget
import java.net.URLEncoder

/**
 * セトリ予想 (みんなの予想) の取得と投票。iOS `PredictionService` の予想の部分の移植
 * (歌唱メンバー予想・マイ予想はまだ移していない)。
 *
 * 集計は `has_user_voted` (自分の票か) を含む**利用者ごとの**データなので、共有キャッシュには
 * 載せない。持つのは端末内メモリの短い覚え書き (60 秒) だけで、自分の投票・取り消しの後は
 * その公演の分を捨てて取り直す。覚え書きは「誰のセッションで取ったか」ごとに持つ
 * ([SetlistLikeService] と同じ。サインアウト・別アカウントの後に前の人の票を出さない)。
 *
 * 送る前に「ログインしているか」を見て弾かない。セッション更新中の一瞬にトークンが空になる
 * ことがあり、そこで先回りすると投票が無言で落ちる (iOS で 14th の予想が保存されなかった原因)。
 * 認証が要るかどうかはサーバの 401 に任せ、[Unauthorized] で返す。
 */
class SetlistPredictionService(private val http: WorkerHttpClient) {

    /** 1 曲ぶんの集計と自分の票。 */
    data class Prediction(val songId: String, val voteCount: Int, val hasUserVoted: Boolean)

    /** 認証されていない。呼び出し側はログイン誘導に使う。 */
    class Unauthorized : Exception("セトリ予想の投票にはログインが必要です")

    /** 1 公演の票の上限 (サーバの 409)。 */
    class VoteLimitReached : Exception() {
        override val message: String get() = "1公演につき投票できるのは${voteLimitPerTarget()}曲までです"
    }

    /** それ以外の失敗。[message] は画面にそのまま出せる和文。 */
    class RequestFailed(message: String) : Exception(message)

    private class CacheHit(val entries: List<Prediction>, val atMillis: Long)

    private data class CacheKey(val session: String?, val showId: String)

    private val cache = HashMap<CacheKey, CacheHit>()

    /** 公演の予想 (票の多い順。並びはサーバのまま)。TTL 内なら取り直さない。 */
    suspend fun fetch(showId: String): List<Prediction> = withContext(Dispatchers.IO) {
        val key = CacheKey(http.currentSession(), showId)
        synchronized(cache) {
            cache.keys.removeAll { it.session != key.session }
            cache[key]?.takeIf { System.currentTimeMillis() - it.atMillis < CACHE_TTL_MS }
        }?.let { return@withContext it.entries }

        val (code, body) = request("GET", "/shows/${enc(showId)}/predictions")
        if (code !in 200..299) throw failure(code)
        val entries = parse(body.orEmpty())
        synchronized(cache) { cache[key] = CacheHit(entries, System.currentTimeMillis()) }
        entries
    }

    /** その曲に 1 票入れる。上限は [VoteLimitReached]。 */
    suspend fun vote(showId: String, songId: String) = withContext(Dispatchers.IO) {
        val (code, _) = request(
            "POST", "/shows/${enc(showId)}/predictions", JSONObject().put("song_id", songId)
        )
        if (code == 409) throw VoteLimitReached()
        if (code !in 200..299) throw failure(code)
        invalidate(showId)
    }

    /** その曲への自分の票を取り消す。 */
    suspend fun unvote(showId: String, songId: String) = withContext(Dispatchers.IO) {
        val (code, _) = request("DELETE", "/shows/${enc(showId)}/predictions/${enc(songId)}")
        if (code !in 200..299) throw failure(code)
        invalidate(showId)
    }

    private fun invalidate(showId: String) {
        synchronized(cache) { cache.keys.removeAll { it.showId == showId } }
    }

    private fun failure(code: Int): Exception = when (code) {
        401, 403 -> Unauthorized()
        429 -> RequestFailed("投票の制限に達しました。明日またお試しください")
        -1 -> RequestFailed("通信に失敗しました。電波の良いところでもう一度お試しください")
        else -> RequestFailed("サーバーエラー (HTTP $code)")
    }

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    /** ステータスとレスポンス本文。通信自体が失敗したら code = -1。 */
    private fun request(method: String, path: String, body: JSONObject? = null): Pair<Int, String?> = try {
        val response = http.request(method, path, body)
        response.code to response.body
    } catch (e: Exception) {
        Log.w(TAG, "$method $path failed: ${e.message}")
        -1 to null
    }

    companion object {
        private const val TAG = "SetlistPrediction"
        private const val CACHE_TTL_MS = 60_000L

        /** `/shows/:id/predictions` の本文。読めない行は落とす (曲 ID の無い行は出せない)。 */
        internal fun parse(body: String): List<Prediction> = runCatching {
            val arr = JSONArray(body)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                val songId = o.optString("song_id").takeIf { it.isNotEmpty() } ?: return@mapNotNull null
                Prediction(songId, o.optInt("vote_count"), o.optBoolean("has_user_voted"))
            }
        }.getOrDefault(emptyList())
    }
}
