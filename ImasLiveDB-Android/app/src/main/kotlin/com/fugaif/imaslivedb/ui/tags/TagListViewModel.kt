package com.fugaif.imaslivedb.ui.tags

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class TagListUiState(
    val isLoading: Boolean = true,
    val tags: List<CommunityApi.CommunityTag> = emptyList(),
    val category: String = "",
    val sort: String = "popular"
) {
    val activeFilterCount: Int get() = if (category.isEmpty()) 0 else 1
}

/** タグ一覧画面 (iOS TagListView の移植)。人気/新着/名前順 + カテゴリ絞り込み。 */
class TagListViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(TagListUiState())
    val uiState: StateFlow<TagListUiState> = _uiState.asStateFlow()

    private var api: CommunityApi? = null
    private var loadJob: Job? = null

    fun init(context: Context) {
        if (api != null) return
        api = AppModule.from(context).communityApi
        load()
    }

    fun setCategory(category: String) {
        _uiState.value = _uiState.value.copy(category = category)
        load()
    }

    fun setSort(sort: String) {
        _uiState.value = _uiState.value.copy(sort = sort)
        load()
    }

    /** タグ作成シートで新規作成した直後、リストの先頭に即時反映する。 */
    fun prependCreatedTag(tag: CommunityApi.CommunityTag) {
        val current = _uiState.value.tags
        if (current.any { it.id == tag.id }) return
        _uiState.value = _uiState.value.copy(tags = listOf(tag) + current)
    }

    private fun load() {
        val a = api ?: return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            val state = _uiState.value
            val tags = runCatching { a.tags(category = state.category, sort = state.sort) }.getOrDefault(emptyList())
            _uiState.value = _uiState.value.copy(isLoading = false, tags = tags)
        }
    }
}
