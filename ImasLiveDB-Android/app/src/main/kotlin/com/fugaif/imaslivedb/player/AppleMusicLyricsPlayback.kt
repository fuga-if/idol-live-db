package com.fugaif.imaslivedb.player

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.browser.customtabs.CustomTabsIntent
import com.fugaif.imaslivedb.data.net.WorkerHttpClient
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.IOException
import java.lang.ref.WeakReference
import uniffi.imas_core.playQueueNextIndex
import uniffi.imas_core.playQueuePreviousIndex

/**
 * Apple Music のフル再生 (MusicKit for Android) による [LyricsPlayback]。
 *
 * 揃えるもの:
 * - デベロッパトークン … Worker の `GET /music-token` が配る短命の JWT (APK に焼き込まない)
 * - ミュージックユーザートークン … アプリ内ブラウザ (Custom Tabs) でサインインして受け取る ([beginSignIn])。
 *   SDK の認証は端末の Apple Music にサインイン済みだと返らない不具合があるため (FB24754184)。
 *   受け取ったものは端末の SharedPreferences に置く (イントロドンと同じ)。
 * - 再生器 … [MusicKitBridge] (SDK の AAR を置いたビルドだけ)
 *
 * 再生器は Activity を要るので、いま前に出ている Activity を覚えておく。
 */
class AppleMusicLyricsPlayback(
    private val app: Application,
    private val client: WorkerHttpClient,
    private val bridge: MusicKitBridge? = MusicKitBridge.createOrNull(),
) : LyricsPlayback {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var resumed: WeakReference<Activity>? = null

    private val _isAvailable = MutableStateFlow(bridge != null)
    override val isAvailable: StateFlow<Boolean> = _isAvailable.asStateFlow()
    private val _loadedSongId = MutableStateFlow<String?>(null)
    override val loadedSongId: StateFlow<String?> = _loadedSongId.asStateFlow()
    private val _isPlaying = MutableStateFlow(false)
    override val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    /** 曲送りで積んだ `songs.id` の並び (積んでいなければ空)。iOS `queueSongIds` と対。 */
    private var queueSongIds: List<String> = emptyList()
    /** カタログ id → songId (曲送りで SDK から戻る id をこちらの songId に逆引きする)。 */
    private var queueSongIdByCatalogId: Map<String, String> = emptyMap()
    /** いま鳴っている曲が [queueSongIds] の何番目か。 */
    private var queueIndex: Int? = null

    private val _hasQueue = MutableStateFlow(false)
    override val hasQueue: StateFlow<Boolean> = _hasQueue.asStateFlow()
    private val _canSkipNext = MutableStateFlow(false)
    override val canSkipNext: StateFlow<Boolean> = _canSkipNext.asStateFlow()

    private fun refreshQueueFlags() {
        val index = queueIndex
        _hasQueue.value = queueSongIds.size > 1
        _canSkipNext.value = index != null &&
            playQueueNextIndex(index.toUInt(), queueSongIds.size.toUInt()) != null
    }

    private val _appleMusicState = MutableStateFlow(
        when {
            bridge == null -> AppleMusicState.UNAVAILABLE
            app.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_USER_TOKEN, null) == null ->
                AppleMusicState.SIGNED_OUT
            else -> AppleMusicState.READY
        }
    )
    override val appleMusicState: StateFlow<AppleMusicState> = _appleMusicState.asStateFlow()

    /** ブラウザでサインインしている最中の合言葉。戻ってきたら取りに行く。 */
    private var pendingCode: String? = null
    /** サインインのために待たせている曲 (songId, appleMusicId)。サインインを終えたら鳴らす。 */
    private var pendingStart: Pair<String, String>? = null
    /** サインインのために待たせていたプレイリスト曲送り。サインインを終えたら鳴らす。 */
    private var pendingQueueStart: Pair<List<Pair<String, String>>, Int>? = null
    private var developerToken: Pair<String, Long>? = null

    init {
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                resumed = WeakReference(activity)
                pendingCode?.let { code -> scope.launch { takeUserToken(code) } }
            }
            override fun onActivityPaused(activity: Activity) = Unit
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }

    override fun positionMs(): Int? =
        if (_loadedSongId.value == null) null else bridge?.positionMs()?.toInt()

    override fun durationMs(): Int? =
        if (_loadedSongId.value == null) null else bridge?.durationMs()?.toInt()

    override suspend fun startFull(songId: String, appleMusicId: String): Boolean {
        val bridge = bridge ?: return false
        if (appleMusicId.isEmpty()) return false
        // 既にこの曲を積んでいれば積み直さない (頭に戻ってしまう)。止まっていれば鳴らすだけ。
        if (_loadedSongId.value == songId) {
            if (!_isPlaying.value) bridge.play()
            return true
        }
        val activity = resumed?.get() ?: return false
        val devToken = developerToken() ?: return false
        val userToken = userToken()
        if (userToken == null) {
            // まだ繋いでいない。鳴らそうとしたその場でサインインの画面を出し、
            // 戻ってきたらこの曲を鳴らし始める (もう一度押させない)。
            pendingStart = songId to appleMusicId
            if (_appleMusicState.value != AppleMusicState.SIGNING_IN) beginSignIn(activity)
            return false
        }
        // 単曲なので曲送りの対象ではない (キュー状態をリセット)。
        queueSongIds = emptyList()
        queueSongIdByCatalogId = emptyMap()
        queueIndex = null
        refreshQueueFlags()
        bridge.load(activity, devToken, userToken, appleMusicId,
            onPlayingChanged = { _isPlaying.value = it },
            onFailed = { message ->
                Log.w(TAG, message)
                _isPlaying.value = false
                _loadedSongId.value = null
            })
        _loadedSongId.value = songId
        return true
    }

    override suspend fun startQueue(entries: List<Pair<String, String>>, startAt: Int): Boolean {
        val bridge = bridge ?: return false
        // Apple Music に無い曲は飛ばす。押した曲がその中に無ければ、その後ろで最初に鳴らせる曲から。
        val playable = entries.filter { it.second.isNotEmpty() }
        if (playable.isEmpty()) return false
        val start = (startAt until entries.size)
            .firstNotNullOfOrNull { i -> playable.indexOfFirst { it.first == entries[i].first }.takeIf { it >= 0 } }
            ?: 0
        val activity = resumed?.get() ?: return false
        val devToken = developerToken() ?: return false
        val userToken = userToken()
        if (userToken == null) {
            pendingQueueStart = playable to start
            if (_appleMusicState.value != AppleMusicState.SIGNING_IN) beginSignIn(activity)
            return false
        }
        queueSongIds = playable.map { it.first }
        queueSongIdByCatalogId = playable.associate { it.second to it.first }
        queueIndex = start
        refreshQueueFlags()
        bridge.loadQueue(
            activity, devToken, userToken, playable.map { it.second }, start,
            onPlayingChanged = { _isPlaying.value = it },
            onCurrentItemChanged = { catalogId ->
                val songId = catalogId?.let { queueSongIdByCatalogId[it] } ?: return@loadQueue
                if (songId != _loadedSongId.value) {
                    _loadedSongId.value = songId
                    queueIndex = queueSongIds.indexOf(songId).takeIf { it >= 0 }
                    refreshQueueFlags()
                }
            },
            onFailed = { message ->
                Log.w(TAG, message)
                _isPlaying.value = false
                _loadedSongId.value = null
            }
        )
        _loadedSongId.value = playable[start].first
        return true
    }

    override fun skipNext() {
        if (!_canSkipNext.value) return
        bridge?.skipToNext()
    }

    override fun skipPrevious() {
        val bridge = bridge ?: return
        val index = queueIndex ?: return
        val target = playQueuePreviousIndex(index.toUInt(), (positionMs() ?: 0).toLong())
        if (target.toInt() == index) {
            bridge.seek(0)
        } else {
            bridge.skipToPrevious()
        }
    }

    override fun signIn() {
        val activity = resumed?.get() ?: return
        scope.launch { beginSignIn(activity) }
    }

    override fun seek(ms: Int) { bridge?.seek(ms.toLong()) }

    override fun togglePlay() {
        val bridge = bridge ?: return
        if (_isPlaying.value) bridge.pause() else bridge.play()
    }

    override fun stop() {
        bridge?.pause()
        _loadedSongId.value = null
        _isPlaying.value = false
        queueSongIds = emptyList()
        queueSongIdByCatalogId = emptyMap()
        queueIndex = null
        refreshQueueFlags()
    }

    // ---- トークン ----

    /** 配られたデベロッパトークン。残り 5 分を切ったら取り直す。取れなければ null。 */
    private suspend fun developerToken(): String? {
        val now = System.currentTimeMillis()
        developerToken?.let { (token, expiresAt) -> if (expiresAt - 5 * 60_000 > now) return token }
        return withContext(Dispatchers.IO) {
            try {
                val res = client.request("GET", "/music-token", authorized = false)
                if (res.code != 200) return@withContext null
                val o = JSONObject(res.body ?: "{}")
                val token = o.optString("token").takeIf { it.isNotEmpty() } ?: return@withContext null
                developerToken = token to now + o.optLong("expiresIn", 0) * 1000
                token
            } catch (e: IOException) {
                null
            }
        }
    }

    private fun prefs() = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private fun userToken(): String? = prefs().getString(KEY_USER_TOKEN, null)

    /** ブラウザでサインインを始める。合言葉をもらって、サインインの面を開く。 */
    private suspend fun beginSignIn(activity: Activity) {
        val code = withContext(Dispatchers.IO) {
            try {
                val res = client.request("POST", "/music-auth/start", authorized = false)
                if (res.code == 200) JSONObject(res.body ?: "{}").optString("code").takeIf { it.isNotEmpty() } else null
            } catch (e: IOException) {
                null
            }
        } ?: run {
            _appleMusicState.value = AppleMusicState.SIGNED_OUT
            return
        }
        pendingCode = code
        _appleMusicState.value = AppleMusicState.SIGNING_IN
        // アプリ内ブラウザ (Custom Tabs) で開く。MusicKit for Android の認証は端末の Apple Music の
        // 状態に引きずられて返らないので、ブラウザ側 (MusicKit JS) で通す。埋め込み WebView は
        // Apple が弾くので使わない。サインインの面なので、出先 (タイトル) を見せる。
        val url = "${WorkerHttpClient.BASE_URL}/music-auth?code=$code"
        runCatching {
            CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, Uri.parse(url))
        }.onFailure {
            Log.w(TAG, "アプリ内ブラウザを開けない: ${it.message}")
            runCatching { activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        }
    }

    /** 戻ってきたときに、預けられたユーザートークンを取りに行く (入力中なら少し待つ)。 */
    private suspend fun takeUserToken(code: String) {
        repeat(6) {
            val result = withContext(Dispatchers.IO) {
                try {
                    val res = client.request("GET", "/music-auth/take?code=$code", authorized = false)
                    res.code to (res.body ?: "{}")
                } catch (e: IOException) {
                    null
                }
            } ?: return
            val (status, body) = result
            if (status == 404 || status == 410) {
                pendingCode = null
                _appleMusicState.value = AppleMusicState.SIGNED_OUT
                return
            }
            val o = JSONObject(body)
            if (o.optBoolean("ready")) {
                val token = o.optString("token").takeIf { it.isNotEmpty() }
                pendingCode = null
                if (token == null) {
                    _appleMusicState.value = AppleMusicState.SIGNED_OUT
                    return
                }
                prefs().edit().putString(KEY_USER_TOKEN, token).apply()
                _appleMusicState.value = AppleMusicState.READY
                // サインインのために待たせていた曲を鳴らし始める。
                pendingStart?.let { (songId, appleMusicId) ->
                    pendingStart = null
                    startFull(songId, appleMusicId)
                }
                pendingQueueStart?.let { (entries, startAt) ->
                    pendingQueueStart = null
                    startQueue(entries, startAt)
                }
                return
            }
            delay(1_000)
        }
        // ブラウザでまだ終えていない (戻ってきただけ)。もう一度開けるようにしておく。
        _appleMusicState.value = AppleMusicState.SIGNED_OUT
    }

    private companion object {
        const val TAG = "AppleMusicPlayback"
        const val PREFS = "apple_music"
        const val KEY_USER_TOKEN = "musicUserToken"
    }
}
