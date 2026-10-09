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
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import uniffi.imas_core.FullPlaybackService
import uniffi.imas_core.SpotifyFailure
import uniffi.imas_core.SpotifyTrackCandidate
import uniffi.imas_core.spotifyPlaylistDescription
import uniffi.imas_core.spotifyScopesAllowPlayback
import uniffi.imas_core.spotifySetupGuide
import java.security.MessageDigest
import java.security.SecureRandom

/** 設定とシートが読む状態。 */
data class SpotifyState(
    val clientId: String? = null,
    val accountName: String? = null,
    val isConnected: Boolean = false,
    /** Spotify アプリを操作して鳴らせる許可があるか (プレイリストだけの頃のログインには無い)。 */
    val canControlPlayback: Boolean = false,
    /** フル尺をどちらで鳴らすか (端末の設定)。null は選んでいない (コアの既定に任せる)。 */
    val fullPlaybackPreference: FullPlaybackService? = null,
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
            canControlPlayback = tokens?.scope?.let(::spotifyScopesAllowPlayback) ?: false,
            fullPlaybackPreference = when (prefs.getString(KEY_FULL_PLAYBACK, null)) {
                "spotify" -> FullPlaybackService.SPOTIFY
                "apple_music" -> FullPlaybackService.APPLE_MUSIC
                else -> null
            },
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
        SpotifyWebApi.Tokens(
            json.getString("access"), json.getString("refresh"), json.getLong("expires"),
            json.optString("scope").ifEmpty { null },
        )
    }.getOrNull()

    /** フル尺をどちらで鳴らすかを選ぶ (端末の設定)。 */
    fun setFullPlaybackPreference(value: FullPlaybackService) {
        prefs.edit { putString(KEY_FULL_PLAYBACK, if (value == FullPlaybackService.SPOTIFY) "spotify" else "apple_music") }
        _state.update { it.copy(fullPlaybackPreference = value) }
    }

    private fun storeTokens(value: SpotifyWebApi.Tokens?) {
        tokens = value
        _state.update { it.copy(canControlPlayback = value?.scope?.let(::spotifyScopesAllowPlayback) ?: false) }
        secure?.edit {
            if (value == null) {
                remove(KEY_TOKENS)
            } else {
                putString(
                    KEY_TOKENS,
                    JSONObject().put("access", value.accessToken).put("refresh", value.refreshToken)
                        .put("expires", value.expiresAtMillis).put("scope", value.scope ?: "").toString()
                )
            }
        }
    }

    /** 使える鍵。切れていれば更新する。更新もできなければログアウトして投げる。 */
    suspend fun accessToken(): String = tokenLock.withLock {
        val current = tokens ?: throw SpotifyException(SpotifyFailure.SESSION_EXPIRED)
        val clientId = _state.value.clientId ?: throw SpotifyException(SpotifyFailure.SESSION_EXPIRED)
        if (current.expiresAtMillis > System.currentTimeMillis()) return@withLock current.accessToken
        try {
            SpotifyWebApi.refresh(current.refreshToken, clientId)
                // 更新の応答に権限が無ければ前のを引き継ぐ。
                .let { it.copy(scope = it.scope ?: current.scope) }
                .also { storeTokens(it) }.accessToken
        } catch (e: SpotifyException) {
            if (e.kind == SpotifyFailure.SESSION_EXPIRED) signOut()
            throw e
        }
    }

    // MARK: - 曲

    /** 曲の Spotify のページ。見つからなければ null。 */
    suspend fun trackUrl(songId: String): String? = findTrack(songId)?.let { SpotifyWebApi.trackUrl(it.first) }

    /** 曲の Spotify の URI (`spotify:track:…`)。見つからなければ null。 */
    suspend fun trackUri(songId: String): String? = findTrack(songId)?.second

    /**
     * 曲をまとめて探す (並びは [songIds] と同じ。見つからなければ null)。iOS `trackURIs` と対。
     * 覚えている曲は探さない。探すのは同時に 4 曲まで (一度に投げすぎると 429 になる)。
     */
    suspend fun trackUris(songIds: List<String>): List<String?> = coroutineScope {
        val gate = Semaphore(4)
        songIds.map { songId ->
            async { gate.withPermit { runCatching { trackUri(songId) }.getOrNull() } }
        }.awaitAll()
    }

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
        const val KEY_FULL_PLAYBACK = "full_playback_preference"
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
