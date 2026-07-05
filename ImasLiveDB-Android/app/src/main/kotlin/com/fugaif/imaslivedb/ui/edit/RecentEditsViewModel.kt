package com.fugaif.imaslivedb.ui.edit

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.auth.AuthService
import com.fugaif.imaslivedb.data.edit.EditApi
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class RecentEditsUiState(
    val entries: List<EditApi.EditFeedEntry> = emptyList(),
    val recordTitles: Map<Int, String> = emptyMap(),
    /** batchId -> (gooded, count) の楽観更新オーバーレイ。未操作の行はここに無く entry の値をそのまま使う。 */
    val goodOverrides: Map<Int, Pair<Boolean, Int>> = emptyMap(),
    val page: Int = 1,
    val hasMore: Boolean = true,
    val isLoading: Boolean = false,
    val isLoadingMore: Boolean = false,
    val errorMessage: String? = null,
    val mineOnly: Boolean = false,
    val showLoginPrompt: Boolean = false
)

/**
 * 「最近の編集」フィード (`GET /edits` / `GET /me/edits`) + Good トグルの ViewModel。
 * iOS `RecentEditsView` の状態管理を移植。
 */
class RecentEditsViewModel(app: Application) : AndroidViewModel(app) {
    private val editApi = AppModule.from(app).editApi
    private val editFeedRepository = AppModule.from(app).editFeedRepository
    private val authService: AuthService = AppModule.from(app).authService

    private val _uiState = MutableStateFlow(RecentEditsUiState())
    val uiState: StateFlow<RecentEditsUiState> = _uiState.asStateFlow()

    private val limit = 20

    init {
        viewModelScope.launch { reload() }
    }

    fun setMineOnly(mine: Boolean) {
        if (_uiState.value.mineOnly == mine) return
        _uiState.value = _uiState.value.copy(mineOnly = mine)
        viewModelScope.launch { reload() }
    }

    fun refresh() {
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        val mine = _uiState.value.mineOnly
        _uiState.value = _uiState.value.copy(isLoading = true, errorMessage = null)
        try {
            val page = editApi.fetchEdits(page = 1, limit = limit, mine = mine)
            val titles = resolveTitles(page.items)
            _uiState.value = _uiState.value.copy(
                entries = page.items,
                recordTitles = titles,
                goodOverrides = emptyMap(),
                page = 1,
                hasMore = page.items.size >= limit,
                isLoading = false
            )
        } catch (e: Exception) {
            _uiState.value = _uiState.value.copy(isLoading = false, errorMessage = errorText(e))
        }
    }

    fun loadMore() {
        val state = _uiState.value
        if (!state.hasMore || state.isLoadingMore || state.isLoading) return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingMore = true)
            try {
                val next = state.page + 1
                val page = editApi.fetchEdits(page = next, limit = limit, mine = state.mineOnly)
                val existingIds = state.entries.map { it.batchId }.toSet()
                val fresh = page.items.filter { it.batchId !in existingIds }
                val newTitles = resolveTitles(fresh)
                _uiState.value = _uiState.value.copy(
                    entries = state.entries + fresh,
                    recordTitles = state.recordTitles + newTitles,
                    page = next,
                    hasMore = page.items.size >= limit,
                    isLoadingMore = false
                )
            } catch (e: Exception) {
                _uiState.value = _uiState.value.copy(isLoadingMore = false, hasMore = false)
            }
        }
    }

    /** 現在の (gooded, count) を返す (楽観更新オーバーレイ優先)。 */
    fun goodState(entry: EditApi.EditFeedEntry): Pair<Boolean, Int> =
        _uiState.value.goodOverrides[entry.batchId] ?: (entry.hasUserGood to entry.goodCount)

    fun toggleGood(entry: EditApi.EditFeedEntry) {
        if (!authService.state.value.isSignedIn) {
            _uiState.value = _uiState.value.copy(showLoginPrompt = true)
            return
        }
        if (entry.isOwnEdit) return

        val current = goodState(entry)
        val newGooded = !current.first
        val newCount = (current.second + if (newGooded) 1 else -1).coerceAtLeast(0)
        _uiState.value = _uiState.value.copy(
            goodOverrides = _uiState.value.goodOverrides + (entry.batchId to (newGooded to newCount))
        )
        viewModelScope.launch {
            try {
                val result = if (newGooded) editApi.good(entry.batchId) else editApi.ungood(entry.batchId)
                _uiState.value = _uiState.value.copy(
                    goodOverrides = _uiState.value.goodOverrides + (entry.batchId to (result.gooded to result.goodCount))
                )
            } catch (e: Exception) {
                // ロールバック。
                _uiState.value = _uiState.value.copy(
                    goodOverrides = _uiState.value.goodOverrides + (entry.batchId to current)
                )
                if (e is EditApi.ApiException.NotAuthorized) {
                    _uiState.value = _uiState.value.copy(showLoginPrompt = true)
                } else {
                    _uiState.value = _uiState.value.copy(errorMessage = errorText(e))
                }
            }
        }
    }

    fun clearError() {
        _uiState.value = _uiState.value.copy(errorMessage = null)
    }

    fun dismissLoginPrompt() {
        _uiState.value = _uiState.value.copy(showLoginPrompt = false)
    }

    fun requestLogin() {
        _uiState.value = _uiState.value.copy(showLoginPrompt = true)
    }

    private suspend fun resolveTitles(items: List<EditApi.EditFeedEntry>): Map<Int, String> {
        val map = mutableMapOf<Int, String>()
        for (e in items) {
            val title = runCatching { editFeedRepository.recordTitle(e.recordType, e.recordName) }.getOrNull()
            if (!title.isNullOrEmpty()) map[e.batchId] = title
        }
        return map
    }

    private fun errorText(e: Exception): String = when (e) {
        is EditApi.ApiException.RateLimited -> "操作が多すぎます。しばらく待ってからお試しください。"
        is EditApi.ApiException.NotAuthorized -> "ログインが必要です。"
        is EditApi.ApiException.Banned -> "この操作は利用できません。"
        else -> "読み込みに失敗しました。"
    }
}
