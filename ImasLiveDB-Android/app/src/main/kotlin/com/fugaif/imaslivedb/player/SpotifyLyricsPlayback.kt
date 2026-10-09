package com.fugaif.imaslivedb.player

import android.util.Log
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
import uniffi.imas_core.SpotifyFailure
import uniffi.imas_core.playQueueNextIndex
import uniffi.imas_core.playQueuePreviousIndex
import uniffi.imas_core.spotifyPickDevice
import uniffi.imas_core.spotifyPositionNow

/**
 * Spotify アプリを Web API で操作して鳴らす [LyricsPlayback] (Spotify Connect)。iOS `SpotifyRemotePlayer` と
 * `MusicKitService` の Spotify の枝を合わせたもの。音を出すのは利用者の Spotify アプリで、このアプリは
 * 「この曲を鳴らして」「今どこ？」を頼むだけ (SDK は使わない。Client ID の登録だけで済む)。
 *
 * 再生位置は周期で聞きに行き、間はコア (`spotifyPositionNow`) が経過を足して埋める。
 * 鳴らす先 (どの端末の Spotify アプリか) はコア (`spotifyPickDevice`) が選ぶ。
 *
 * 鳴らし始めは Spotify 側の切り替わりが遅れる (頼んでから 1〜2 秒は前の曲が返る)。
 * そこで鳴らし始めごとに番号 ([session]) を振り、頼んだ曲が一度返ってくるまでの状態は写さない。
 * その間の位置の指定 (歌詞の行のタップ) も、頼んだ曲が鳴り始めてから送る。
 *
 * 「次はこれ」は Spotify では足さない。足すには Spotify の「次に再生」に積むしかなく、
 * それは鳴らし直しても消えずに次の再生へ割り込むため。
 */
class SpotifyLyricsPlayback(private val spotify: SpotifyService) : LyricsPlayback {
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
            val token = spotify.accessToken()
            val devices = SpotifyWebApi.devices(token)
            val device = spotifyPickDevice(devices)?.let { devices[it.toInt()].id }
                ?: throw SpotifyException(SpotifyFailure.NO_DEVICE)
            SpotifyWebApi.play(playable.map { it.second }, start, device, token)
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
        startPolling()
        return true
    }

    override fun skipNext() {
        if (_canSkipNext.value) send { SpotifyWebApi.next(it) }
    }

    override fun skipPrevious() {
        val index = queueIndex ?: return
        val target = playQueuePreviousIndex(index.toUInt(), (positionMs() ?: 0).toLong())
        if (target.toInt() == index) seek(0) else send { SpotifyWebApi.previous(it) }
    }

    override fun seek(ms: Int) {
        last = last?.copy(progressMs = ms.coerceAtLeast(0).toLong(), fetchedAt = System.currentTimeMillis())
        // 鳴り始める前に送ると、読み込み前の Spotify が捨てる。鳴り始めたら送る。
        if (!isConfirmed) {
            pendingSeekMs = ms
            return
        }
        send { SpotifyWebApi.seek(ms.toLong(), it) }
    }

    override fun togglePlay() {
        val current = last ?: return
        if (_isPlaying.value) {
            last = current.copy(progressMs = (positionMs() ?: 0).toLong(), isPlaying = false, fetchedAt = System.currentTimeMillis())
            _isPlaying.value = false
            send { SpotifyWebApi.pause(it) }
        } else {
            last = current.copy(isPlaying = true, fetchedAt = System.currentTimeMillis())
            _isPlaying.value = true
            send { SpotifyWebApi.resume(it) }
        }
    }

    /** 止める (Spotify アプリの音も止める)。 */
    override fun stop() {
        val playing = _loadedSongId.value != null && _isPlaying.value
        detach()
        if (playing) send(pollAfter = false) { SpotifyWebApi.pause(it) }
    }

    /** 追うのをやめて状態を手放す (Spotify 側の音は触らない)。 */
    private fun detach() {
        session++
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

    // MARK: - Spotify とのやりとり

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
                // 鳴っている間は 1 秒ごと、止まっている間はゆっくり。
                delay(if (last?.isPlaying == true) 1_000 else 3_000)
                poll()
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
        if (!isConfirmed) {
            val arrived = state?.trackId?.let { songIdByTrackId.containsKey(it) } ?: false
            val timedOut = System.currentTimeMillis() - startedAt > CONFIRM_TIMEOUT_MS
            if (!arrived && !timedOut) return
            isConfirmed = true
            pendingSeekMs?.let {
                pendingSeekMs = null
                seek(it)
            }
        }
        if (state == null || state.trackId == null) {
            last = last?.copy(isPlaying = false, fetchedAt = System.currentTimeMillis())
            _isPlaying.value = false
            return
        }
        last = Snapshot(state.trackId, state.progressMs, state.durationMs, state.isPlaying, System.currentTimeMillis())
        val songId = songIdByTrackId[state.trackId]
        if (songId == null) {
            detach()
            return
        }
        if (songId != _loadedSongId.value) {
            _loadedSongId.value = songId
            queueIndex = queueSongIds.indexOf(songId).takeIf { it >= 0 }
            refreshQueueFlags()
        }
        if (_isPlaying.value != state.isPlaying) _isPlaying.value = state.isPlaying
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
