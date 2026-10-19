package com.fugaif.imaslivedb.data.community

import android.content.Context
import android.util.Log
import com.fugaif.imaslivedb.player.LyricsPlayback
import com.fugaif.imaslivedb.player.PlaybackState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import uniffi.imas_core.PlayKind
import uniffi.imas_core.PlayObservation
import uniffi.imas_core.PlayTimerAction
import uniffi.imas_core.playSessionFire
import uniffi.imas_core.playSessionIdle
import uniffi.imas_core.playSessionObserve
import uniffi.imas_core.playBatchBody
import uniffi.imas_core.playLogAfterSent
import uniffi.imas_core.playLogDecode
import uniffi.imas_core.playLogDue
import uniffi.imas_core.playLogEncode
import uniffi.imas_core.playLogMarkAttempt
import uniffi.imas_core.playLogRecord

/**
 * 曲の再生回数 (試聴 / フル再生) を数えて、みんなの集計 (`POST /plays/batch`) に送る。
 * 何秒で 1 回か・貯め方・いつ送るか・送れた分の引き方・本文の形はすべて imas-core (`play_counts`)。
 * ここは「流れ続けているかを見る」「保存する」「送る」だけ。
 *
 * @param send 本文 ([playBatchBody]) を送る。失敗 (429 含む) は例外 = 貯めたまま残す。
 * @param now epoch 秒。
 */
class PlayCountRepository(
    context: Context,
    private val scope: CoroutineScope,
    private val now: () -> Double = { System.currentTimeMillis() / 1000.0 },
    private val send: suspend (body: String) -> Unit
) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    /** ログの読み書きの排他。送信中は持たない (その間の記録を止めない)。 */
    private val lock = Mutex()
    /** 送信を重ねない。 */
    private val flushing = Mutex()

    /**
     * 鳴っている曲を見て数える。いつ 1 回と数えるかは imas-core の状態機械 (`playSessionObserve` /
     * `playSessionFire`) が決め、ここは「観測を渡す」「指示どおりにタイマを動かす」「鳴ったら記録する」だけ。
     * 試聴とフル再生は別々のまとまりとして見る。
     * 一時停止中も曲は渡し続け (isPlaying だけ false)、止めて曲が無くなったときだけ songId を null にする。
     * イントロクイズなど数えない再生 ([PlaybackState.countsAsPlay] が false) もそのまま渡す。
     */
    fun observe(preview: StateFlow<PlaybackState>, full: LyricsPlayback) {
        track(
            preview.map { PlayObservation(it.nowPlayingSongId, PlayKind.PREVIEW, it.isPlaying, it.countsAsPlay) }
        )
        // フル再生の loadedSongId は一時停止・Spotify の一瞬の null でも手放さない (止めたときだけ null)。
        track(
            combine(full.loadedSongId, full.isPlaying) { id, playing ->
                PlayObservation(id, PlayKind.FULL, playing, true)
            }
        )
    }

    private fun track(observations: Flow<PlayObservation>) {
        val sessionLock = Mutex()
        var session = playSessionIdle()
        var timer: Job? = null
        scope.launch {
            observations.distinctUntilChanged().collect { observation ->
                sessionLock.withLock {
                    val step = playSessionObserve(session, observation)
                    session = step.session
                    when (val action = step.timer) {
                        is PlayTimerAction.Keep -> Unit
                        is PlayTimerAction.Cancel -> { timer?.cancel(); timer = null }
                        is PlayTimerAction.Start -> {
                            timer?.cancel()
                            timer = scope.launch {
                                delay((action.seconds * 1000).toLong())
                                val fire = sessionLock.withLock {
                                    playSessionFire(session).also { session = it.session }
                                }
                                if (fire.record) record(fire.session.songId, fire.session.kind)
                            }
                        }
                    }
                }
            }
        }
    }

    /** 1 回数える。 */
    suspend fun record(songId: String, kind: PlayKind) = lock.withLock {
        save(playLogRecord(load(), songId, kind))
    }

    /** 送る時間なら貯めた分を送る (前面に出たとき・背面に回るとき)。空・1 時間以内なら何もしない。 */
    suspend fun flushIfDue() {
        if (!flushing.tryLock()) return
        try {
            val batch = lock.withLock {
                val log = load()
                val due = playLogDue(log, now())
                if (due.isNotEmpty()) save(playLogMarkAttempt(log, now()))
                due
            }
            if (batch.isEmpty()) return
            try {
                send(playBatchBody(batch))
            } catch (e: Exception) {
                Log.w(TAG, "plays batch failed, keep", e)
                return
            }
            // 送っている間に増えた分を消さないよう、最新のログから送れた分だけを引く。
            lock.withLock { save(playLogAfterSent(load(), batch)) }
        } finally {
            flushing.unlock()
        }
    }

    private fun load() = playLogDecode(prefs.getString(KEY_LOG, null) ?: "")

    private fun save(log: uniffi.imas_core.PlayLog) {
        prefs.edit().putString(KEY_LOG, playLogEncode(log)).apply()
    }

    private companion object {
        const val TAG = "PlayCountRepository"
        const val PREFS_NAME = "play_count_log"
        const val KEY_LOG = "log"
    }
}
