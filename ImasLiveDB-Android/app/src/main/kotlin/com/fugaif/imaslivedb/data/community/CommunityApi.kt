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
    data class IdolTag(val id: String, val name: String, val color: String?, val voteCount: Int, val mine: Boolean)
    data class UnitTag(val id: String, val name: String, val color: String?, val voteCount: Int, val mine: Boolean)
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
        val description: String? = null,
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
    /** 指定エンティティ(曲/アイドル)が終了お題で取った順位実績 (上位3位まで)。 */
    data class PollAchievement(
        val pollId: String,
        val title: String,
        val targetType: String,
        val endsAtMs: Long,
        val voteCount: Int,
        val rank: Int
    ) {
        val rankLabel: String get() = if (rank == 1) "優勝" else "第${rank}位"
    }
    data class PenlightSet(val key: String, val colors: List<String>, val count: Int)
    data class PenlightResult(val topSets: List<PenlightSet>, val totalVotes: Int)
    data class PenlightPaletteEntry(val colorHex: String?, val name: String, val sortOrder: Int, val note: String?)
    /** タグが似ている楽曲 (songId, 共有タグ数)。この曲が好きな人向けのおすすめ算出に使う。 */
    data class SimilarSongEntry(val songId: String, val sharedTags: Int)
    /** タグが似ているアイドル (idolId, 共有タグ数)。この人が好きな人向けのおすすめ算出に使う。 */
    data class SimilarIdolEntry(val idolId: String, val sharedTags: Int)
    /** タグが似ているユニット (unitId, 共有タグ数)。このユニットが好きな人向けのおすすめ算出に使う。 */
    data class SimilarUnitEntry(val unitId: String, val sharedTags: Int)

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
    data class TagIdolEntry(val idolId: String, val voteCount: Int)
    data class TagUnitEntry(val unitId: String, val voteCount: Int)
    /** 曲タグ (tags マスタ) の詳細。アイドルタグは idol_tag_master に分離済みなのでここには出ない (→ IdolTagDetail)。 */
    data class TagDetail(val tag: CommunityTag, val songs: List<TagSongEntry>)
    /** アイドルタグ (idol_tag_master) の詳細。曲タグとは別プールなので songs を持たない。 */
    data class IdolTagDetail(val tag: CommunityTag, val idols: List<TagIdolEntry>)
    /** ユニットタグ (unit_tag_master) の詳細。曲/アイドルタグとは別プール。 */
    data class UnitTagDetail(val tag: CommunityTag, val units: List<TagUnitEntry>)
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

    /** GET /idols/{id}/tags — タグ一覧 (件数 + 自分が付けたか)。song 版と対のメソッド。 */
    suspend fun idolTags(idolId: String): List<IdolTag> = withContext(Dispatchers.IO) {
        val json = get("/idols/${enc(idolId)}/tags") ?: return@withContext emptyList()
        val mine = json.optJSONArray("my_tag_ids")?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()
        val tags = json.optJSONArray("tags") ?: JSONArray()
        (0 until tags.length()).map { i ->
            val t = tags.getJSONObject(i)
            IdolTag(t.getString("id"), t.optString("name"), t.strOrNull("color"),
                t.optInt("vote_count"), mine.contains(t.getString("id")))
        }
    }

    /** DELETE /idols/{id}/tags/{tagId} — 自分のタグ投票を外す。 */
    suspend fun removeIdolTag(idolId: String, tagId: String): Boolean = withContext(Dispatchers.IO) {
        send("DELETE", "/idols/${enc(idolId)}/tags/${enc(tagId)}", null)
    }

    /** POST /idols/{id}/tags — 複数タグをまとめてアイドルに適用 (タグ追加ピッカーの「追加」)。 */
    suspend fun applyIdolTags(idolId: String, tagIds: List<String>): List<String> = withContext(Dispatchers.IO) {
        if (tagIds.isEmpty()) return@withContext emptyList()
        val json = sendJson("POST", "/idols/${enc(idolId)}/tags", JSONObject().put("tag_ids", JSONArray(tagIds)))
            ?: return@withContext emptyList()
        val arr = json.optJSONArray("applied_tag_ids") ?: JSONArray()
        (0 until arr.length()).map { arr.getString(it) }
    }

    /** GET /units/{id}/tags — タグ一覧 (件数 + 自分が付けたか)。idol 版と対のメソッド。 */
    suspend fun unitTags(unitId: String): List<UnitTag> = withContext(Dispatchers.IO) {
        val json = get("/units/${enc(unitId)}/tags") ?: return@withContext emptyList()
        val mine = json.optJSONArray("my_tag_ids")?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()
        val tags = json.optJSONArray("tags") ?: JSONArray()
        (0 until tags.length()).map { i ->
            val t = tags.getJSONObject(i)
            UnitTag(t.getString("id"), t.optString("name"), t.strOrNull("color"),
                t.optInt("vote_count"), mine.contains(t.getString("id")))
        }
    }

    /** DELETE /units/{id}/tags/{tagId} — 自分のタグ投票を外す。 */
    suspend fun removeUnitTag(unitId: String, tagId: String): Boolean = withContext(Dispatchers.IO) {
        send("DELETE", "/units/${enc(unitId)}/tags/${enc(tagId)}", null)
    }

    /** POST /units/{id}/tags — 複数タグをまとめてユニットに適用 (タグ追加ピッカーの「追加」)。 */
    suspend fun applyUnitTags(unitId: String, tagIds: List<String>): List<String> = withContext(Dispatchers.IO) {
        if (tagIds.isEmpty()) return@withContext emptyList()
        val json = sendJson("POST", "/units/${enc(unitId)}/tags", JSONObject().put("tag_ids", JSONArray(tagIds)))
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

    // --- アイドルタグカタログ (idol_tag_master — 曲タグ (tags) とは別プール) ---

    /** GET /idol-tags — 全アイドルタグ検索/一覧。tags() の idol_tag_master 版。 */
    suspend fun idolTagCatalog(search: String = "", category: String = "", sort: String = "popular", limit: Int = 1000): List<CommunityTag> =
        withContext(Dispatchers.IO) {
            val query = buildString {
                append("?sort=").append(enc(sort)).append("&limit=").append(limit)
                if (search.isNotEmpty()) append("&search=").append(enc(search))
                if (category.isNotEmpty()) append("&category=").append(enc(category))
            }
            val json = get("/idol-tags$query") ?: return@withContext emptyList()
            val arr = json.optJSONArray("tags") ?: JSONArray()
            (0 until arr.length()).map { parseTagListItem(arr.getJSONObject(it)) }
        }

    /** POST /idol-tags — 新規アイドルタグ作成。createTag() の idol_tag_master 版。 */
    suspend fun createIdolTagOption(name: String, description: String? = null, category: String? = null, color: String? = null): TagCreateResult =
        withContext(Dispatchers.IO) {
            val body = JSONObject().put("name", name)
            description?.let { body.put("description", it) }
            category?.let { body.put("category", it) }
            color?.let { body.put("color", it) }
            val (code, json) = sendJsonWithStatus("POST", "/idol-tags", body, allowedExtra = setOf(409))
            when {
                code == 429 -> TagCreateResult.RateLimited
                json?.optJSONObject("tag") != null ->
                    TagCreateResult.Success(parseTagFull(json.getJSONObject("tag")), alreadyExisted = code == 409)
                else -> TagCreateResult.Error(null)
            }
        }

    /** GET /idol-tags/{id} — アイドルタグ詳細 + 付いたアイドル一覧 (票数降順)。 */
    suspend fun idolTagDetail(id: String): IdolTagDetail? = withContext(Dispatchers.IO) {
        val json = get("/idol-tags/${enc(id)}") ?: return@withContext null
        val tagObj = json.optJSONObject("tag") ?: return@withContext null
        val idolsArr = json.optJSONArray("idols") ?: JSONArray()
        val idols = (0 until idolsArr.length()).map {
            val i = idolsArr.getJSONObject(it)
            TagIdolEntry(i.optString("idol_id"), i.optInt("vote_count"))
        }
        IdolTagDetail(parseTagFull(tagObj), idols)
    }

    /** PUT /idol-tags/{id} — 説明文・カテゴリ・色を更新。 */
    suspend fun updateIdolTagOption(id: String, description: String? = null, category: String? = null, color: String? = null): CommunityTag? =
        withContext(Dispatchers.IO) {
            val body = JSONObject()
            description?.let { body.put("description", it) }
            category?.let { body.put("category", it) }
            color?.let { body.put("color", it) }
            val json = sendJson("PUT", "/idol-tags/${enc(id)}", body) ?: return@withContext null
            json.optJSONObject("tag")?.let { parseTagFull(it) }
        }

    /** GET /idol-tags/{id}/history — 説明文の編集履歴。 */
    suspend fun idolTagOptionHistory(id: String): List<TagHistoryEntry> = withContext(Dispatchers.IO) {
        val arr = getArray("/idol-tags/${enc(id)}/history") ?: return@withContext emptyList()
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

    /** POST /idol-tags/{id}/report — 不適切なアイドルタグを通報。 */
    suspend fun reportIdolTagOption(id: String, reason: String? = null): Boolean = withContext(Dispatchers.IO) {
        val body = JSONObject()
        reason?.let { body.put("reason", it) }
        send("POST", "/idol-tags/${enc(id)}/report", body)
    }

    // --- ユニットタグカタログ (unit_tag_master — 曲/アイドルタグとは別プール) ---

    /** GET /unit-tags — 全ユニットタグ検索/一覧。tags()/idolTagCatalog() の unit_tag_master 版。 */
    suspend fun unitTagCatalog(search: String = "", category: String = "", sort: String = "popular", limit: Int = 1000): List<CommunityTag> =
        withContext(Dispatchers.IO) {
            val query = buildString {
                append("?sort=").append(enc(sort)).append("&limit=").append(limit)
                if (search.isNotEmpty()) append("&search=").append(enc(search))
                if (category.isNotEmpty()) append("&category=").append(enc(category))
            }
            val json = get("/unit-tags$query") ?: return@withContext emptyList()
            val arr = json.optJSONArray("tags") ?: JSONArray()
            (0 until arr.length()).map { parseTagListItem(arr.getJSONObject(it)) }
        }

    /** POST /unit-tags — 新規ユニットタグ作成。createIdolTagOption() の unit_tag_master 版。 */
    suspend fun createUnitTagOption(name: String, description: String? = null, category: String? = null, color: String? = null): TagCreateResult =
        withContext(Dispatchers.IO) {
            val body = JSONObject().put("name", name)
            description?.let { body.put("description", it) }
            category?.let { body.put("category", it) }
            color?.let { body.put("color", it) }
            val (code, json) = sendJsonWithStatus("POST", "/unit-tags", body, allowedExtra = setOf(409))
            when {
                code == 429 -> TagCreateResult.RateLimited
                json?.optJSONObject("tag") != null ->
                    TagCreateResult.Success(parseTagFull(json.getJSONObject("tag")), alreadyExisted = code == 409)
                else -> TagCreateResult.Error(null)
            }
        }

    /** GET /unit-tags/{id} — ユニットタグ詳細 + 付いたユニット一覧 (票数降順)。 */
    suspend fun unitTagDetail(id: String): UnitTagDetail? = withContext(Dispatchers.IO) {
        val json = get("/unit-tags/${enc(id)}") ?: return@withContext null
        val tagObj = json.optJSONObject("tag") ?: return@withContext null
        val unitsArr = json.optJSONArray("units") ?: JSONArray()
        val units = (0 until unitsArr.length()).map {
            val u = unitsArr.getJSONObject(it)
            TagUnitEntry(u.optString("unit_id"), u.optInt("vote_count"))
        }
        UnitTagDetail(parseTagFull(tagObj), units)
    }

    /** PUT /unit-tags/{id} — 説明文・カテゴリ・色を更新。 */
    suspend fun updateUnitTagOption(id: String, description: String? = null, category: String? = null, color: String? = null): CommunityTag? =
        withContext(Dispatchers.IO) {
            val body = JSONObject()
            description?.let { body.put("description", it) }
            category?.let { body.put("category", it) }
            color?.let { body.put("color", it) }
            val json = sendJson("PUT", "/unit-tags/${enc(id)}", body) ?: return@withContext null
            json.optJSONObject("tag")?.let { parseTagFull(it) }
        }

    /** GET /unit-tags/{id}/history — 説明文の編集履歴。 */
    suspend fun unitTagOptionHistory(id: String): List<TagHistoryEntry> = withContext(Dispatchers.IO) {
        val arr = getArray("/unit-tags/${enc(id)}/history") ?: return@withContext emptyList()
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

    /** POST /unit-tags/{id}/report — 不適切なユニットタグを通報。 */
    suspend fun reportUnitTagOption(id: String, reason: String? = null): Boolean = withContext(Dispatchers.IO) {
        val body = JSONObject()
        reason?.let { body.put("reason", it) }
        send("POST", "/unit-tags/${enc(id)}/report", body)
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

    /** GET /penlight/palette — 投票ピッカー用の色候補一覧。 */
    suspend fun penlightPalette(): List<PenlightPaletteEntry> = withContext(Dispatchers.IO) {
        val arr = getArray("/penlight/palette") ?: return@withContext emptyList()
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            PenlightPaletteEntry(o.strOrNull("color_hex"), o.optString("name"), o.optInt("sort_order"), o.strOrNull("note"))
        }.sortedBy { it.sortOrder }
    }

    /** GET /songs/{id}/similar — タグが似ている楽曲 (共有タグ数の降順、ユーザー非依存の集計)。 */
    suspend fun similarSongsByTags(songId: String, limit: Int = 10): List<SimilarSongEntry> = withContext(Dispatchers.IO) {
        val json = get("/songs/${enc(songId)}/similar?limit=$limit") ?: return@withContext emptyList()
        val arr = json.optJSONArray("songs") ?: JSONArray()
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            SimilarSongEntry(o.optString("song_id"), o.optInt("shared_tags"))
        }
    }

    /** GET /idols/{id}/similar — タグが似ているアイドル (共有タグ数の降順、ユーザー非依存の集計)。song 版と対のメソッド。 */
    suspend fun similarIdolsByTags(idolId: String, limit: Int = 10): List<SimilarIdolEntry> = withContext(Dispatchers.IO) {
        val json = get("/idols/${enc(idolId)}/similar?limit=$limit") ?: return@withContext emptyList()
        val arr = json.optJSONArray("idols") ?: JSONArray()
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            SimilarIdolEntry(o.optString("idol_id"), o.optInt("shared_tags"))
        }
    }

    /** GET /units/{id}/similar — タグが似ているユニット (共有タグ数の降順、ユーザー非依存の集計)。idol 版と対のメソッド。 */
    suspend fun similarUnitsByTags(unitId: String, limit: Int = 10): List<SimilarUnitEntry> = withContext(Dispatchers.IO) {
        val json = get("/units/${enc(unitId)}/similar?limit=$limit") ?: return@withContext emptyList()
        val arr = json.optJSONArray("units") ?: JSONArray()
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            SimilarUnitEntry(o.optString("unit_id"), o.optInt("shared_tags"))
        }
    }

    /** タグ付けの盛り上がりの対象領域 (曲タグ / アイドルタグ)。iOS TagActivityDomain の移植。 */
    enum class TagActivityDomain(val raw: String) {
        SONG("song"), IDOL("idol");
        companion object {
            fun fromRaw(s: String?): TagActivityDomain? = entries.firstOrNull { it.raw == s }
        }
    }
    /** 直近のタグ付けイベント1件。曲/アイドル名は entityId を元にクライアント側のローカル DB で解決する。 */
    data class TagActivityEvent(
        val domain: TagActivityDomain,
        val entityId: String,
        val tagId: String,
        val tagName: String,
        val tagColor: String?,
        val tagCategory: String?,
        val createdAtMs: Long
    )
    /** 直近 window_days 日間で伸びているタグ。 */
    data class TagActivityTrend(
        val domain: TagActivityDomain,
        val tagId: String,
        val tagName: String,
        val tagColor: String?,
        val tagCategory: String?,
        val recentCount: Int,
        val totalCount: Int
    )
    /** 直近 window_days 日間で特定の曲/アイドルにタグが急増した組み合わせ。 */
    data class TagActivityRise(
        val domain: TagActivityDomain,
        val entityId: String,
        val tagId: String,
        val tagName: String,
        val tagColor: String?,
        val recentCount: Int
    )
    data class TagActivityResponse(
        val windowDays: Int,
        val recent: List<TagActivityEvent>,
        val trendingTags: List<TagActivityTrend>,
        val risingEntities: List<TagActivityRise>
    )

    /** GET /tags/activity — タグ付けの盛り上がり (直近フィード/トレンドタグ/急上昇コンテンツ)。ユーザー非依存の集計。 */
    suspend fun tagActivity(windowDays: Int = 7): TagActivityResponse? = withContext(Dispatchers.IO) {
        val json = get("/tags/activity?window_days=$windowDays") ?: return@withContext null
        val recentArr = json.optJSONArray("recent") ?: JSONArray()
        val recent = (0 until recentArr.length()).mapNotNull { i ->
            val o = recentArr.getJSONObject(i)
            val domain = TagActivityDomain.fromRaw(o.optString("domain")) ?: return@mapNotNull null
            TagActivityEvent(
                domain = domain,
                entityId = o.optString("entity_id"),
                tagId = o.optString("tag_id"),
                tagName = o.optString("tag_name"),
                tagColor = o.strOrNull("tag_color"),
                tagCategory = o.strOrNull("tag_category"),
                createdAtMs = epochSecToMs(o.optLong("created_at"))
            )
        }
        val trendArr = json.optJSONArray("trending_tags") ?: JSONArray()
        val trendingTags = (0 until trendArr.length()).mapNotNull { i ->
            val o = trendArr.getJSONObject(i)
            val domain = TagActivityDomain.fromRaw(o.optString("domain")) ?: return@mapNotNull null
            TagActivityTrend(
                domain = domain,
                tagId = o.optString("tag_id"),
                tagName = o.optString("tag_name"),
                tagColor = o.strOrNull("tag_color"),
                tagCategory = o.strOrNull("tag_category"),
                recentCount = o.optInt("recent_count"),
                totalCount = o.optInt("total_count")
            )
        }
        val riseArr = json.optJSONArray("rising_entities") ?: JSONArray()
        val risingEntities = (0 until riseArr.length()).mapNotNull { i ->
            val o = riseArr.getJSONObject(i)
            val domain = TagActivityDomain.fromRaw(o.optString("domain")) ?: return@mapNotNull null
            TagActivityRise(
                domain = domain,
                entityId = o.optString("entity_id"),
                tagId = o.optString("tag_id"),
                tagName = o.optString("tag_name"),
                tagColor = o.strOrNull("tag_color"),
                recentCount = o.optInt("recent_count")
            )
        }
        TagActivityResponse(
            windowDays = json.optInt("window_days", windowDays),
            recent = recent,
            trendingTags = trendingTags,
            risingEntities = risingEntities
        )
    }

    data class FavoriteRankingDto(val songId: String, val count: Int)

    /** GET /favorites/ranking — お気に入りの曲別集計 (曲メタは呼び出し側でローカルカタログから解決する)。 */
    suspend fun favoritesRanking(): List<FavoriteRankingDto> = withContext(Dispatchers.IO) {
        val arr = getArray("/favorites/ranking") ?: return@withContext emptyList()
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            FavoriteRankingDto(o.optString("song_id"), o.optInt("count"))
        }
    }

    /** 進行中のポール一覧。 */
    suspend fun polls(): List<PollSummary> = withContext(Dispatchers.IO) {
        val arr = getArray("/polls?status=active") ?: return@withContext emptyList()
        (0 until arr.length()).mapNotNull { i ->
            val o = arr.getJSONObject(i)
            val id = o.optString("id")
            if (id.isEmpty()) null else PollSummary(id, o.optString("title"), o.optString("target_type"))
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
            description = poll.strOrNull("description"),
            targetType = poll.optString("target_type"),
            totalVotes = poll.optInt("total_votes"),
            entries = entries,
            candidateScope = PollCandidateScope.fromRaw(poll.strOrNull("candidate_scope")),
            scopeBrandIds = poll.optJSONArray("scope_brand_ids")?.toStringList().orEmpty(),
            scopeEntityIds = poll.optJSONArray("scope_entity_ids")?.toStringList().orEmpty(),
            myVoteCount = poll.optInt("my_vote_count"),
            status = poll.strOrNull("status") ?: "active",
            endsAtMs = epochSecToMs(poll.optLong("ends_at")),
        )
    }

    /** GET /polls/achievements/{entityId} — 終了お題での順位実績 (上位3位まで)。 */
    suspend fun pollAchievements(entityId: String): List<PollAchievement> = withContext(Dispatchers.IO) {
        val arr = getArray("/polls/achievements/${enc(entityId)}") ?: return@withContext emptyList()
        (0 until arr.length()).map { i ->
            val o = arr.getJSONObject(i)
            PollAchievement(
                pollId = o.optString("poll_id"),
                title = o.optString("title"),
                targetType = o.optString("target_type"),
                endsAtMs = epochSecToMs(o.optLong("ends_at")),
                voteCount = o.optInt("vote_count"),
                rank = o.optInt("rnk"),
            )
        }
    }

    private fun JSONArray.toStringList(): List<String> =
        (0 until length()).map { optString(it) }.filter { it.isNotEmpty() }

    /** サーバは ends_at を epoch 秒の数値で返す (`CAST(strftime('%s', ...) AS INTEGER)`)。0/欠損は Long.MAX_VALUE (常に「開催中」扱い)。 */
    private fun epochSecToMs(sec: Long): Long = if (sec <= 0) Long.MAX_VALUE else sec * 1000L

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
