package com.fugaif.imaslivedb.data.community

import android.util.Log
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.URLEncoder

/**
 * みんなのプレイリスト (ユーザー投稿) の Worker D1 クライアント。iOS `CommunityPlaylistAPI` の移植。
 *
 * タイトル・ひとこと・曲 id の並びだけを持ち、作者名は返さない。一覧と 1 つ取りは未ログインでも読める
 * (公開キャッシュ・数分遅れて見える)。公開・差し替え・取り下げはログインが要る。
 */
class CommunityPlaylistApi(private val http: WorkerHttpClient) {

    data class CommunityPlaylist(
        val id: String,
        val title: String,
        val description: String?,
        /** 一覧では先頭の数曲だけ (ジャケを並べる分)。1 つ取りでは全曲。 */
        val songIds: List<String>,
        val songCount: Int,
        val createdAt: String,
        val updatedAt: String,
        /** 自分が公開したものか (`/me/playlists` で取ったときだけ付く)。 */
        val isOwn: Boolean? = null
    )

    /** 続きの位置。最後のページなら null。 */
    data class Page(val playlists: List<CommunityPlaylist>, val next: String?)

    /** 公開する・差し替えるときの中身。 */
    data class Input(val title: String, val description: String?, val songIds: List<String>)

    sealed class SaveResult {
        data class Success(val playlist: CommunityPlaylist) : SaveResult()
        data class Error(val message: String?) : SaveResult()
    }

    /** GET /playlists — 新しく更新された順 (公開キャッシュ)。通信失敗は null。 */
    suspend fun page(before: String? = null): Page? = withContext(Dispatchers.IO) {
        val path = if (before != null) "/playlists?before=${enc(before)}" else "/playlists"
        get(path, authorized = false)?.let(::parsePage)
    }

    /** GET /playlists/{id} — 1 つ (全曲・公開キャッシュ)。通信失敗・取り下げ済みは null。 */
    suspend fun playlist(id: String): CommunityPlaylist? = withContext(Dispatchers.IO) {
        get("/playlists/${enc(id)}", authorized = false)?.let(::parsePlaylist)
    }

    /** GET /me/playlists — 自分が公開したもの (要ログイン)。通信失敗は null。 */
    suspend fun mine(): List<CommunityPlaylist>? = withContext(Dispatchers.IO) {
        get("/me/playlists", authorized = true)?.let(::parsePage)?.playlists
    }

    /** POST /playlists — 公開する (要ログイン・playlist 枠)。 */
    suspend fun publish(input: Input): SaveResult = withContext(Dispatchers.IO) {
        save("POST", "/playlists", input)
    }

    /** PUT /playlists/{id} — 中身を差し替える (作者だけ・playlist 枠)。 */
    suspend fun update(id: String, input: Input): SaveResult = withContext(Dispatchers.IO) {
        save("PUT", "/playlists/${enc(id)}", input)
    }

    /** DELETE /playlists/{id} — 取り下げる (作者かモデレーター)。 */
    suspend fun remove(id: String): Boolean = withContext(Dispatchers.IO) {
        try {
            http.request("DELETE", "/playlists/${enc(id)}").isSuccess
        } catch (e: Exception) {
            Log.w(TAG, "DELETE /playlists/$id failed: ${e.message}")
            false
        }
    }

    private fun save(method: String, path: String, input: Input): SaveResult {
        val body = JSONObject()
            .put("title", input.title)
            .put("description", input.description ?: JSONObject.NULL)
            .put("songIds", JSONArray(input.songIds))
        return try {
            val response = http.request(method, path, body)
            when {
                response.isSuccess && !response.body.isNullOrEmpty() -> SaveResult.Success(parsePlaylist(JSONObject(response.body)))
                response.code == 401 -> SaveResult.Error("ログインが必要です。")
                response.code == 403 -> SaveResult.Error("この操作は制限されています。")
                response.code == 429 -> SaveResult.Error("今日の上限に達しました。しばらくしてからお試しください。")
                else -> SaveResult.Error(null)
            }
        } catch (e: Exception) {
            Log.w(TAG, "$method $path failed: ${e.message}")
            SaveResult.Error("通信できませんでした。")
        }
    }

    private fun parsePage(json: JSONObject): Page {
        val arr = json.optJSONArray("playlists") ?: JSONArray()
        val playlists = (0 until arr.length()).map { parsePlaylist(arr.getJSONObject(it)) }
        val next = if (json.isNull("next")) null else json.optString("next").ifEmpty { null }
        return Page(playlists, next)
    }

    private fun parsePlaylist(o: JSONObject): CommunityPlaylist {
        val idsArr = o.optJSONArray("songIds") ?: JSONArray()
        return CommunityPlaylist(
            id = o.optString("id"),
            title = o.optString("title"),
            description = if (o.isNull("description")) null else o.optString("description").ifEmpty { null },
            songIds = (0 until idsArr.length()).map { idsArr.getString(it) },
            songCount = o.optInt("songCount"),
            createdAt = o.optString("createdAt"),
            updatedAt = o.optString("updatedAt"),
            isOwn = if (o.has("isOwn") && !o.isNull("isOwn")) o.optBoolean("isOwn") else null
        )
    }

    private fun get(path: String, authorized: Boolean): JSONObject? = try {
        val response = http.request("GET", path, authorized = authorized)
        if (response.isSuccess && !response.body.isNullOrEmpty()) JSONObject(response.body) else null
    } catch (e: Exception) {
        Log.w(TAG, "GET $path failed: ${e.message}")
        null
    }

    private fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")

    companion object {
        private const val TAG = "CommunityPlaylistApi"
    }
}
