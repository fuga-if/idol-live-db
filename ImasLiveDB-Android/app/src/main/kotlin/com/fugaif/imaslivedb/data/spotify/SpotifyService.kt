package com.fugaif.imaslivedb.data.spotify

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Base64
import android.util.Log
import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import uniffi.imas_core.SpotifyFailure
import uniffi.imas_core.SpotifyTrackCandidate
import uniffi.imas_core.spotifyPlaylistDescription
import uniffi.imas_core.spotifySetupGuide
import java.security.MessageDigest
import java.security.SecureRandom

/** 設定とシートが読む状態。 */
data class SpotifyState(
    val clientId: String? = null,
    val accountName: String? = null,
    val isConnected: Boolean = false,
    /**
     * ブラウザから戻って、鍵を受け取っている間。ブラウザを開いている間は立てない
     * (閉じて戻られたことをアプリは知れないので、立てると下ろす機会が無い)。
     */
    val isSigningIn: Boolean = false,
    /** 直前のログインの失敗。出したら [SpotifyService.clearSignInError] で消す。 */
    val signInError: String? = null,
)

/**
 * Spotify 連携の状態 (Client ID・ログイン) と、曲を探す・プレイリストに書き出す操作。iOS `SpotifyService`。
 *
 * Client ID は利用者が自分の Spotify のアプリで発行したもの (理由は imas-core `domain/spotify.rs`)。
 * 鍵は暗号化した prefs、Client ID・表示名・見つけた曲は普通の prefs。端末の外には出さない。
 * どの検索結果を同じ曲と見なすかはコア (`spotifyPickTrack`) が決める。
 *
 * ログインはアプリ内ブラウザで開き、`imaslivedb://spotify-callback` で
 * [SpotifyAuthReturnActivity] に戻る。ブラウザの間にプロセスが落ちてもよいように、
 * 試行の鍵 (verifier・state) は prefs に置いておく。
 */
class SpotifyService(context: Context, private val snapshot: SnapshotStoreProvider) {
    private val appContext = context.applicationContext
    private val prefs: SharedPreferences = appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val secure: SharedPreferences? by lazy {
        runCatching {
            EncryptedSharedPreferences.create(
                appContext,
                SECURE_PREFS,
                MasterKey.Builder(appContext).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build(),
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        }.onFailure { Log.w(TAG, "鍵の保存先を開けない: ${it.message}") }.getOrNull()
    }
    private val guide = spotifySetupGuide()
    private val tokenLock = Mutex()
    private var tokens: SpotifyWebApi.Tokens? = loadTokens()

    private val _state = MutableStateFlow(
        SpotifyState(
            clientId = prefs.getString(KEY_CLIENT_ID, null),
            accountName = prefs.getString(KEY_ACCOUNT_NAME, null),
            isConnected = tokens != null,
        )
    )
    val state: StateFlow<SpotifyState> = _state.asStateFlow()

    // MARK: - ログイン

    /** アプリ内ブラウザで Spotify にログインして許可をもらう。戻りは [completeSignIn]。 */
    fun startSignIn(context: Context, clientId: String) {
        val verifier = randomUrlSafe(64)
        val state = randomUrlSafe(16)
        prefs.edit {
            putString(KEY_PENDING_VERIFIER, verifier)
            putString(KEY_PENDING_STATE, state)
            putString(KEY_PENDING_CLIENT_ID, clientId)
        }
        _state.update { it.copy(signInError = null) }
        val url = SpotifyWebApi.authorizeUrl(clientId, guide.redirectUri, guide.scopes, state, codeChallenge(verifier))
        runCatching {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, url)
        }.onFailure {
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    /** ブラウザから戻ったとき。利用者が断ったなら黙って戻す。 */
    suspend fun completeSignIn(callback: Uri) {
        val verifier = prefs.getString(KEY_PENDING_VERIFIER, null)
        val expectedState = prefs.getString(KEY_PENDING_STATE, null)
        val clientId = prefs.getString(KEY_PENDING_CLIENT_ID, null)
        prefs.edit {
            remove(KEY_PENDING_VERIFIER)
            remove(KEY_PENDING_STATE)
            remove(KEY_PENDING_CLIENT_ID)
        }
        _state.update { it.copy(isSigningIn = true) }
        try {
            // access_denied = 利用者が「同意しない」を押した。
            if (callback.getQueryParameter("error") == "access_denied") return
            val code = callback.getQueryParameter("code")
            if (verifier == null || clientId == null || code == null || callback.getQueryParameter("state") != expectedState) {
                throw SpotifyException(SpotifyFailure.OTHER)
            }
            val fresh = SpotifyWebApi.exchangeCode(code, verifier, clientId, guide.redirectUri)
            // 名前が引けない = このアカウントがアプリに登録されていない (403)。ここで止めて伝える。
            val name = SpotifyWebApi.displayName(fresh.accessToken)
            storeTokens(fresh)
            prefs.edit {
                putString(KEY_CLIENT_ID, clientId)
                putString(KEY_ACCOUNT_NAME, name)
            }
            _state.update { it.copy(clientId = clientId, accountName = name, isConnected = true) }
        } catch (e: SpotifyException) {
            _state.update { it.copy(signInError = e.message) }
        } finally {
            _state.update { it.copy(isSigningIn = false) }
        }
    }

    fun clearSignInError() = _state.update { it.copy(signInError = null) }

    /** 連携をやめる。Client ID は残す (ログインし直すときに貼り直さなくてよい)。 */
    fun signOut() {
        storeTokens(null)
        prefs.edit { remove(KEY_ACCOUNT_NAME) }
        _state.update { it.copy(accountName = null, isConnected = false) }
    }

    /** Client ID も忘れる (別のアプリで作り直すとき)。 */
    fun forgetClientId() {
        signOut()
        prefs.edit { remove(KEY_CLIENT_ID) }
        _state.update { it.copy(clientId = null) }
    }

    // MARK: - 鍵

    private fun loadTokens(): SpotifyWebApi.Tokens? = runCatching {
        val json = JSONObject(secure?.getString(KEY_TOKENS, null) ?: return null)
        SpotifyWebApi.Tokens(json.getString("access"), json.getString("refresh"), json.getLong("expires"))
    }.getOrNull()

    private fun storeTokens(value: SpotifyWebApi.Tokens?) {
        tokens = value
        secure?.edit {
            if (value == null) {
                remove(KEY_TOKENS)
            } else {
                putString(
                    KEY_TOKENS,
                    JSONObject().put("access", value.accessToken).put("refresh", value.refreshToken)
                        .put("expires", value.expiresAtMillis).toString()
                )
            }
        }
    }

    /** 使える鍵。切れていれば更新する。更新もできなければログアウトして投げる。 */
    private suspend fun accessToken(): String = tokenLock.withLock {
        val current = tokens ?: throw SpotifyException(SpotifyFailure.SESSION_EXPIRED)
        val clientId = _state.value.clientId ?: throw SpotifyException(SpotifyFailure.SESSION_EXPIRED)
        if (current.expiresAtMillis > System.currentTimeMillis()) return@withLock current.accessToken
        try {
            SpotifyWebApi.refresh(current.refreshToken, clientId).also { storeTokens(it) }.accessToken
        } catch (e: SpotifyException) {
            if (e.kind == SpotifyFailure.SESSION_EXPIRED) signOut()
            throw e
        }
    }

    // MARK: - 曲

    /** 曲の Spotify のページ。見つからなければ null。 */
    suspend fun trackUrl(songId: String): String? = findTrack(songId)?.let { SpotifyWebApi.trackUrl(it.first) }

    /** (Spotify の曲 id, uri)。 */
    private suspend fun findTrack(songId: String): Pair<String, String>? {
        prefs.getString(KEY_TRACK_PREFIX + songId, null)?.let { return it to "spotify:track:$it" }
        val queries = snapshot.query { it.spotifySearchQueries(songId) }
        for (query in queries) {
            val results = SpotifyWebApi.searchTracks(query, accessToken())
            val candidates = results.map { SpotifyTrackCandidate(it.name, it.artists, it.album) }
            val picked = snapshot.query { it.spotifyPickTrack(songId, candidates) } ?: continue
            val track = results[picked.toInt()]
            prefs.edit { putString(KEY_TRACK_PREFIX + songId, track.id) }
            return track.id to track.uri
        }
        return null
    }

    // MARK: - 書き出し

    data class ExportResult(
        val playlistUrl: String?,
        val added: Int,
        /** Spotify で見つからなかった曲 (並びは元のまま)。 */
        val missingSongIds: List<String>,
    )

    /**
     * 曲を探して、見つかった曲で非公開のプレイリストを作る。1 曲も無ければ作らない。
     * 同じ曲が 2 回あれば 2 回入れる (セトリの再披露・メドレーの順を崩さない)。
     */
    suspend fun exportPlaylist(name: String, songIds: List<String>, progress: (done: Int, total: Int) -> Unit): ExportResult {
        val uris = mutableListOf<String>()
        val missing = mutableListOf<String>()
        val found = mutableMapOf<String, Pair<String, String>?>()
        songIds.forEachIndexed { index, songId ->
            progress(index, songIds.size)
            val track = if (found.containsKey(songId)) found[songId] else findTrack(songId).also { found[songId] = it }
            if (track != null) uris += track.second else missing += songId
        }
        progress(songIds.size, songIds.size)
        if (uris.isEmpty()) return ExportResult(null, 0, missing)
        val token = accessToken()
        val (playlistId, url) = SpotifyWebApi.createPlaylist(name, spotifyPlaylistDescription(), token)
        SpotifyWebApi.addItems(playlistId, uris, token)
        return ExportResult(url, uris.size, missing)
    }

    private companion object {
        const val TAG = "SpotifyService"
        const val PREFS = "spotify"
        const val SECURE_PREFS = "spotify_secure"
        const val KEY_CLIENT_ID = "client_id"
        const val KEY_ACCOUNT_NAME = "account_name"
        const val KEY_TOKENS = "tokens"
        const val KEY_TRACK_PREFIX = "track."
        const val KEY_PENDING_VERIFIER = "pending_verifier"
        const val KEY_PENDING_STATE = "pending_state"
        const val KEY_PENDING_CLIENT_ID = "pending_client_id"

        fun randomUrlSafe(count: Int): String =
            base64Url(ByteArray(count).also { SecureRandom().nextBytes(it) })

        fun codeChallenge(verifier: String): String =
            base64Url(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(Charsets.US_ASCII)))

        fun base64Url(bytes: ByteArray): String =
            Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)
    }
}
