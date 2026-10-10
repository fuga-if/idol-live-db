package com.fugaif.imaslivedb.player

import com.fugaif.imaslivedb.data.spotify.SpotifyService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import uniffi.imas_core.FullPlaybackService
import uniffi.imas_core.SpotifyFailure
import uniffi.imas_core.chooseFullPlayback

/**
 * フル尺を Apple Music と Spotify のどちらで鳴らすかを振り分ける [LyricsPlayback]。
 * iOS は `MusicKitService.playFullSongs` が同じ振り分けをする。選び方はコア (`chooseFullPlayback`)。
 *
 * 鳴らし始めるときにどちらかを選び、以降の操作 (止める・送る・位置) はその時に選んだ方へ渡す。
 */
@OptIn(ExperimentalCoroutinesApi::class)
class RoutedLyricsPlayback(
    private val apple: LyricsPlayback,
    private val spotifyPlayback: SpotifyLyricsPlayback,
    private val spotify: SpotifyService,
) : LyricsPlayback {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val active = MutableStateFlow(apple)

    /** いまフル尺を鳴らすならどちらか。鳴らせなければ null (試聴に落とす)。 */
    fun currentService(): FullPlaybackService? {
        val s = spotify.state.value
        return chooseFullPlayback(
            s.fullPlaybackPreference,
            apple.appleMusicState.value == AppleMusicState.READY,
            s.isConnected && s.canControlPlayback,
        )
    }

    override val fullPlaysWithoutAppleMusicId: Boolean get() = currentService() == FullPlaybackService.SPOTIFY

    /** Spotify で鳴らせなかった理由 (画面が出して [clearSpotifyFailure] で消す)。 */
    val spotifyFailure: StateFlow<SpotifyFailure?> = spotifyPlayback.failure
    fun clearSpotifyFailure() = spotifyPlayback.clearFailure()

    // Spotify で鳴らすなら、Apple Music のサインインの案内は出さない (鳴らせる扱い)。
    override val appleMusicState: StateFlow<AppleMusicState> =
        combine(apple.appleMusicState, spotify.state) { _, _ ->
            if (currentService() == FullPlaybackService.SPOTIFY) AppleMusicState.READY else apple.appleMusicState.value
        }.stateIn(scope, SharingStarted.Eagerly, apple.appleMusicState.value)

    override fun signIn() = apple.signIn()

    override val isAvailable: StateFlow<Boolean> =
        combine(apple.isAvailable, spotify.state) { a, s -> a || (s.isConnected && s.canControlPlayback) }
            .stateIn(scope, SharingStarted.Eagerly, apple.isAvailable.value)

    override val loadedSongId: StateFlow<String?> = follow { it.loadedSongId }
    override val isPlaying: StateFlow<Boolean> = follow { it.isPlaying }
    override val hasQueue: StateFlow<Boolean> = follow { it.hasQueue }
    override val canSkipNext: StateFlow<Boolean> = follow { it.canSkipNext }
    override val upcomingQueue: StateFlow<List<Pair<String, String?>>> = follow { it.upcomingQueue }
    override val autoplayNext: StateFlow<Boolean> = apple.autoplayNext

    init {
        spotifyPlayback.setAutoplayNext(apple.autoplayNext.value)
    }

    override fun setAutoplayNext(value: Boolean) {
        apple.setAutoplayNext(value)
        spotifyPlayback.setAutoplayNext(value)
    }

    override fun positionMs(): Int? = active.value.positionMs()
    override fun durationMs(): Int? = active.value.durationMs()

    override suspend fun startFull(songId: String, appleMusicId: String): Boolean =
        startQueue(listOf(songId to appleMusicId), 0)

    override suspend fun startQueue(entries: List<Pair<String, String>>, startAt: Int): Boolean {
        val target = when (currentService()) {
            FullPlaybackService.SPOTIFY -> spotifyPlayback
            FullPlaybackService.APPLE_MUSIC, null -> apple
        }
        // 片方で鳴らしたまま、もう片方で鳴らし始めない。
        if (active.value !== target) active.value.stop()
        active.value = target
        return target.startQueue(entries, startAt)
    }

    override fun skipNext() = active.value.skipNext()
    override fun skipPrevious() = active.value.skipPrevious()
    override fun seek(ms: Int) = active.value.seek(ms)
    override fun togglePlay() = active.value.togglePlay()
    override fun stop() = active.value.stop()

    private fun <T> follow(pick: (LyricsPlayback) -> StateFlow<T>): StateFlow<T> =
        active.flatMapLatest { pick(it) }.stateIn(scope, SharingStarted.Eagerly, pick(apple).value)
}
