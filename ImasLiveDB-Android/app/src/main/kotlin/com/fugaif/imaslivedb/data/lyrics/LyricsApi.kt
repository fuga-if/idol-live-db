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

    /**
     * 行ごとの歌唱者 (アイドル id) と、行の途中で歌う人が変わるところ ([breaks]) を保存する
     * (PUT /songs/:id/parts。全置換で、載せなかった行のパートは消える)。[PartsLine.breaks] が
     * null ならその行の区切りは送らない (サーバは今の区切りを残す)。歌詞本文は送らない。
     */
    suspend fun saveParts(songId: String, lines: List<PartsLine>) = withContext(Dispatchers.IO) {
        val body = JSONObject().put(
            "lines",
            JSONArray(lines.map { line ->
                JSONObject().put("id", line.id).put("singers", JSONArray(line.singers)).apply {
                    line.breaks?.let { breaks ->
                        put("breaks", JSONArray(breaks.map { b ->
                            JSONObject().put("at", b.at).put("singers", JSONArray(b.singers))
                        }))
                    }
                }
            })
        )
        check(client.request("PUT", "/songs/${seg(songId)}/parts", body), "パート分けを保存できませんでした")
    }

    /**
     * 歌詞の投稿 (POST /songs/:id/lyric-submissions)。歌詞の無い曲ならその場で公開され、
     * 運営はあとから確認する。既に歌詞のある曲への投稿も、その場で公開される (前の版はサーバに残る)。
     * ログイン必須・1 日 20 曲 (サーバの rate limit)。応答に本文は返らない。
     *
     * 投稿ガイドラインへの同意が必須 (入力元は書かせない。どこから写したかは確かめようがないので
     * 規約で縛る)。ボディは Worker 側 (`routes/lyric_submissions.ts`) と同じ snake_case
     * (`agreed_to_guideline` / `text`)。
     *
     * @return 公開されたら true (歌詞の無い曲)、預かっただけなら false。
     */
    suspend fun submitLyricSubmission(songId: String, text: String): Boolean = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("agreed_to_guideline", true)
            .put("text", text)
        val res = client.request("POST", "/songs/${seg(songId)}/lyric-submissions", body)
        check(res, "歌詞を送信できませんでした")
        JSONObject(res.body ?: "{}").optBoolean("published", false)
    }

    /** 公開中の歌詞の 1 行だけを直す (PUT /songs/:id/lyric-lines/:line_id)。すぐ公開される。 */
    suspend fun editLine(songId: String, lineId: String, text: String) = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("agreed_to_guideline", true)
            .put("text", text)
        check(client.request("PUT", "/songs/${seg(songId)}/lyric-lines/${seg(lineId)}", body), "行を直せませんでした")
    }

    /** 行をくっつける / 切り離す (POST /songs/:id/lyric-structure)。文字は変わらない。 */
    suspend fun editStructure(songId: String, change: StructureChange) = withContext(Dispatchers.IO) {
        val body = when (change) {
            is StructureChange.Merge -> JSONObject().put("op", "merge").put("lineId", change.lineId).put("joiner", change.joiner.raw)
            is StructureChange.Split -> JSONObject().put("op", "split").put("lineId", change.lineId).put("at", change.at)
            is StructureChange.Ruby -> JSONObject().put("op", "ruby").put("lineId", change.lineId).put("at", change.at)
                .apply { if (change.base != null) put("base", change.base) }
            is StructureChange.Unruby -> JSONObject().put("op", "unruby").put("lineId", change.lineId).put("at", change.at)
            is StructureChange.RubyBase -> JSONObject().put("op", "rubyBase").put("lineId", change.lineId)
                .put("at", change.at).put("base", change.base)
        }
        check(client.request("POST", "/songs/${seg(songId)}/lyric-structure", body), "行の区切りを変えられませんでした")
    }

    /** 歌詞の報告 (POST /songs/:id/lyrics-report)。運営の GitHub の issue になる。本文は送らない。 */
    suspend fun report(songId: String, reason: String, note: String = "") = withContext(Dispatchers.IO) {
        val body = JSONObject().put("reason", reason).put("note", note)
        check(client.request("POST", "/songs/${seg(songId)}/lyrics-report", body), "報告を送れませんでした")
    }

    /** モデレーター: 公開 ⇄ 非公開 (POST /admin/lyrics/status)。本文は消さない。 */
    suspend fun setPublished(songId: String, isPublished: Boolean) = withContext(Dispatchers.IO) {
        val body = JSONObject()
            .put("song_ids", JSONArray(listOf(songId)))
            .put("status", if (isPublished) "published" else "draft")
        check(client.request("POST", "/admin/lyrics/status", body), "公開状態を変えられませんでした")
    }

    /** モデレーター: 投稿で上書きされる前の版に 1 つ戻す (POST /admin/lyrics/:id/restore)。 */
    suspend fun restorePrevious(songId: String) = withContext(Dispatchers.IO) {
        check(client.request("POST", "/admin/lyrics/${seg(songId)}/restore"), "前の版に戻せませんでした")
    }

    private fun check(res: com.fugaif.imaslivedb.data.net.WorkerResponse, message: String) {
        if (res.code !in 200..299) throw IOException("$message (${res.code})")
    }

    private fun seg(s: String) = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
}

/** [LyricsApi.saveParts] に渡す行 1 つ。[breaks] が null ならその行の区切りは送らない (今の区切りを残す)。 */
data class PartsLine(val id: String, val singers: List<String>, val breaks: List<LyricLinePartBreak>? = null)

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
    /** `at` は開く括弧 (（／(／《) のスカラー位置。文字数は変わらず、振り仮名にする/やめる。
     * `base` を渡すと親字の頭をそこにする (当て字・漢字のまとまりの一部)。無ければ直前の漢字のまとまり。 */
    data class Ruby(val lineId: String, val at: Int, val base: Int? = null) : StructureChange
    data class Unruby(val lineId: String, val at: Int) : StructureChange
    /** 振り仮名 (「《」が `at`) の親字の頭を `base` に決め直す。 */
    data class RubyBase(val lineId: String, val at: Int, val base: Int) : StructureChange
}
