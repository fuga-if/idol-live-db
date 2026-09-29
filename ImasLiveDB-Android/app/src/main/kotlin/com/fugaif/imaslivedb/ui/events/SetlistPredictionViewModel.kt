package com.fugaif.imaslivedb.ui.events

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.fugaif.imaslivedb.data.auth.AuthState
import com.fugaif.imaslivedb.data.community.SetlistPredictionService
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import uniffi.imas_core.planVoteSelection
import uniffi.imas_core.voteLimitPerTarget
import uniffi.imas_core.votesRemaining

/** 予想の 1 行。票はサーバ、曲名とジャケは端末のカタログから引く (iOS `SetlistPrediction`)。 */
data class PredictionRow(
    val songId: String,
    val title: String,
    val brandId: String?,
    val artworkUrl: String?,
    val voteCount: Int,
    val hasUserVoted: Boolean
)

data class SetlistPredictionUiState(
    val isLoading: Boolean = true,
    val predictions: List<PredictionRow> = emptyList(),
    /** 読み込み・投票の失敗や、溢れた票のお知らせ。次の読み込みで消える。 */
    val errorMessage: String? = null
) {
    val totalVotes: Int get() = predictions.sumOf { it.voteCount }

    /** 自分が投票済みの曲 (票数順のまま)。 */
    val myVotedSongIds: List<String> get() = predictions.filter { it.hasUserVoted }.map { it.songId }

    /** 残りの票数 (上限と数え方はコア)。 */
    val remaining: Int get() = votesRemaining(myVotedSongIds.size.toUInt()).toInt()

    val predictedSongIds: Set<String> get() = predictions.mapTo(HashSet()) { it.songId }
}

/**
 * 未来の公演のセトリ予想 (みんなの予想 + 機械予測)。iOS `SetlistPredictionView` の
 * データの部分の移植。Apple Music のプレイリスト作成・シェア・歌唱メンバー予想はまだ無い。
 *
 * 投票はアプリのスコープで送る (押した直後に画面を離れても最後まで届く)。
 */
class SetlistPredictionViewModel(
    app: Application,
    private val showId: String
) : AndroidViewModel(app) {

    private val module = AppModule.from(app)
    private val service = module.setlistPredictionService

    val forecast = SetlistForecastModel(
        showId = showId,
        reading = module.setlistForecastReading,
        voting = module.setlistPredictionVoting
    )

    private val _uiState = MutableStateFlow(SetlistPredictionUiState())
    val uiState: StateFlow<SetlistPredictionUiState> = _uiState.asStateFlow()

    private val _loginPrompt = MutableStateFlow(false)
    val loginPrompt: StateFlow<Boolean> = _loginPrompt.asStateFlow()

    val authState: StateFlow<AuthState> = module.authService.state

    init {
        viewModelScope.launch { loadPredictions() }
        viewModelScope.launch { forecast.load() }
    }

    fun reload() {
        viewModelScope.launch { loadPredictions() }
    }

    private suspend fun loadPredictions(notice: String? = null) {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        try {
            val entries = service.fetch(showId).distinctBy { it.songId }
            // 曲名とジャケは API ではなく端末のカタログから (D1 のミラーに頼らない)。
            val songs = hydrateInOrder(entries.map { it.songId }, Song::id) {
                module.database.songDao().fetchSongsByIds(it)
            }.associateBy { it.id }
            val rows = entries.map { e ->
                val song = songs[e.songId]
                PredictionRow(
                    songId = e.songId,
                    // カタログにまだ無い曲 (同期直後等) でも票は見せる。題名は ID で代える。
                    title = song?.title ?: e.songId,
                    brandId = song?.brandId,
                    artworkUrl = song?.artworkUrl,
                    voteCount = e.voteCount,
                    hasUserVoted = e.hasUserVoted
                )
            }
            _uiState.update { it.copy(isLoading = false, predictions = rows, errorMessage = notice) }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "load_predictions_failed show=$showId", e)
            _uiState.update { it.copy(isLoading = false, errorMessage = notice ?: e.message) }
        }
    }

    /** 予想の投票トグル (投票済みなら取り消す)。 */
    fun toggleVote(row: PredictionRow) = write {
        try {
            if (row.hasUserVoted) service.unvote(showId, row.songId) else service.vote(showId, row.songId)
            loadPredictions()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            fail(e)
        }
    }

    /**
     * 曲をまとめて予想に入れる (ピッカーの複数選択)。どれを入れてどれが溢れるかはコア
     * (`planVoteSelection`)。順に投票して、最後に 1 回だけ読み直す。
     */
    fun addPredictions(songIdsInOrder: List<String>) {
        if (songIdsInOrder.isEmpty()) return
        val voted = _uiState.value.myVotedSongIds
        write {
            val plan = planVoteSelection(voted, songIdsInOrder, voted.size.toUInt(), false)
            var failed = 0
            for (songId in plan.toVote) {
                try {
                    service.vote(showId, songId)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: SetlistPredictionService.Unauthorized) {
                    _loginPrompt.value = true
                    return@write
                } catch (e: Exception) {
                    failed++
                    Log.w(TAG, "add_prediction_failed song=$songId", e)
                }
            }
            val notice = when {
                failed > 0 -> "${failed}曲の追加に失敗しました"
                plan.overflow > 0u -> "1公演${voteLimitPerTarget()}票までなので、${plan.overflow}曲は投票できませんでした"
                else -> null
            }
            loadPredictions(notice)
        }
    }

    /** 機械予測の曲を予想に入れる (格上げ)。失敗の扱いは [toggleVote] と同じ。 */
    fun promoteForecast(songId: String) = write {
        try {
            forecast.promote(songId)
            loadPredictions()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            fail(e)
        }
    }

    fun requestLogin() {
        _loginPrompt.value = true
    }

    fun dismissLoginPrompt() {
        _loginPrompt.value = false
    }

    private fun fail(e: Exception) {
        if (e is SetlistPredictionService.Unauthorized) {
            _loginPrompt.value = true
        } else {
            Log.w(TAG, "prediction_vote_failed show=$showId", e)
            _uiState.update { it.copy(errorMessage = e.message) }
        }
    }

    private fun write(block: suspend () -> Unit) {
        module.appScope.launch { block() }
    }

    companion object {
        private const val TAG = "SetlistPrediction"

        /** 公演ごとに 1 つ (`viewModel(key = "prediction_$showId", factory = factory(showId))`)。 */
        fun factory(showId: String): ViewModelProvider.Factory = viewModelFactory {
            initializer {
                SetlistPredictionViewModel(
                    checkNotNull(this[ViewModelProvider.AndroidViewModelFactory.APPLICATION_KEY]),
                    showId
                )
            }
        }
    }
}
