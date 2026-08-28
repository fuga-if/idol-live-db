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
import com.fugaif.imaslivedb.ui.components.searchFiltered

data class TagListUiState(
    val isLoading: Boolean = true,
    /** API から返ってきたそのままのタグ (名前絞り込み前)。 */
    val tags: List<CommunityApi.CommunityTag> = emptyList(),
    val category: String = "",
    val sort: String = "popular",
    /** 一覧を名前で絞り込む語。API ではなく手元で絞る (打鍵ごとに D1 を叩かない)。 */
    val nameFilter: String = ""
) {
    /**
     * 名前絞り込み適用後のタグ。名前・説明の部分一致で絞る (iOS TagListView.filteredTags と同じ)。
     * 人気順の順位表示は絞り込み後の並びに振り直る — 元の順位を残すと歯抜けになって読めない。
     */
    val visibleTags: List<CommunityApi.CommunityTag>
        get() {
            // 照合はコア (`domain/text_search_index.rs`) に一任する。タグ名はユーザーが
            // 打つ自由文字列なので表記の揺れが大きく、他の一覧と同じく かなを畳む。
            // API が返す件数は高々数百なので、索引を使い捨てても割に合う。
            return searchFiltered(tags, nameFilter) { listOf(it.name, it.description) }
        }

    val activeFilterCount: Int
        get() = (if (category.isEmpty()) 0 else 1) + (if (nameFilter.isEmpty()) 0 else 1)
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

    /**
     * 名前絞り込み。API を叩き直さず手元の [TagListUiState.tags] を絞るだけなので
     * 打鍵ごとに呼んでよい (D1 の読み取りを打鍵数で消費しない)。
     */
    fun setNameFilter(text: String) {
        _uiState.value = _uiState.value.copy(nameFilter = text)
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
