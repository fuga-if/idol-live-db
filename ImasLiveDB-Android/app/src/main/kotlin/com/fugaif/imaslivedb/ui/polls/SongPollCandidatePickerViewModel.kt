package com.fugaif.imaslivedb.ui.polls

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SongPickerUiState(
    val songs: List<SongWithArtists> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val isLoading: Boolean = true
)

/** お題候補用の曲検索 (SongPollCandidatePicker が使う軽量 ViewModel)。iOS SongSearchPickerView の移植。 */
class SongPollCandidatePickerViewModel(app: Application) : AndroidViewModel(app) {
    private val songRepo = AppModule.from(app).songRepository
    private val statsRepo = AppModule.from(app).statsRepository
    private val communityApi = AppModule.from(app).communityApi

    private val _uiState = MutableStateFlow(SongPickerUiState())
    val uiState: StateFlow<SongPickerUiState> = _uiState.asStateFlow()

    private var searchJob: Job? = null

    init {
        viewModelScope.launch {
            val brands = runCatching { statsRepo.fetchBrands() }.getOrDefault(emptyList())
            _uiState.value = _uiState.value.copy(brands = brands)
        }
        search()
    }

    fun search(
        title: String = "",
        songwriter: String = "",
        brandId: String? = null,
        songType: String? = null,
        tagIds: List<String> = emptyList()
    ) {
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            if (title.isNotEmpty() || songwriter.isNotEmpty()) delay(200)

            val tagFilterSongIds = if (tagIds.isNotEmpty()) {
                val sets = tagIds.map { id ->
                    runCatching { communityApi.tagDetail(id) }
                        .getOrNull()?.songs?.map { it.songId }?.toSet() ?: emptySet()
                }
                sets.reduce { acc, s -> acc intersect s }
            } else {
                null
            }

            val filter = SongSearchFilter(
                // このピッカーのブランド選択は単一。フィルタ側が集合を取るので 0/1 要素で渡す。
                brandIds = setOfNotNull(brandId),
                title = title.ifEmpty { null },
                songwriter = songwriter.ifEmpty { null },
                songType = songType
            )
            val songs = runCatching {
                songRepo.fetchSongs(filter, SongSortOrder.TITLE_KANA, null, tagFilterSongIds)
            }.getOrDefault(emptyList())
            _uiState.value = _uiState.value.copy(songs = songs, isLoading = false)
        }
    }
}
