package com.fugaif.imaslivedb.ui.search

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.SearchResults
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SearchUiState(
    val query: String = "",
    val results: SearchResults = SearchResults(emptyList(), emptyList(), emptyList()),
    val isSearching: Boolean = false
)

class SearchViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).searchRepository

    private val _uiState = MutableStateFlow(SearchUiState())
    val uiState: StateFlow<SearchUiState> = _uiState.asStateFlow()

    private var searchJob: Job? = null

    fun setQuery(query: String) {
        _uiState.value = _uiState.value.copy(query = query)
        searchJob?.cancel()
        if (query.isBlank()) {
            _uiState.value = _uiState.value.copy(
                results = SearchResults(emptyList(), emptyList(), emptyList()),
                isSearching = false
            )
            return
        }
        searchJob = viewModelScope.launch {
            delay(300L) // debounce
            _uiState.value = _uiState.value.copy(isSearching = true)
            val results = repo.search(query)
            _uiState.value = _uiState.value.copy(results = results, isSearching = false)
        }
    }
}
