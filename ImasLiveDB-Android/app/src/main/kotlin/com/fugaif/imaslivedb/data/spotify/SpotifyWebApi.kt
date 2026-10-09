package com.fugaif.imaslivedb.data.spotify

import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import uniffi.imas_core.SpotifyFailure
import uniffi.imas_core.spotifyFailureMessage
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

/** うまくいかなかったとき。文言はコア (`spotifyFailureMessage`) が決める。 */
class SpotifyException(val kind: SpotifyFailure) : Exception(spotifyFailureMessage(kind))

/**
 * Spotify の認可と Web API の通信だけ。状態は持たない ([SpotifyService] が持つ)。iOS `SpotifyWebAPI`。
 *
 * 使う口は開発者モード (2026-02 改定後) で残っているものだけ:
 * `/me`・`/search` (limit は 10 まで)・`POST /me/playlists`・`POST /playlists/{id}/items`。
 */
object SpotifyWebApi {
    private const val AUTHORIZE = "https://accounts.spotify.com/authorize"
    private const val TOKEN = "https://accounts.spotify.com/api/token"
    private const val API = "https://api.spotify.com/v1/"
    private const val TIMEOUT_MS = 15_000

    data class Tokens(val accessToken: String, val refreshToken: String, val expiresAtMillis: Long)

    data class Track(val id: String, val name: String, val artists: List<String>, val album: String, val uri: String)

    fun authorizeUrl(clientId: String, redirectUri: String, scopes: String, state: String, codeChallenge: String): Uri =
        Uri.parse(AUTHORIZE).buildUpon()
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("scope", scopes)
            .appendQueryParameter("state", state)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("code_challenge", codeChallenge)
            .build()

    suspend fun exchangeCode(code: String, verifier: String, clientId: String, redirectUri: String): Tokens =
        tokenRequest(
            mapOf(
                "grant_type" to "authorization_code",
                "code" to code,
                "redirect_uri" to redirectUri,
                "client_id" to clientId,
                "code_verifier" to verifier,
            ),
            previousRefreshToken = null,
        )

    suspend fun refresh(refreshToken: String, clientId: String): Tokens =
        tokenRequest(
            mapOf("grant_type" to "refresh_token", "refresh_token" to refreshToken, "client_id" to clientId),
            previousRefreshToken = refreshToken,
        )

    private suspend fun tokenRequest(form: Map<String, String>, previousRefreshToken: String?): Tokens {
        val body = form.entries.joinToString("&") { (k, v) -> "$k=${URLEncoder.encode(v, "UTF-8")}" }
        val (code, text) = send("POST", TOKEN, mapOf("Content-Type" to "application/x-www-form-urlencoded"), body)
        // 400 invalid_grant = 更新用の鍵が失効した (連携の解除・パスワード変更)。
        if (code != 200) throw SpotifyException(if (code == 400) SpotifyFailure.SESSION_EXPIRED else SpotifyFailure.OTHER)
        val json = JSONObject(text ?: "{}")
        // 更新で新しい鍵が返らなければ前の鍵を使い続ける。
        val refresh = json.optString("refresh_token").ifEmpty { null } ?: previousRefreshToken
            ?: throw SpotifyException(SpotifyFailure.OTHER)
        return Tokens(
            accessToken = json.getString("access_token"),
            refreshToken = refresh,
            expiresAtMillis = System.currentTimeMillis() + (json.optLong("expires_in", 3600) - 60) * 1000,
        )
    }

    suspend fun displayName(accessToken: String): String {
        val me = JSONObject(api("GET", "me", accessToken = accessToken))
        return me.optString("display_name").ifEmpty { me.getString("id") }
    }

    suspend fun searchTracks(query: String, accessToken: String): List<Track> {
        val q = "search?type=track&limit=10&market=from_token&q=${URLEncoder.encode(query, "UTF-8").replace("+", "%20")}"
        val items = JSONObject(api("GET", q, accessToken = accessToken)).getJSONObject("tracks").getJSONArray("items")
        return (0 until items.length()).map { i ->
            val item = items.getJSONObject(i)
            val artists = item.getJSONArray("artists")
            Track(
                id = item.getString("id"),
                name = item.getString("name"),
                artists = (0 until artists.length()).map { artists.getJSONObject(it).getString("name") },
                album = item.getJSONObject("album").optString("name"),
                uri = item.getString("uri"),
            )
        }
    }

    /** 非公開のプレイリストを作る。返すのは (id, 開く URL)。 */
    suspend fun createPlaylist(name: String, description: String, accessToken: String): Pair<String, String> {
        val body = JSONObject().put("name", name).put("description", description).put("public", false)
        val created = JSONObject(api("POST", "me/playlists", body.toString(), accessToken))
        return created.getString("id") to created.getJSONObject("external_urls").getString("spotify")
    }

    /** 曲を足す。1 回で 100 曲までなので分けて送る。 */
    suspend fun addItems(playlistId: String, uris: List<String>, accessToken: String) {
        uris.chunked(100).forEach { chunk ->
            api("POST", "playlists/$playlistId/items", JSONObject().put("uris", JSONArray(chunk)).toString(), accessToken)
        }
    }

    fun trackUrl(id: String): String = "https://open.spotify.com/track/$id"

    private suspend fun api(method: String, path: String, json: String? = null, accessToken: String): String {
        val headers = buildMap {
            put("Authorization", "Bearer $accessToken")
            if (json != null) put("Content-Type", "application/json")
        }
        // 429 は Retry-After だけ待って 1 回だけやり直す。
        repeat(2) { attempt ->
            val (code, text, retryAfter) = sendWithRetryAfter(method, API + path, headers, json)
            when {
                code in 200..299 -> return text ?: ""
                code == 401 -> throw SpotifyException(SpotifyFailure.SESSION_EXPIRED)
                code == 403 -> throw SpotifyException(SpotifyFailure.NOT_REGISTERED)
                code == 429 && attempt == 0 -> delay((retryAfter ?: 2L).coerceAtMost(10L) * 1000)
                code == 429 -> throw SpotifyException(SpotifyFailure.RATE_LIMITED)
                else -> throw SpotifyException(SpotifyFailure.OTHER)
            }
        }
        throw SpotifyException(SpotifyFailure.OTHER)
    }

    private suspend fun send(method: String, url: String, headers: Map<String, String>, body: String?): Pair<Int, String?> {
        val (code, text, _) = sendWithRetryAfter(method, url, headers, body)
        return code to text
    }

    private data class Response(val code: Int, val text: String?, val retryAfter: Long?)

    private suspend fun sendWithRetryAfter(method: String, url: String, headers: Map<String, String>, body: String?): Response =
        withContext(Dispatchers.IO) {
            try {
                val conn = (URL(url).openConnection() as HttpURLConnection).apply {
                    requestMethod = method
                    connectTimeout = TIMEOUT_MS
                    readTimeout = TIMEOUT_MS
                    headers.forEach { (k, v) -> setRequestProperty(k, v) }
                }
                try {
                    if (body != null) {
                        conn.doOutput = true
                        conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                    }
                    val code = conn.responseCode
                    // 400 以上は inputStream が投げるので errorStream から読む。
                    val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                        ?.bufferedReader()?.use { it.readText() }
                    Response(code, text, conn.getHeaderField("Retry-After")?.toLongOrNull())
                } finally {
                    conn.disconnect()
                }
            } catch (e: IOException) {
                throw SpotifyException(SpotifyFailure.NETWORK)
            }
        }
}
