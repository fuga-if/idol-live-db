package com.fugaif.imaslivedb.player

import android.content.Context
import android.util.Log
import com.spotify.android.appremote.api.ConnectionParams
import com.spotify.android.appremote.api.Connector
import com.spotify.android.appremote.api.PlayerApi
import com.spotify.android.appremote.api.SpotifyAppRemote
import com.spotify.android.appremote.api.error.CouldNotFindSpotifyApp
import com.spotify.protocol.client.Subscription
import com.spotify.protocol.types.PlayerState
import com.fugaif.imaslivedb.data.spotify.SpotifyException
import com.fugaif.imaslivedb.data.spotify.SpotifyService
import com.fugaif.imaslivedb.data.spotify.SpotifyWebApi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import uniffi.imas_core.SpotifyGuidePlatform
import uniffi.imas_core.spotifySetupGuide
import uniffi.imas_core.SpotifyFailure
import uniffi.imas_core.playQueueNextIndex
import uniffi.imas_core.playQueuePreviousIndex
import uniffi.imas_core.spotifyPickDevice
import uniffi.imas_core.spotifyPositionNow

/**
 * 利用者の Spotify アプリと Spotify の SDK (App Remote) で繋いで鳴らす [LyricsPlayback]。iOS `SpotifyRemotePlayer` と
 * `MusicKitService` の Spotify の枝を合わせたもの。音を出すのは Spotify アプリで、このアプリは「この曲を鳴らして」と
 * 頼み、鳴っている曲と位置を Spotify アプリから知らされる。
 *
 * - 繋ぐ: SDK が Spotify アプリを裏で起こして繋ぐ。初回は Spotify アプリが許可の画面を出す
 *   (利用者の Spotify アプリにこのアプリのパッケージ名と指紋が登録されている必要がある。案内はコア)。
 * - 鳴らす: 1 曲は SDK で。並べて鳴らすときは SDK に口が無いので、繋いだ後に Web API の
 *   `PUT /me/player/play` に並べた曲を渡す (鳴らす先はコア `spotifyPickDevice` が選ぶ)。
 * - 位置: SDK が状態の変わり目を知らせる。その間はコア (`spotifyPositionNow`) が経過を足して埋める。
 *   SDK の接続が切れている間は Web API に周期で聞きに行く。
 *
 * 鳴らし始めは Spotify 側の切り替わりが遅れる (頼んでから 1〜2 秒は前の曲が返る)。
 * そこで鳴らし始めごとに番号 ([session]) を振り、頼んだ曲が一度返ってくるまでの状態は写さない。
 * その間の位置の指定 (歌詞の行のタップ) も、頼んだ曲が鳴り始めてから送る。
 *
 * 「次はこれ」は Spotify では足さない。足すには Spotify の「次に再生」に積むしかなく、
 * それは鳴らし直しても消えずに次の再生へ割り込むため。
 */
class SpotifyLyricsPlayback(
    private val context: Context,
    private val spotify: SpotifyService,
) : LyricsPlayback {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // Apple Music の口は振り分け ([RoutedLyricsPlayback]) が持つ。ここでは使わない。
    override val appleMusicState: StateFlow<AppleMusicState> = MutableStateFlow(AppleMusicState.READY)
    override fun signIn() {}

    override val isAvailable: StateFlow<Boolean> = MutableStateFlow(true)
    private val _loadedSongId = MutableStateFlow<String?>(null)
    override val loadedSongId: StateFlow<String?> = _loadedSongId.asStateFlow()
    private val _isPlaying = MutableStateFlow(false)
    override val isPlaying: StateFlow<Boolean> = _isPlaying.asStateFlow()

    /** Spotify で鳴らせなかった理由。画面が出して [clearFailure] で消す。 */
    private val _failure = MutableStateFlow<SpotifyFailure?>(null)
    val failure: StateFlow<SpotifyFailure?> = _failure.asStateFlow()
    fun clearFailure() { _failure.value = null }

    private var queueSongIds: List<String> = emptyList()
    private var queueIndex: Int? = null
    private var songIdByTrackId: Map<String, String> = emptyMap()

    private val _hasQueue = MutableStateFlow(false)
    override val hasQueue: StateFlow<Boolean> = _hasQueue.asStateFlow()
    private val _canSkipNext = MutableStateFlow(false)
    override val canSkipNext: StateFlow<Boolean> = _canSkipNext.asStateFlow()
    private val _upcomingQueue = MutableStateFlow<List<Pair<String, String?>>>(emptyList())
    override val upcomingQueue: StateFlow<List<Pair<String, String?>>> = _upcomingQueue.asStateFlow()

    // 「次はこれ」は足さない (上の説明)。入れ切りの設定は Apple Music の方が持つ。
    override val autoplayNext: StateFlow<Boolean> = MutableStateFlow(false)
    override fun setAutoplayNext(value: Boolean) {}

    /** 最後に聞いた状態と、聞いた時刻。 */
    private data class Snapshot(val trackId: String?, val progressMs: Long, val durationMs: Long?, val isPlaying: Boolean, val fetchedAt: Long)
    private var last: Snapshot? = null
    private var pollJob: Job? = null

    /** 鳴らし始めの番号。古い頼みの結果 (前の再生のぶん) を捨てるのに使う。 */
    private var session = 0
    /** 頼んだ曲が鳴り始めたのを確かめたか。確かめるまでは状態を写さない。 */
    private var isConfirmed = false
    private var startedAt = 0L
    /** 鳴り始める前に頼まれた位置。鳴り始めたら送る。 */
    private var pendingSeekMs: Int? = null

    /** SDK の接続。切れていれば null。 */
    private var appRemote: SpotifyAppRemote? = null
    private var stateSubscription: Subscription<PlayerState>? = null
    private val connected: SpotifyAppRemote? get() = appRemote?.takeIf { it.isConnected }

    override fun positionMs(): Int? {
        val last = last ?: return null
        if (_loadedSongId.value == null) return null
        return spotifyPositionNow(last.progressMs, last.fetchedAt, System.currentTimeMillis(), last.isPlaying, last.durationMs).toInt()
    }

    override fun durationMs(): Int? = last?.durationMs?.toInt()

    override suspend fun startFull(songId: String, appleMusicId: String): Boolean =
        startQueue(listOf(songId to appleMusicId), 0)

    /**
     * 並べる曲を先に Spotify で探し (覚えている曲は探さない。探すのは並行で)、見つかった曲だけを並べて、
     * 押した曲 (無ければその後ろで最初に見つかった曲) から鳴らす。iOS `playSpotify` と対。
     */
    override suspend fun startQueue(entries: List<Pair<String, String>>, startAt: Int): Boolean {
        _failure.value = null
        val songIds = entries.map { it.first }
        if (songIds.isEmpty()) return false
        val uris = spotify.trackUris(songIds)
        val playable = songIds.indices.mapNotNull { i -> uris[i]?.let { Triple(songIds[i], it, i) } }
        if (playable.isEmpty()) return false
        val start = playable.indexOfFirst { it.third >= startAt }.takeIf { it >= 0 } ?: 0
        detach()
        val mine = session
        try {
            val remote = ensureConnected()
            val uris = playable.map { it.second }
            if (uris.size == 1) {
                playNative(remote, uris[0])
            } else {
                try {
                    playList(uris, start)
                } catch (e: SpotifyException) {
                    // 繋いだ直後で鳴らす先の一覧に出てこないことがある。せめて押した曲だけは鳴らす。
                    if (e.kind != SpotifyFailure.NO_DEVICE) throw e
                    playNative(remote, uris[start])
                }
            }
        } catch (e: SpotifyException) {
            _failure.value = e.kind
            return false
        }
        if (mine != session) return false
        isConfirmed = false
        startedAt = System.currentTimeMillis()
        // 次に聞きに行くまでの間も位置が進むように、頭から鳴り始めたことにしておく。
        last = Snapshot(trackId(playable[start].second), 0, null, true, startedAt)
        queueSongIds = playable.map { it.first }
        queueIndex = start
        songIdByTrackId = playable.mapNotNull { p -> trackId(p.second)?.let { it to p.first } }.toMap()
        _loadedSongId.value = playable[start].first
        _isPlaying.value = true
        refreshQueueFlags()
        subscribe()
        startPolling()
        return true
    }

    override fun skipNext() {
        if (_canSkipNext.value) command({ it.skipNext() }) { SpotifyWebApi.next(it) }
    }

    override fun skipPrevious() {
        val index = queueIndex ?: return
        val target = playQueuePreviousIndex(index.toUInt(), (positionMs() ?: 0).toLong())
        if (target.toInt() == index) seek(0) else command({ it.skipPrevious() }) { SpotifyWebApi.previous(it) }
    }

    override fun seek(ms: Int) {
        last = last?.copy(progressMs = ms.coerceAtLeast(0).toLong(), fetchedAt = System.currentTimeMillis())
        // 鳴り始める前に送ると、読み込み前の Spotify が捨てる。鳴り始めたら送る。
        if (!isConfirmed) {
            pendingSeekMs = ms
            return
        }
        command({ it.seekTo(ms.coerceAtLeast(0).toLong()) }) { SpotifyWebApi.seek(ms.toLong(), it) }
    }

    override fun togglePlay() {
        val current = last ?: return
        if (_isPlaying.value) {
            last = current.copy(progressMs = (positionMs() ?: 0).toLong(), isPlaying = false, fetchedAt = System.currentTimeMillis())
            _isPlaying.value = false
            command({ it.pause() }) { SpotifyWebApi.pause(it) }
        } else {
            last = current.copy(isPlaying = true, fetchedAt = System.currentTimeMillis())
            _isPlaying.value = true
            command({ it.resume() }) { SpotifyWebApi.resume(it) }
        }
    }

    /** 止める (Spotify アプリの音も止める)。 */
    override fun stop() {
        val playing = _loadedSongId.value != null && _isPlaying.value
        detach()
        if (playing) command({ it.pause() }, pollAfter = false) { SpotifyWebApi.pause(it) }
    }

    /** 追うのをやめて状態を手放す (Spotify 側の音は触らない)。 */
    private fun detach() {
        session++
        stateSubscription?.cancel()
        stateSubscription = null
        pollJob?.cancel()
        pollJob = null
        last = null
        isConfirmed = false
        pendingSeekMs = null
        queueSongIds = emptyList()
        queueIndex = null
        songIdByTrackId = emptyMap()
        _loadedSongId.value = null
        _isPlaying.value = false
        refreshQueueFlags()
    }

    private fun refreshQueueFlags() {
        val index = queueIndex
        _hasQueue.value = queueSongIds.size > 1
        _canSkipNext.value = index != null && playQueueNextIndex(index.toUInt(), queueSongIds.size.toUInt()) != null
        _upcomingQueue.value = if (index != null && index + 1 < queueSongIds.size) {
            queueSongIds.drop(index + 1).map { it to null }
        } else {
            emptyList()
        }
    }

    // MARK: - SDK

    /** 繋がっていなければ繋ぐ (Spotify アプリを裏で起こす。初回は Spotify アプリが許可を尋ねる)。 */
    private suspend fun ensureConnected(): SpotifyAppRemote {
        connected?.let { return it }
        val clientId = spotify.state.value.clientId ?: throw SpotifyException(SpotifyFailure.SESSION_EXPIRED)
        if (!SpotifyAppRemote.isSpotifyInstalled(context)) throw SpotifyException(SpotifyFailure.APP_NOT_INSTALLED)
        val params = ConnectionParams.Builder(clientId)
            .setRedirectUri(spotifySetupGuide(SpotifyGuidePlatform.ANDROID).redirectUri)
            .showAuthView(true)
            .build()
        val remote = suspendCancellableCoroutine { cont ->
            SpotifyAppRemote.connect(context, params, object : Connector.ConnectionListener {
                override fun onConnected(remote: SpotifyAppRemote) {
                    if (cont.isActive) cont.resume(remote)
                }

                override fun onFailure(error: Throwable) {
                    Log.w(TAG, "spotify_sdk_connect_failed: $error")
                    val kind = when (error) {
                        is CouldNotFindSpotifyApp -> SpotifyFailure.APP_NOT_INSTALLED
                        else -> SpotifyFailure.CONNECTION_FAILED
                    }
                    // 繋いだ後に切れたときもここに来る。そのときは Web API に聞く方へ落とすだけ。
                    appRemote = null
                    if (cont.isActive) cont.resumeWithException(SpotifyException(kind))
                }
            })
        }
        appRemote = remote
        return remote
    }

    private suspend fun playNative(remote: SpotifyAppRemote, uri: String) {
        suspendCancellableCoroutine { cont ->
            remote.playerApi.play(uri)
                .setResultCallback { if (cont.isActive) cont.resume(Unit) }
                .setErrorCallback {
                    Log.w(TAG, "spotify_sdk_play_failed: $it")
                    if (cont.isActive) cont.resumeWithException(SpotifyException(SpotifyFailure.PREMIUM_REQUIRED))
                }
        }
    }

    private suspend fun playList(uris: List<String>, offset: Int) {
        val token = spotify.accessToken()
        val devices = SpotifyWebApi.devices(token)
        val device = spotifyPickDevice(devices)?.let { devices[it.toInt()].id }
            ?: throw SpotifyException(SpotifyFailure.NO_DEVICE)
        SpotifyWebApi.play(uris, offset, device, token)
    }

    /** SDK の知らせを受け始める。 */
    private fun subscribe() {
        val remote = connected ?: return
        stateSubscription?.cancel()
        val mine = session
        stateSubscription = remote.playerApi.subscribeToPlayerState().setEventCallback { state ->
            if (mine != session) return@setEventCallback
            val track = state.track
            accept(
                track?.uri?.let(::trackId),
                state.playbackPosition,
                track?.duration?.takeIf { it > 0 },
                !state.isPaused,
            )
        }
    }

    /** 操作を送る。繋がっていれば SDK で、繋がっていなければ Web API で。 */
    private fun command(
        native: (PlayerApi) -> Unit,
        pollAfter: Boolean = true,
        web: suspend (String) -> Unit,
    ) {
        val remote = connected
        if (remote != null) {
            native(remote.playerApi)
            return
        }
        send(pollAfter, web)
    }

    // MARK: - Spotify とのやりとり (SDK が繋がっていない間)

    /** 操作を送って、すぐ状態を聞き直す (Spotify 側が受け付けたかを画面に返す)。 */
    private fun send(pollAfter: Boolean = true, action: suspend (String) -> Unit) {
        val mine = session
        scope.launch {
            try {
                action(spotify.accessToken())
                if (pollAfter) {
                    delay(300)
                    if (mine == session) poll()
                }
            } catch (e: SpotifyException) {
                Log.w(TAG, "spotify_control_failed: ${e.kind}")
                if (mine != session) return@launch
                // 通信の揺れ・「今はできない」(Restriction violated) は伝えない。状態は次の周回で読み直す。
                if (stopsPlayback(e.kind)) {
                    _failure.value = e.kind
                    detach()
                } else if (e.kind == SpotifyFailure.NO_DEVICE) {
                    _failure.value = e.kind
                }
            }
        }
    }

    private fun startPolling() {
        if (pollJob != null) return
        pollJob = scope.launch {
            while (isActive) {
                // 鳴っている間は 1 秒ごと、止まっている間はゆっくり。SDK が繋がっていれば SDK の知らせを待つ。
                delay(if (last?.isPlaying == true) 1_000 else 3_000)
                if (connected == null) poll()
            }
        }
    }

    /**
     * Spotify の状態をこちらへ写す (曲が替わった・Spotify アプリ側で止めた)。
     * このアプリが並べていない曲に替わったら (Spotify アプリで別の曲を選んだ)、追うのをやめる。
     */
    private suspend fun poll() {
        if (_loadedSongId.value == null) return
        val mine = session
        val state = try {
            SpotifyWebApi.playerState(spotify.accessToken())
        } catch (e: SpotifyException) {
            // 通信の揺れ・混雑は次の周回で聞き直す。鍵や許可の問題は聞き続けても直らない。
            if (mine == session && stopsPlayback(e.kind)) {
                _failure.value = e.kind
                detach()
            }
            return
        }
        // 聞いている間に鳴らし直した・止めたなら、この答えは前の再生のもの。
        if (mine != session) return
        accept(state?.trackId, state?.progressMs ?: 0, state?.durationMs, state?.isPlaying ?: false)
    }

    /** 知った状態を受け取る (SDK の知らせ・Web API の答えのどちらからも)。 */
    private fun accept(trackId: String?, progressMs: Long, durationMs: Long?, isPlaying: Boolean) {
        if (_loadedSongId.value == null) return
        if (!isConfirmed) {
            val arrived = trackId?.let { songIdByTrackId.containsKey(it) } ?: false
            val timedOut = System.currentTimeMillis() - startedAt > CONFIRM_TIMEOUT_MS
            if (!arrived && !timedOut) return
            isConfirmed = true
            pendingSeekMs?.let {
                pendingSeekMs = null
                seek(it)
            }
        }
        if (trackId == null) {
            last = last?.copy(isPlaying = false, fetchedAt = System.currentTimeMillis())
            _isPlaying.value = false
            return
        }
        last = Snapshot(trackId, progressMs, durationMs, isPlaying, System.currentTimeMillis())
        val songId = songIdByTrackId[trackId]
        if (songId == null) {
            detach()
            return
        }
        if (songId != _loadedSongId.value) {
            _loadedSongId.value = songId
            queueIndex = queueSongIds.indexOf(songId).takeIf { it >= 0 }
            refreshQueueFlags()
        }
        if (_isPlaying.value != isPlaying) _isPlaying.value = isPlaying
    }

    private fun trackId(uri: String): String? = uri.removePrefix("spotify:track:").takeIf { uri.startsWith("spotify:track:") }

    private companion object {
        const val TAG = "SpotifyPlayback"
        /** 頼んだ曲が鳴り始めるのを待つ長さ。過ぎたら、返ってくる状態をそのまま信じる。 */
        const val CONFIRM_TIMEOUT_MS = 8_000L

        /** 聞き続けても直らない失敗 (再生ごと手放す)。 */
        fun stopsPlayback(kind: SpotifyFailure): Boolean = when (kind) {
            SpotifyFailure.SESSION_EXPIRED, SpotifyFailure.PLAYBACK_NOT_ALLOWED,
            SpotifyFailure.PREMIUM_REQUIRED, SpotifyFailure.NOT_REGISTERED -> true
            else -> false
        }
    }
}
