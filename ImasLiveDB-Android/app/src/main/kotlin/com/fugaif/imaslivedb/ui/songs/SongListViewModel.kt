package com.fugaif.imaslivedb.ui.songs

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
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
    val sortOrder: SongSortOrder = SongSortOrder.TITLE_KANA
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
            val songs = AppModule.from(ctx).songRepository.fetchSongs(
                filter = effectiveFilter,
                sortOrder = state.sortOrder
            )
            _uiState.value = _uiState.value.copy(isLoading = false, songs = songs)
        }
    }
}
