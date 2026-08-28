package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 殿堂 1 行分。優勝した entity の表示情報はサーバから来ないので、
 * ここでローカル master から解決したものを [displayName] / [artworkUrl] に載せる
 * (未解決なら entityId をそのまま出すフォールバック)。
 */
data class HallOfFameRow(
    val result: CommunityApi.PollResult,
    val displayName: String,
    /** 曲お題のときだけ入るジャケ写 URL。アイドル/ユニットはモノグラムを使うので null。 */
    val artworkUrl: String? = null,
    /** アバターの色決定に使う seed / ブランド (アイドル・ユニットのみ)。 */
    val seed: String? = null,
    val brandId: String? = null
)

data class PollHallOfFameUiState(
    val rows: List<HallOfFameRow> = emptyList(),
    val isLoading: Boolean = true,
    val loadError: String? = null
)

/**
 * 殿堂 (終了お題の優勝者一覧)。iOS PollHallOfFameViewModel の移植。
 * iOS は名前解決を View 側に残しているが、Android は行の描画を軽く保つため
 * ここでまとめて解決してから UiState に載せる (他の一覧系 VM と同じ作り)。
 */
class PollHallOfFameViewModel(app: Application) : AndroidViewModel(app) {

    private val api = AppModule.from(app).communityApi
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val unitRepo = AppModule.from(app).unitRepository

    private val _uiState = MutableStateFlow(PollHallOfFameUiState())
    val uiState: StateFlow<PollHallOfFameUiState> = _uiState.asStateFlow()

    init { load() }

    fun load() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            val results = runCatching { api.pollResults() }.getOrNull()
            if (results == null) {
                _uiState.value = PollHallOfFameUiState(isLoading = false, loadError = "通信エラー")
                return@launch
            }
            _uiState.value = PollHallOfFameUiState(rows = results.map { resolve(it) }, isLoading = false)
        }
    }

    private suspend fun resolve(result: CommunityApi.PollResult): HallOfFameRow {
        val resolved = when (result.targetType) {
            "idol" -> idolRepo.fetchIdol(result.entityId)?.let {
                HallOfFameRow(result, it.name, seed = it.color, brandId = it.brandId)
            }
            "unit" -> unitRepo.fetchUnit(result.entityId)?.let {
                HallOfFameRow(result, it.displayName, seed = it.id, brandId = it.brandId)
            }
            else -> songRepo.fetchSong(result.entityId)?.let {
                HallOfFameRow(result, it.title, artworkUrl = it.artworkUrl)
            }
        }
        // ローカル master に無い ID (サーバ配信ラグ等) は名前を出せないので ID をそのまま見せる。
        return resolved ?: HallOfFameRow(result, result.entityId)
    }
}
