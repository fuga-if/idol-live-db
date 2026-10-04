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
import com.fugaif.imaslivedb.data.repository.SongRepository
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
    private val songRepository: SongRepository,
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

    /** 「次はこれ」で足した曲の理由 (songs.id → 「同じ公演で 12 回」など)。iOS `recommendedLabels` と対。 */
    private var recommendedLabels: Map<String, String> = emptyMap()
    /** この再生で流した曲 (同じ曲に戻らないよう「次はこれ」から外す)。iOS `playedSongIds` と対。 */
    private var playedSongIds: List<String> = emptyList()
    private var isAppendingNext = false

    private val _autoplayNext = MutableStateFlow(prefs().getBoolean(KEY_AUTOPLAY, true))
    override val autoplayNext: StateFlow<Boolean> = _autoplayNext.asStateFlow()
    override fun setAutoplayNext(value: Boolean) {
        _autoplayNext.value = value
        prefs().edit().putBoolean(KEY_AUTOPLAY, value).apply()
        if (value) appendNextIfNeeded()
    }

    private val _upNext = MutableStateFlow<Pair<String, String?>?>(null)
    override val upNext: StateFlow<Pair<String, String?>?> = _upNext.asStateFlow()

    private fun refreshQueueFlags() {
        val index = queueIndex
        _hasQueue.value = queueSongIds.size > 1
        _canSkipNext.value = index != null &&
            playQueueNextIndex(index.toUInt(), queueSongIds.size.toUInt()) != null
        _upNext.value = if (index != null && index + 1 < queueSongIds.size) {
            val id = queueSongIds[index + 1]
            id to recommendedLabels[id]
        } else {
            null
        }
    }

    /**
     * SDK から「今の曲が替わった」と届いたとき (曲送り・SDK 側の操作・「次はこれ」で足した曲への
     * 自然な進行のいずれでも通る)。流した曲を記録し、積んだ最後の曲に来ていれば次を足す。
     */
    private fun onQueueItemChanged(catalogId: String?) {
        val songId = catalogId?.let { queueSongIdByCatalogId[it] } ?: return
        if (songId == _loadedSongId.value) return
        _loadedSongId.value = songId
        queueIndex = queueSongIds.indexOf(songId).takeIf { it >= 0 }
        playedSongIds = playedSongIds + songId
        refreshQueueFlags()
        appendNextIfNeeded()
    }

    /**
     * 今の曲が積んだ最後の曲なら、「次はこれ」を 1 曲足す (選び方はコア)。単曲再生も
     * 要素数 1 のキューとして積んであるので同じ経路で効く。足すのは最後の曲に来たときだけ
     * なので、積んでいくのは常に 1 曲先まで。iOS `MusicKitService.appendNextIfNeeded` と対。
     */
    private fun appendNextIfNeeded() {
        val bridge = bridge ?: return
        val current = _loadedSongId.value
        val index = queueIndex
        if (!_autoplayNext.value || isAppendingNext || current == null ||
            index == null || index != queueSongIds.lastIndex
        ) {
            return
        }
        isAppendingNext = true
        val exclude = (playedSongIds + queueSongIds).takeLast(300)
        scope.launch {
            try {
                val picks = runCatching { songRepository.fetchNextSongPicks(current, exclude, limit = 5) }
                    .getOrElse { emptyList() }
                for (pick in picks) {
                    val appleMusicId = pick.song.appleMusicId
                    if (appleMusicId.isNullOrEmpty()) continue
                    // 待っている間に止めた・別の曲を鳴らし直したなら足さない。
                    if (_loadedSongId.value != current || queueSongIds.lastOrNull() != current) return@launch
                    if (!bridge.appendToQueue(appleMusicId)) {
                        Log.w(TAG, "autoplay_insert_failed")
                        return@launch
                    }
                    queueSongIds = queueSongIds + pick.song.id
                    queueSongIdByCatalogId = queueSongIdByCatalogId + (appleMusicId to pick.song.id)
                    recommendedLabels = recommendedLabels + (pick.song.id to pick.label)
                    refreshQueueFlags()
                    return@launch
                }
            } finally {
                isAppendingNext = false
            }
        }
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
        // 要素数 1 のキューとして積む (「次はこれ」で後から 1 曲足せるように)。
        // hasQueue は size > 1 判定なので、足すまでは曲送りのボタンは出ない。
        queueSongIds = listOf(songId)
        queueSongIdByCatalogId = mapOf(appleMusicId to songId)
        queueIndex = 0
        recommendedLabels = emptyMap()
        playedSongIds = listOf(songId)
        refreshQueueFlags()
        bridge.loadQueue(
            activity, devToken, userToken, listOf(appleMusicId), 0,
            onPlayingChanged = { _isPlaying.value = it },
            onCurrentItemChanged = { catalogId -> onQueueItemChanged(catalogId) },
            onFailed = { message ->
                Log.w(TAG, message)
                _isPlaying.value = false
                _loadedSongId.value = null
            }
        )
        _loadedSongId.value = songId
        appendNextIfNeeded()
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
        recommendedLabels = emptyMap()
        playedSongIds = listOf(playable[start].first)
        refreshQueueFlags()
        bridge.loadQueue(
            activity, devToken, userToken, playable.map { it.second }, start,
            onPlayingChanged = { _isPlaying.value = it },
            onCurrentItemChanged = { catalogId -> onQueueItemChanged(catalogId) },
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
        recommendedLabels = emptyMap()
        playedSongIds = emptyList()
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
        /** 端末の設定。iOS `MusicKitService.autoplayKey` と同じキー名。 */
        const val KEY_AUTOPLAY = "music.autoplay_next"
    }
}
