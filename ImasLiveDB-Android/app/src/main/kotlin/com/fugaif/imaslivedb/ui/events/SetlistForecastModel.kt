package com.fugaif.imaslivedb.ui.events

import android.util.Log
import com.fugaif.imaslivedb.data.repository.SetlistForecastReading
import com.fugaif.imaslivedb.data.repository.SetlistPredictionVoting
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import uniffi.imas_core.ForecastShowFlag
import uniffi.imas_core.ForecastSongRecord
import uniffi.imas_core.SetlistForecastRecord

/**
 * セトリ予想の画面の「機械予測」の節。iOS `SetlistForecastViewModel` と 1:1。
 *
 * 点数・順位・理由の札・公演の印は、すべてコア (`setlistForecast`) の答えをそのまま出す。
 * ここが持つのは、読み込みの状態と、みんなの予想に入っている曲を隠すことと、
 * 「予想に入れる」(= 既存の投票) の呼び出しだけ。
 *
 * 画面は [state] を収集して、その値から [State.visibleSongs] 等を引く
 * (このクラスの中の値を直に読む関数を Composable から呼ぶと、Compose が変化を追えない)。
 */
class SetlistForecastModel(
    val showId: String,
    private val reading: SetlistForecastReading,
    private val voting: SetlistPredictionVoting
) {
    sealed interface Phase {
        data object Loading : Phase
        data class Loaded(val record: SetlistForecastRecord) : Phase
        /** 予測の対象でない公演か、読み込みに失敗した。節ごと出さない。 */
        data object Unavailable : Phase
    }

    data class State(
        val phase: Phase = Phase.Loading,
        /** このセッションで「予想に入れる」が成功した曲。みんなの予想の読み直しを待たずに隠す。 */
        val promotedSongIds: Set<String> = emptySet(),
        /** 投票を送っている最中の曲 (連打の防止)。 */
        val promotingSongId: String? = null
    ) {
        /** 出す曲。みんなの予想 (票のある曲) と、ここで予想に入れた曲は除く。順位はコアのまま。 */
        fun visibleSongs(predictedSongIds: Set<String>): List<ForecastSongRecord> {
            val record = (phase as? Phase.Loaded)?.record ?: return emptyList()
            return record.songs.asSequence()
                .filter { it.songId !in predictedSongIds && it.songId !in promotedSongIds }
                .take(DISPLAY_LIMIT)
                .toList()
        }

        /** 出演者未発表の印が立っていれば、その注記 (コアの label)。 */
        val castUnannouncedNote: String?
            get() = (phase as? Phase.Loaded)?.record?.flags
                ?.firstOrNull { it.flag == ForecastShowFlag.CAST_UNANNOUNCED }?.label
    }

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state.asStateFlow()

    suspend fun load() {
        val phase = try {
            reading.setlistForecast(showId, FETCH_LIMIT)?.let { Phase.Loaded(it) } ?: Phase.Unavailable
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "setlist_forecast_failed show=$showId", e)
            Phase.Unavailable
        }
        _state.update { it.copy(phase = phase) }
    }

    /** 「予想に入れる」。既存の投票をそのまま呼ぶ。失敗はそのまま投げる (表示は画面の既存の経路)。 */
    suspend fun promote(songId: String) {
        if (_state.value.promotingSongId != null) return
        _state.update { it.copy(promotingSongId = songId) }
        try {
            voting.vote(showId, songId)
            _state.update { it.copy(promotedSongIds = it.promotedSongIds + songId) }
        } finally {
            _state.update { it.copy(promotingSongId = null) }
        }
    }

    companion object {
        private const val TAG = "SetlistForecast"

        /** 節に出す曲数。 */
        const val DISPLAY_LIMIT = 20

        /**
         * コアに頼む曲数。みんなの予想に入っている曲を隠しても 20 曲残るよう、多めに引く。
         * (予想は 1 人 3 票なので、票の入った曲がこれを超えて上位を占めることはまず無い)
         */
        const val FETCH_LIMIT = 60
    }
}
