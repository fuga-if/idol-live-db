package com.fugaif.imaslivedb.ui.tags

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolTagRankRow(val idolId: String, val voteCount: Int, val idol: Idol?)

data class IdolTagDetailUiState(
    val isLoading: Boolean = true,
    val tag: CommunityApi.CommunityTag? = null,
    val idols: List<IdolTagRankRow> = emptyList(),
    val reportSubmitted: Boolean = false,
    val reportError: String? = null
)

/** アイドルタグ (idol_tag_master) 詳細。TagDetailViewModel (曲タグ) と同じ構成の別プール版。 */
class IdolTagDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(IdolTagDetailUiState())
    val uiState: StateFlow<IdolTagDetailUiState> = _uiState.asStateFlow()

    private var api: CommunityApi? = null
    private var appModule: AppModule? = null
    private var tagId: String? = null

    fun load(context: Context, tagId: String) {
        this.tagId = tagId
        val module = AppModule.from(context)
        appModule = module
        api = module.communityApi
        viewModelScope.launch { reload() }
    }

    private suspend fun reload() {
        val id = tagId ?: return
        val a = api ?: return
        val module = appModule ?: return
        _uiState.value = _uiState.value.copy(isLoading = true)
        val detail = runCatching { a.idolTagDetail(id) }.getOrNull()
        if (detail == null) {
            _uiState.value = _uiState.value.copy(isLoading = false)
            return
        }
        val idolRows = detail.idols.map { IdolTagRankRow(it.idolId, it.voteCount, module.idolRepository.fetchIdol(it.idolId)) }
        _uiState.value = _uiState.value.copy(isLoading = false, tag = detail.tag, idols = idolRows)
    }

    fun onTagUpdated(tag: CommunityApi.CommunityTag) {
        _uiState.value = _uiState.value.copy(tag = tag)
    }

    fun reportTag(reason: String? = null) {
        val id = tagId ?: return
        val a = api ?: return
        viewModelScope.launch {
            val ok = runCatching { a.reportIdolTagOption(id, reason) }.getOrDefault(false)
            _uiState.value = if (ok) {
                _uiState.value.copy(reportSubmitted = true, reportError = null)
            } else {
                _uiState.value.copy(reportError = "通報に失敗しました。しばらくしてからお試しください。")
            }
        }
    }

    fun clearReportState() {
        _uiState.value = _uiState.value.copy(reportSubmitted = false, reportError = null)
    }
}
