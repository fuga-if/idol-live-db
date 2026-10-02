package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.lyrics.LyricsApi
import com.fugaif.imaslivedb.data.lyrics.TimingEntry
import uniffi.imas_core.lyricNextRecordable

/**
 * 歌詞行とコールの再生位置 (タイミング) を付ける・直す画面の状態。iOS `LyricTimingRecorder` の移植。
 *
 * 段は 2 本: 歌詞の行と、コール。どちらも「歌い出しで押す」で次の 1 つを記録し、
 * タイムラインで前後に寄せる。保存 ([LyricsApi.saveTimings]) するまでサーバにも端末にも残さない。
 * 行の本文・コールの文言は持たない (id と種別だけ)。
 *
 * 「次に記録する行」の決め方はコア ([lyricNextRecordable]) が持つ。
 */
class LyricTimingRecorder(lyrics: Lyrics, val songId: String) {

    sealed interface SaveState {
        data object Idle : SaveState
        data object Saving : SaveState
        data class Failed(val message: String) : SaveState
    }

    enum class Lane { LINES, CALLS }

    /** 表示順の行 ID。 */
    val lineIds: List<String> = lyrics.lines.map { it.id }

    /** 曲の順 (行の順 → 行の中の順) に並べたコールの ID と、ぶら下がる行の添字。 */
    val callIds: List<String>
    val callLineIndexes: List<Int>

    /** 表示順の各行の種別 (`lyric` / `marker` / `blank`)。コアへ渡す。 */
    private val kinds: List<String> = lyrics.lines.map { it.kind.raw }

    /** 表示順の各行の開始 ms。 */
    var starts: List<Int?> by mutableStateOf(lyrics.lines.map { it.startMs })
        private set
    private val originalStarts: List<Int?> = starts

    /** 曲の順の各コールの開始 ms。 */
    var callStarts: List<Int?> by mutableStateOf(emptyList())
        private set
    private val originalCallStarts: List<Int?>

    /** 表示順の各行の被せ指定 ("overlay" / "main" / null = 括弧で決める)。 */
    var layers: List<String?> by mutableStateOf(lyrics.lines.map { it.layer })
        private set
    private val originalLayers: List<String?> = layers

    var lane: Lane by mutableStateOf(Lane.LINES)

    /** 次に記録する行 / コールの添字。最後まで記録したら null。 */
    var cursor: Int? by mutableStateOf(null)
        private set
    var callCursor: Int? by mutableStateOf(null)
        private set
    var saveState: SaveState by mutableStateOf(SaveState.Idle)
        private set

    private data class HistoryEntry(val lane: Lane, val index: Int, val previous: Int?, val cursor: Int?)
    private val history = ArrayDeque<HistoryEntry>()
    /** 直前の履歴が「微調整」か。なぞっている間は 1 回の取り消しにまとめる。 */
    private var lastWasAdjust = false

    init {
        val calls = lyrics.lines.flatMapIndexed { i, line -> line.calls.map { i to it } }
        callIds = calls.map { it.second.id }
        callLineIndexes = calls.map { it.first }
        callStarts = calls.map { it.second.startMs }
        originalCallStarts = callStarts
        // 途中から続けられるよう、まだ時刻の無い最初のものから始める。全部あれば先頭から。
        cursor = firstUntimed(starts) { after -> lyricNextRecordable(kinds, after) }
        callCursor = firstUntimed(callStarts) { after ->
            val next = (after?.toInt()?.plus(1)) ?: 0
            if (next < callStarts.size) next.toUInt() else null
        }
    }

    private fun firstUntimed(values: List<Int?>, next: (UInt?) -> UInt?): Int? {
        val first = next(null)?.toInt()
        var candidate = first
        while (candidate != null && values[candidate] != null) {
            candidate = next(candidate.toUInt())?.toInt()
        }
        return candidate ?: first
    }

    val isDirty: Boolean
        get() = starts != originalStarts || callStarts != originalCallStarts || layers != originalLayers

    /** 行の被せ指定を切り替える (被せ ⇄ メイン)。括弧の判定より指定が勝つ。 */
    fun setOverlay(lineId: String, overlay: Boolean) {
        val i = lineIds.indexOf(lineId)
        if (i < 0) return
        layers = layers.toMutableList().also { it[i] = if (overlay) "overlay" else "main" }
    }

    val canUndo: Boolean get() = history.isNotEmpty()
    val hasCalls: Boolean get() = callIds.isNotEmpty()

    /** 行またはコールの開始 ms (id で引く)。 */
    fun start(id: String): Int? {
        lineIds.indexOf(id).takeIf { it >= 0 }?.let { return starts[it] }
        callIds.indexOf(id).takeIf { it >= 0 }?.let { return callStarts[it] }
        return null
    }

    /** 記録できる行か (空行は記録しない)。判定はコアの「次の行」と同じ規則に寄せる。 */
    fun isRecordable(lineId: String): Boolean {
        val index = lineIds.indexOf(lineId)
        if (index < 0) return false
        val previous = if (index == 0) null else (index - 1).toUInt()
        return lyricNextRecordable(kinds, previous) == index.toUInt()
    }

    /** いま記録している段の「次」。 */
    val laneCursor: Int? get() = if (lane == Lane.LINES) cursor else callCursor

    /** いま記録している段の次の 1 つを、今の再生位置で記録する (大きい記録ボタン)。 */
    fun recordNext(positionMs: Int) {
        when (lane) {
            Lane.LINES -> {
                val index = cursor ?: return
                history.addLast(HistoryEntry(Lane.LINES, index, starts[index], cursor))
                starts = starts.toMutableList().also { it[index] = positionMs }
                cursor = lyricNextRecordable(kinds, index.toUInt())?.toInt()
            }
            Lane.CALLS -> {
                val index = callCursor ?: return
                history.addLast(HistoryEntry(Lane.CALLS, index, callStarts[index], callCursor))
                callStarts = callStarts.toMutableList().also { it[index] = positionMs }
                callCursor = if (index + 1 < callIds.size) index + 1 else null
            }
        }
        lastWasAdjust = false
    }

    /** 行またはコールの開始を指定の時刻にする (つまみ・微調整)。カーソルは動かさない。 */
    fun adjust(id: String, toMs: Int) {
        val lane: Lane
        val index: Int
        val li = lineIds.indexOf(id)
        if (li >= 0 && isRecordable(id)) {
            lane = Lane.LINES; index = li
        } else {
            val ci = callIds.indexOf(id)
            if (ci < 0) return
            lane = Lane.CALLS; index = ci
        }
        val current = if (lane == Lane.LINES) starts[index] else callStarts[index]
        if (!(lastWasAdjust && history.lastOrNull()?.lane == lane && history.lastOrNull()?.index == index)) {
            history.addLast(HistoryEntry(lane, index, current, if (lane == Lane.LINES) cursor else callCursor))
        }
        val clamped = maxOf(0, toMs)
        if (lane == Lane.LINES) {
            starts = starts.toMutableList().also { it[index] = clamped }
        } else {
            callStarts = callStarts.toMutableList().also { it[index] = clamped }
        }
        lastWasAdjust = true
    }

    /** 前後に寄せる (-0.1 秒 / +0.1 秒)。記録の無いものは動かさない。 */
    fun nudge(id: String, byMs: Int) {
        val current = start(id) ?: return
        adjust(id, current + byMs)
    }

    /** 表示順の各行の開始 ms (コアに渡す形)。 */
    val startsForCore: List<Long?> get() = starts.map { it?.toLong() }
    /** 曲の順の各コールの開始 ms (コアに渡す形)。 */
    val callStartsForCore: List<Long?> get() = callStarts.map { it?.toLong() }

    /** 直前の記録を取り消す (カーソルも戻す)。 */
    fun undo() {
        val last = history.removeLastOrNull() ?: return
        lastWasAdjust = false
        when (last.lane) {
            Lane.LINES -> {
                starts = starts.toMutableList().also { it[last.index] = last.previous }
                cursor = last.cursor
            }
            Lane.CALLS -> {
                callStarts = callStarts.toMutableList().also { it[last.index] = last.previous }
                callCursor = last.cursor
            }
        }
    }

    suspend fun save(api: LyricsApi): Boolean {
        if (saveState == SaveState.Saving) return false
        saveState = SaveState.Saving
        val lines = lineIds.indices.map { TimingEntry(lineIds[it], starts[it], layers[it]) }
        val calls = callIds.indices.map { TimingEntry(callIds[it], callStarts[it]) }
        return try {
            api.saveTimings(songId, lines, calls)
            saveState = SaveState.Idle
            true
        } catch (e: Exception) {
            saveState = SaveState.Failed(e.message ?: "保存できませんでした")
            false
        }
    }
}
