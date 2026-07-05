package com.fugaif.imaslivedb.data.community

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.data.auth.AuthService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** 集計系コミュニティ (タグ / ペンライト投票 / お題) の Worker D1 クライアント。iOS CommunityAPI の移植。
 *  authService がサインイン済みなら Authorization: Bearer を全リクエストに付与する
 *  (投票系エンドポイントはサーバ側で認証必須。タグ/ペンライト等は未指定でも動く匿名 read/write)。 */
class CommunityApi(private val appContext: Context, private val authService: AuthService) {

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
        /** 自分がこのお題に入れた合計票数 (1人3票まで)。 */
        val myVoteCount: Int = 0,
        /** サーバのお題ステータス ("active"/"ended"/"removed" 等)。 */
        val status: String = "active",
        /** 締切日時 (epoch millis)。未知/パース不可なら Long.MAX_VALUE (常に「開催中」扱い)。 */
        val endsAtMs: Long = Long.MAX_VALUE,
    ) {
        /** iOS Poll.isActive の移植: サーバが active かつ締切前。 */
        val isActive: Boolean get() = status == "active" && endsAtMs > System.currentTimeMillis()

        /** iOS Poll.statusLabel の移植。 */
        val statusLabel: String get() {
            if (!isActive) return "終了"
            val days = ((endsAtMs - System.currentTimeMillis()) / 86_400_000L)
            return if (days <= 0) "本日締切" else "残り${days}日"
        }
    }
    /** 投票/取消のレスポンス (対象 entity の確定票数 + 自分の合計投票数)。 */
    data class PollVoteResult(val entityId: String, val voteCount: Int, val myVoteCount: Int)
    data class PenlightSet(val key: String, val colors: List<String>, val count: Int)
    data class PenlightResult(val topSets: List<PenlightSet>, val totalVotes: Int)

    data class CommunityTag(
        val id: String,
        val name: String,
        val description: String?,
        val category: String?,
        val color: String?,
        val createdAt: Long,
        val totalUses: Int
    )
    data class TagSongEntry(val songId: String, val voteCount: Int)
    data class TagDetail(val tag: CommunityTag, val songs: List<TagSongEntry>)
    data class TagHistoryEntry(
        val descriptionAfter: String?,
        val descriptionBefore: String?,
        val editedBy: String,
        val editedAt: Long
    )
    sealed class TagCreateResult {
        data class Success(val tag: CommunityTag, val alreadyExisted: Boolean) : TagCreateResult()
        object RateLimited : TagCreateResult()
        data class Error(val message: String?) : TagCreateResult()
    }

    /** GET /songs/{id}/tags — タグ一覧 (件数 + 自分が付けたか)。 */
    suspend fun songTags(songId: String): List<SongTag> = withContext(Dispatchers.IO) {
        val json = get("/songs/${enc(songId)}/tags") ?: return@withContext emptyList()
        val mine = json.optJSONArray("my_tag_ids")?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()
        val tags = json.optJSONArray("tags") ?: JSONArray()
        (0 until tags.length()).map { i ->
            val t = tags.getJSONObject(i)
            SongTag(t.getString("id"), t.optString("name"), t.strOrNull("color"),
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

    /** POST /songs/{id}/tags — 複数タグをまとめて曲に適用 (タグ追加ピッカーの「追加」)。 */
    suspend fun applySongTags(songId: String, tagIds: List<String>): List<String> = withContext(Dispatchers.IO) {
        if (tagIds.isEmpty()) return@withContext emptyList()
        val json = sendJson("POST", "/songs/${enc(songId)}/tags", JSONObject().put("tag_ids", JSONArray(tagIds)))
            ?: return@withContext emptyList()
        val arr = json.optJSONArray("applied_tag_ids") ?: JSONArray()
        (0 until arr.length()).map { arr.getString(it) }
    }

    /** GET /tags — 全タグ検索/一覧 (人気・新着・名前順)。 */
    suspend fun tags(search: String = "", category: String = "", sort: String = "popular", limit: Int = 1000): List<CommunityTag> =
        withContext(Dispatchers.IO) {
            val query = buildString {
                append("?sort=").append(enc(sort)).append("&limit=").append(limit)
                if (search.isNotEmpty()) append("&search=").append(enc(search))
                if (category.isNotEmpty()) append("&category=").append(enc(category))
            }
            val json = get("/tags$query") ?: return@withContext emptyList()
            val arr = json.optJSONArray("tags") ?: JSONArray()
            (0 until arr.length()).map { parseTagListItem(arr.getJSONObject(it)) }
        }

    /** POST /tags — 新規タグ作成。同名タグが既存なら 409 で既存タグが返るので、それを採用して冪等にする。 */
    suspend fun createTag(name: String, description: String? = null, category: String? = null, color: String? = null): TagCreateResult =
        withContext(Dispatchers.IO) {
            val body = JSONObject().put("name", name)
            description?.let { body.put("description", it) }
            category?.let { body.put("category", it) }
            color?.let { body.put("color", it) }
            val (code, json) = sendJsonWithStatus("POST", "/tags", body, allowedExtra = setOf(409))
            when {
                code == 429 -> TagCreateResult.RateLimited
                json?.optJSONObject("tag") != null ->
                    TagCreateResult.Success(parseTagFull(json.getJSONObject("tag")), alreadyExisted = code == 409)
                else -> TagCreateResult.Error(null)
            }
        }

    /** GET /tags/{id} — タグ詳細 + 付いた曲一覧 (票数降順)。 */
    suspend fun tagDetail(id: String): TagDetail? = withContext(Dispatchers.IO) {
        val json = get("/tags/${enc(id)}") ?: return@withContext null
        val tagObj = json.optJSONObject("tag") ?: return@withContext null
        val songsArr = json.optJSONArray("songs") ?: JSONArray()
        val songs = (0 until songsArr.length()).map {
            val s = songsArr.getJSONObject(it)
            TagSongEntry(s.optString("song_id"), s.optInt("vote_count"))
        }
        TagDetail(parseTagFull(tagObj), songs)
    }

    /** PUT /tags/{id} — 説明文・カテゴリ・色を更新。 */
    suspend fun updateTag(id: String, description: String? = null, category: String? = null, color: String? = null): CommunityTag? =
        withContext(Dispatchers.IO) {
            val body = JSONObject()
            description?.let { body.put("description", it) }
            category?.let { body.put("category", it) }
            color?.let { body.put("color", it) }
            val json = sendJson("PUT", "/tags/${enc(id)}", body) ?: return@withContext null
            json.optJSONObject("tag")?.let { parseTagFull(it) }
        }

    /** GET /tags/{id}/history — 説明文の編集履歴。 */
    suspend fun tagHistory(id: String): List<TagHistoryEntry> = withContext(Dispatchers.IO) {
        val arr = getArray("/tags/${enc(id)}/history") ?: return@withContext emptyList()
        (0 until arr.length()).map {
            val o = arr.getJSONObject(it)
            TagHistoryEntry(
                descriptionAfter = o.strOrNull("description_after"),
                descriptionBefore = o.strOrNull("description_before"),
                editedBy = o.optString("edited_by"),
                editedAt = o.optLong("edited_at")
            )
        }
    }

    /** POST /tags/{id}/report — 不適切なタグを通報。 */
    suspend fun reportTag(id: String, reason: String? = null): Boolean = withContext(Dispatchers.IO) {
        val body = JSONObject()
        reason?.let { body.put("reason", it) }
        send("POST", "/tags/${enc(id)}/report", body)
    }

    private fun parseTagListItem(o: JSONObject): CommunityTag = CommunityTag(
        id = o.optString("id"),
        name = o.optString("name"),
        description = o.strOrNull("description_preview"),
        category = o.strOrNull("category"),
        color = o.strOrNull("color"),
        createdAt = o.optLong("created_at"),
        totalUses = o.optInt("total_uses")
    )

    private fun parseTagFull(o: JSONObject): CommunityTag = CommunityTag(
        id = o.optString("id"),
        name = o.optString("name"),
        description = o.strOrNull("description"),
        category = o.strOrNull("category"),
        color = o.strOrNull("color"),
        createdAt = o.optLong("created_at"),
        totalUses = o.optInt("total_uses")
    )

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
            candidateScope = PollCandidateScope.fromRaw(poll.strOrNull("candidate_scope")),
            scopeBrandIds = poll.optJSONArray("scope_brand_ids")?.toStringList().orEmpty(),
            scopeEntityIds = poll.optJSONArray("scope_entity_ids")?.toStringList().orEmpty(),
            myVoteCount = poll.optInt("my_vote_count"),
            status = poll.strOrNull("status") ?: "active",
            endsAtMs = parseEndsAt(poll.optString("ends_at")),
        )
    }

    private fun JSONArray.toStringList(): List<String> =
        (0 until length()).map { optString(it) }.filter { it.isNotEmpty() }

    /** SQLite datetime ("YYYY-MM-DD HH:MM:SS", UTC想定) をエポックミリ秒へ。サーバ (Worker) 側の
     *  `new Date(ends_at.replace(" ", "T") + "Z")` と同じ解釈にする。 */
    private fun parseEndsAt(raw: String): Long {
        if (raw.isEmpty()) return Long.MAX_VALUE
        return try {
            val iso = raw.replace(" ", "T")
            val withZone = if (iso.endsWith("Z") || Regex("[+-]\\d{2}:?\\d{2}$").containsMatchIn(iso)) iso else "${iso}Z"
            java.time.Instant.parse(withZone).toEpochMilli()
        } catch (e: Exception) {
            Long.MAX_VALUE
        }
    }

    /** POST /polls/{id}/votes — entity に投票 (新規候補も可。サーバが未存在なら作る)。 */
    suspend fun votePoll(pollId: String, entityId: String): PollVoteResult? = withContext(Dispatchers.IO) {
        val json = sendJson("POST", "/polls/${enc(pollId)}/votes", JSONObject().put("entity_id", entityId))
            ?: return@withContext null
        PollVoteResult(
            entityId = json.strOrNull("entity_id") ?: entityId,
            voteCount = json.optInt("vote_count"),
            myVoteCount = json.optInt("my_vote_count"),
        )
    }

    /** DELETE /polls/{id}/votes/{entityId} — 自分の票を取り消す。 */
    suspend fun unvotePoll(pollId: String, entityId: String): PollVoteResult? = withContext(Dispatchers.IO) {
        val json = sendJson("DELETE", "/polls/${enc(pollId)}/votes/${enc(entityId)}", null)
            ?: return@withContext null
        PollVoteResult(
            entityId = json.strOrNull("entity_id") ?: entityId,
            voteCount = json.optInt("vote_count"),
            myVoteCount = json.optInt("my_vote_count"),
        )
    }

    // --- HTTP ---

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    /** JSON null と欠損キーを確実に null にする (JSONObject.optString は JSON null を文字列 "null" として返すため .ifEmpty{} では捕捉できない)。 */
    private fun JSONObject.strOrNull(key: String): String? =
        if (isNull(key)) null else optString(key).ifEmpty { null }

    private fun open(method: String, path: String): HttpURLConnection {
        val conn = (URL(BASE + path).openConnection() as HttpURLConnection).apply {
            requestMethod = method
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("X-Device-Id", DeviceIdentity.get(appContext))
            authService.sessionToken?.let { setRequestProperty("Authorization", "Bearer $it") }
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

    /** send と同じだがレスポンス body を JSON として返す (投票結果の票数反映に使う)。 */
    private fun sendJson(method: String, path: String, body: JSONObject?): JSONObject? {
        return try {
            val conn = open(method, path)
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() }
            conn.disconnect()
            if (code !in 200..299) Log.w(TAG, "$method $path -> HTTP $code body=$text")
            if (code in 200..299 && !text.isNullOrEmpty()) JSONObject(text) else null
        } catch (e: Exception) {
            Log.w(TAG, "$method $path failed: ${e.message}"); null
        }
    }

    /** sendJson と同じだが、HTTP ステータスも一緒に返す (409 = 既存タグ・429 = レート制限などを
     *  呼び出し側で区別するため)。allowedExtra に含まれるステータスも成功扱いで body を読む。 */
    private fun sendJsonWithStatus(
        method: String, path: String, body: JSONObject?, allowedExtra: Set<Int> = emptySet()
    ): Pair<Int, JSONObject?> {
        return try {
            val conn = open(method, path)
            if (body != null) {
                conn.doOutput = true
                conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            }
            val code = conn.responseCode
            val ok = code in 200..299 || code in allowedExtra
            val text = (if (ok) conn.inputStream else conn.errorStream)?.bufferedReader()?.use { it.readText() }
            conn.disconnect()
            if (!ok) Log.w(TAG, "$method $path -> HTTP $code body=$text")
            code to (if (ok && !text.isNullOrEmpty()) JSONObject(text) else null)
        } catch (e: Exception) {
            Log.w(TAG, "$method $path failed: ${e.message}")
            -1 to null
        }
    }

    companion object {
        private const val BASE = "https://imas-live-api.tokata3011.workers.dev"
        private const val TAG = "CommunityApi"
    }
}
