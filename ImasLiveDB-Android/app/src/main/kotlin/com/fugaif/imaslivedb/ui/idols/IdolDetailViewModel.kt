package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.CastShowRow
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.IdolPerformedSong
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import java.time.LocalDate
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolDetailUiState(
    val idol: Idol? = null,
    val brand: Brand? = null,
    val originalSongs: List<Song> = emptyList(),
    val performedSongs: List<IdolPerformedSong> = emptyList(),
    val unitsWithSongs: List<ImasUnit> = emptyList(),
    val unitsWithoutSongs: List<ImasUnit> = emptyList(),
    val castShows: List<CastShowRow> = emptyList(),
    val tags: List<CommunityApi.IdolTag> = emptyList(),
    val isLoading: Boolean = true
) {
    /** 出演履歴のうち今日以降で最も近い公演 (= 次の出演)。無ければ null。 */
    val nextShow: CastShowRow?
        get() {
            val today = LocalDate.now().toString()
            return castShows.filter { it.date >= today }.minByOrNull { it.date }
        }
}

class IdolDetailViewModel(app: Application, private val idolId: String) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).idolRepository
    private val songRepo = AppModule.from(app).songRepository
    private val api = AppModule.from(app).communityApi

    private val _uiState = MutableStateFlow(IdolDetailUiState())
    val uiState: StateFlow<IdolDetailUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val idol = repo.fetchIdol(idolId) ?: return@launch
            val brand = repo.fetchBrand(idol.brandId)
            val originalSongs = songRepo.fetchIdolSongs(idolId, "original")
            val performedSongs = repo.fetchIdolPerformedSongs(idolId)
            val units = repo.fetchIdolUnits(idolId)
            val unitIdsWithSongs = repo.fetchIdolUnitIdsWithSongs(idolId)
            val castShows = repo.fetchIdolShows(idolId)

            _uiState.value = IdolDetailUiState(
                idol = idol,
                brand = brand,
                originalSongs = originalSongs,
                performedSongs = performedSongs,
                unitsWithSongs = units.filter { it.id in unitIdsWithSongs },
                unitsWithoutSongs = units.filter { it.id !in unitIdsWithSongs },
                castShows = castShows,
                isLoading = false
            )
            loadTags()
        }
    }

    private suspend fun loadTags() {
        val tags = runCatching { api.idolTags(idolId) }.getOrDefault(emptyList())
        _uiState.value = _uiState.value.copy(tags = tags)
    }

    /** タグ投票のトグル (端末ベース)。完了後にタグを再取得。 */
    fun toggleTag(tag: CommunityApi.IdolTag) {
        viewModelScope.launch {
            runCatching {
                if (tag.mine) api.removeIdolTag(idolId, tag.id) else api.applyIdolTags(idolId, listOf(tag.id))
            }
            loadTags()
        }
    }

    /** タグ追加ピッカー (IdolTagPickerSheet) で新規タグを適用した後の再取得。 */
    fun onTagsApplied() {
        viewModelScope.launch { loadTags() }
    }

    class Factory(private val app: Application, private val idolId: String) :
        ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolDetailViewModel(app, idolId) as T
    }
}
