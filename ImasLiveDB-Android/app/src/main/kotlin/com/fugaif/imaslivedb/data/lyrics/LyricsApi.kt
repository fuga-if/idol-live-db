package com.fugaif.imaslivedb.data.lyrics

import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder

/** 歌詞を取りに行った結果。 */
sealed interface LyricsResult {
    data class Loaded(val lyrics: Lyrics) : LyricsResult
    /** この曲の歌詞はまだ無い。 */
    data object NotFound : LyricsResult
    /** この曲は Android ではまだ歌詞を出せない (Worker の 451。NexTone 管理曲だけ出している)。 */
    data object NotLicensed : LyricsResult
    /** ログインしていない (歌詞はログイン必須)。 */
    data object NeedsLogin : LyricsResult
    data class Failed(val message: String) : LyricsResult
}

/**
 * 歌詞まわりの Worker の口。iOS の LyricsAPI / CallGuideAPI と同じ経路。
 *
 * ⚠️ 1 リクエスト 1 曲。まとめ取りの口を足さないこと (許諾の「一括ダウンロード不可」)。
 * ⚠️ 応答を端末に保存しない (Lyrics.kt 冒頭)。送るのは行 ID・位置・時刻だけで、本文は送らない。
 */
class LyricsApi(private val client: WorkerHttpClient) {

    suspend fun lyrics(songId: String): LyricsResult = withContext(Dispatchers.IO) {
        try {
            val res = client.request("GET", "/songs/${seg(songId)}/lyrics")
            when (res.code) {
                200 -> LyricsResult.Loaded(Lyrics.parse(JSONObject(res.body ?: "{}"), songId))
                401 -> LyricsResult.NeedsLogin
                404 -> LyricsResult.NotFound
                451 -> LyricsResult.NotLicensed
                else -> LyricsResult.Failed("歌詞を読み込めませんでした (${res.code})")
            }
        } catch (e: IOException) {
            LyricsResult.Failed("通信できませんでした")
        } catch (e: org.json.JSONException) {
            LyricsResult.Failed("歌詞を読み込めませんでした")
        }
    }

    /** 行とコールの再生位置・行の被せ指定を保存する (PUT /songs/:id/timings。全置換)。 */
    suspend fun saveTimings(
        songId: String,
        lines: List<TimingEntry>,
        calls: List<TimingEntry>,
    ) = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("lines", JSONArray(lines.map { it.toJson(withLayer = true) }))
            .put("calls", JSONArray(calls.map { it.toJson(withLayer = false) }))
        check(client.request("PUT", "/songs/${seg(songId)}/timings", body), "タイミングを保存できませんでした")
    }

    /** 行の「ここ好き」を付け外しし、付け外し後のみんなの人数を返す。 */
    suspend fun setLike(songId: String, lineId: String, liked: Boolean): Int = withContext(Dispatchers.IO) {
        val res = client.request(if (liked) "PUT" else "DELETE", "/songs/${seg(songId)}/lyric-likes/${seg(lineId)}")
        check(res, "ここ好きを送れませんでした")
        JSONObject(res.body ?: "{}").optInt("likeCount", 0)
    }

    /** 行をくっつける / 切り離す (POST /songs/:id/lyric-structure)。文字は変わらない。 */
    suspend fun editStructure(songId: String, change: StructureChange) = withContext(Dispatchers.IO) {
        val body = when (change) {
            is StructureChange.Merge -> JSONObject().put("op", "merge").put("lineId", change.lineId).put("joiner", change.joiner.raw)
            is StructureChange.Split -> JSONObject().put("op", "split").put("lineId", change.lineId).put("at", change.at)
        }
        check(client.request("POST", "/songs/${seg(songId)}/lyric-structure", body), "行の区切りを変えられませんでした")
    }

    private fun check(res: com.fugaif.imaslivedb.data.net.WorkerResponse, message: String) {
        if (res.code !in 200..299) throw IOException("$message (${res.code})")
    }

    private fun seg(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
}

/** 行またはコール 1 つの再生位置 (と、行なら被せ指定)。 */
data class TimingEntry(val id: String, val startMs: Int?, val layer: String? = null) {
    fun toJson(withLayer: Boolean): JSONObject = JSONObject().apply {
        put("id", id)
        put("startMs", startMs ?: JSONObject.NULL)
        if (withLayer) put("layer", layer ?: JSONObject.NULL)
    }
}

/** くっつけるときに挟む空白。 */
enum class LyricJoiner(val raw: String, val label: String) {
    NONE("", "空白なしでくっつける"),
    HALF(" ", "半角空白でくっつける"),
    FULL("　", "全角空白でくっつける"),
}

sealed interface StructureChange {
    data class Merge(val lineId: String, val joiner: LyricJoiner) : StructureChange
    /** `at` はスカラー位置。その位置の前で切る。 */
    data class Split(val lineId: String, val at: Int) : StructureChange
}
