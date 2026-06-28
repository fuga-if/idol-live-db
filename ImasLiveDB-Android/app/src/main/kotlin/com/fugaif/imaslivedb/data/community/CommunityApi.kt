package com.fugaif.imaslivedb.data.community

import android.content.Context
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** 集計系コミュニティ (タグ / ペンライト投票) の Worker D1 クライアント。iOS CommunityAPI の移植。 */
class CommunityApi(private val appContext: Context) {

    data class SongTag(val id: String, val name: String, val color: String?, val voteCount: Int, val mine: Boolean)
    data class PollSummary(val id: String, val title: String, val targetType: String)
    data class PollEntry(val entityId: String, val voteCount: Int, val mine: Boolean)
    /**
     * 投票候補の絞り込みスコープ。
     * - `all`: 既存挙動 (全曲/全アイドルから自由選択)
     * - `brand`: scopeBrandIds に含まれる brand_id のみ
     * - `manual`: scopeEntityIds に列挙された候補のみ
     *
     * サーバの未知値・古いレスポンスでは `all` にフォールバック (前方互換)。
     */
    enum class PollCandidateScope(val raw: String) {
        ALL("all"), BRAND("brand"), MANUAL("manual");
        companion object {
            fun fromRaw(s: String?): PollCandidateScope = when (s) {
                "brand" -> BRAND
                "manual" -> MANUAL
                else -> ALL
            }
        }
    }
    data class PollDetail(
        val id: String,
        val title: String,
        val targetType: String,
        val totalVotes: Int,
        val entries: List<PollEntry>,
        val candidateScope: PollCandidateScope = PollCandidateScope.ALL,
        val scopeBrandIds: List<String> = emptyList(),
        val scopeEntityIds: List<String> = emptyList(),
    )
    data class PenlightSet(val key: String, val colors: List<String>, val count: Int)
    data class PenlightResult(val topSets: List<PenlightSet>, val totalVotes: Int)

    /** GET /songs/{id}/tags — タグ一覧 (件数 + 自分が付けたか)。 */
    suspend fun songTags(songId: String): List<SongTag> = withContext(Dispatchers.IO) {
        val json = get("/songs/${enc(songId)}/tags") ?: return@withContext emptyList()
        val mine = json.optJSONArray("my_tag_ids")?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()
        val tags = json.optJSONArray("tags") ?: JSONArray()
        (0 until tags.length()).map { i ->
            val t = tags.getJSONObject(i)
            SongTag(t.getString("id"), t.optString("name"), t.optString("color").ifEmpty { null },
                t.optInt("vote_count"), mine.contains(t.getString("id")))
        }
    }

    /** POST /songs/{id}/tags — 自分のタグ投票を追加。 */
    suspend fun applyTag(songId: String, tagId: String): Boolean = withContext(Dispatchers.IO) {
        send("POST", "/songs/${enc(songId)}/tags", JSONObject().put("tag_ids", JSONArray().put(tagId)))
    }

    /** DELETE /songs/{id}/tags/{tagId} — 自分のタグ投票を外す。 */
    suspend fun removeTag(songId: String, tagId: String): Boolean = withContext(Dispatchers.IO) {
        send("DELETE", "/songs/${enc(songId)}/tags/${enc(tagId)}", null)
    }

    /** GET /penlight/votes/{id} — ペンライト投票集計。 */
    suspend fun penlightVotes(songId: String): PenlightResult? = withContext(Dispatchers.IO) {
        val json = get("/penlight/votes/${enc(songId)}") ?: return@withContext null
        val sets = json.optJSONArray("top_sets") ?: JSONArray()
        val top = (0 until sets.length()).map { i ->
            val s = sets.getJSONObject(i)
            val colors = s.optJSONArray("colors")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList()
            PenlightSet(s.optString("key"), colors, s.optInt("count"))
        }
        PenlightResult(top, json.optInt("total_votes"))
    }

    /** POST /penlight/vote — 色セットに投票。 */
    suspend fun votePenlight(songId: String, colors: List<String>): Boolean = withContext(Dispatchers.IO) {
        val body = JSONObject().put("song_id", songId).put("colors", JSONArray(colors))
        send("POST", "/penlight/vote", body)
    }

    /** 進行中/最近のポール一覧 (/polls/results は poll ごとに首位 entity を返すので poll_id で集約)。 */
    suspend fun polls(): List<PollSummary> = withContext(Dispatchers.IO) {
        val arr = getArray("/polls/results") ?: return@withContext emptyList()
        val seen = HashSet<String>()
        (0 until arr.length()).mapNotNull { i ->
            val o = arr.getJSONObject(i)
            val id = o.optString("poll_id")
            if (id.isEmpty() || !seen.add(id)) null
            else PollSummary(id, o.optString("title"), o.optString("target_type"))
        }
    }

    /** GET /polls/{id} — ポール詳細 (選択肢 + 票数 + 自分の投票)。 */
    suspend fun pollDetail(id: String): PollDetail? = withContext(Dispatchers.IO) {
        val json = get("/polls/${enc(id)}") ?: return@withContext null
        val poll = json.optJSONObject("poll") ?: return@withContext null
        val entriesArr = json.optJSONArray("entries") ?: JSONArray()
        val entries = (0 until entriesArr.length()).map { i ->
            val e = entriesArr.getJSONObject(i)
            PollEntry(e.optString("entity_id"), e.optInt("vote_count"), e.optBoolean("has_user_voted"))
        }
        PollDetail(
            id = poll.optString("id"),
            title = poll.optString("title"),
            targetType = poll.optString("target_type"),
            totalVotes = poll.optInt("total_votes"),
            entries = entries,
            candidateScope = PollCandidateScope.fromRaw(poll.optString("candidate_scope").ifEmpty { null }),
            scopeBrandIds = poll.optJSONArray("scope_brand_ids")?.toStringList().orEmpty(),
            scopeEntityIds = poll.optJSONArray("scope_entity_ids")?.toStringList().orEmpty(),
        )
    }

    private fun JSONArray.toStringList(): List<String> =
        (0 until length()).map { optString(it) }.filter { it.isNotEmpty() }

    /** POST /polls/{id}/votes — entity に投票。 */
    suspend fun votePoll(pollId: String, entityId: String): Boolean = withContext(Dispatchers.IO) {
        send("POST", "/polls/${enc(pollId)}/votes", JSONObject().put("entity_id", entityId))
    }

    // --- HTTP ---

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    private fun open(method: String, path: String): HttpURLConnection {
        val conn = (URL(BASE + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
        }
        return conn
    }

    private fun get(path: String): JSONObject? {
        return try {
            val conn = open("GET", path)
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() }
            conn.disconnect()
            if (code in 200..299 && !text.isNullOrEmpty()) JSONObject(text) else null
        } catch (e: Exception) {
            Log.w(TAG, "GET $path failed: ${e.message}"); null
        }
    }

    private fun getArray(path: String): JSONArray? {
        return try {
            val conn = open("GET", path)
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() }
            conn.disconnect()
            if (code in 200..299 && !text.isNullOrEmpty()) JSONArray(text) else null
        } catch (e: Exception) {
            Log.w(TAG, "GET[] $path failed: ${e.message}"); null
        }
    }

    private fun send(method: String, path: String, body: JSONObject?): Boolean {
        return try {
            val conn = open(method, path)
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            conn.disconnect()
            code in 200..299
        } catch (e: Exception) {
            Log.w(TAG, "$method $path failed: ${e.message}"); false
        }
    }

    companion object {
        private const val BASE = "https://imas-live-api.tokata3011.workers.dev"
        private const val TAG = "CommunityApi"
    }
}
