package com.fugaif.imaslivedb.ui.songs

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SongListUiState(
    val isLoading: Boolean = true,
    val songs: List<SongWithArtists> = emptyList(),
    val searchText: String = "",
    val filter: SongSearchFilter = SongSearchFilter(),
    val sortOrder: SongSortOrder = SongSortOrder.TITLE_KANA,
    // タグ絞り込み (TagFilterSheet) で選択中のタグ。複数選択時は AND (全タグを含む曲) で絞る。
    val selectedTags: List<CommunityApi.CommunityTag> = emptyList()
) {
    val activeFilterCount: Int get() = filter.activeFilterCount
}

class SongListViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SongListUiState())
    val uiState: StateFlow<SongListUiState> = _uiState.asStateFlow()

    private var loadJob: Job? = null
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        loadSongs()
    }

    fun setSearchText(text: String) {
        _uiState.value = _uiState.value.copy(searchText = text)
        loadSongs()
    }

    fun applyFilter(filter: SongSearchFilter, sortOrder: SongSortOrder) {
        _uiState.value = _uiState.value.copy(filter = filter, sortOrder = sortOrder)
        loadSongs()
    }

    fun applyTagFilter(tags: List<CommunityApi.CommunityTag>) {
        _uiState.value = _uiState.value.copy(selectedTags = tags)
        loadSongs()
    }

    private fun loadSongs() {
        val ctx = appContext ?: return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            val state = _uiState.value
            val effectiveFilter = if (state.searchText.isNotEmpty()) {
                state.filter.copy(title = state.searchText)
            } else {
                state.filter
            }
            // タグ絞り込み: Worker D1 (コミュニティタグ) は端末外データなので、選択中タグそれぞれの
            // 詳細 (付いた曲の song_id 一覧) を取得して AND (積集合) を取る。
            val tagFilterSongIds = if (state.selectedTags.isNotEmpty()) {
                val api = AppModule.from(ctx).communityApi
                val sets = state.selectedTags.map { tag ->
                    runCatching { api.tagDetail(tag.id) }.getOrNull()?.songs?.map { it.songId }?.toSet() ?: emptySet()
                }
                sets.reduce { acc, s -> acc intersect s }
            } else {
                null
            }
            val songs = AppModule.from(ctx).songRepository.fetchSongs(
                filter = effectiveFilter,
                sortOrder = state.sortOrder,
                tagFilterSongIds = tagFilterSongIds
            )
            _uiState.value = _uiState.value.copy(isLoading = false, songs = songs)
        }
    }
}
