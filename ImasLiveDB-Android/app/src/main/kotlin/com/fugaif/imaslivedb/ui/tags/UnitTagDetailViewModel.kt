package com.fugaif.imaslivedb.ui.tags

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class UnitTagRankRow(val unitId: String, val voteCount: Int, val unit: ImasUnit?)

data class UnitTagDetailUiState(
    val isLoading: Boolean = true,
    val tag: CommunityApi.CommunityTag? = null,
    val units: List<UnitTagRankRow> = emptyList(),
    val reportSubmitted: Boolean = false,
    val reportError: String? = null
)

/** ユニットタグ (unit_tag_master) 詳細。IdolTagDetailViewModel と同じ構成の別プール版。 */
class UnitTagDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(UnitTagDetailUiState())
    val uiState: StateFlow<UnitTagDetailUiState> = _uiState.asStateFlow()

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
        val detail = runCatching { a.unitTagDetail(id) }.getOrNull()
        if (detail == null) {
            _uiState.value = _uiState.value.copy(isLoading = false)
            return
        }
        // ランキングは票数降順でサーバが返すので、ここでは並べ替えず ID → ユニットの解決だけする。
        val unitsById = module.unitRepository
            .fetchUnitsByIds(detail.units.map { it.unitId })
            .associateBy { it.id }
        val unitRows = detail.units.map { UnitTagRankRow(it.unitId, it.voteCount, unitsById[it.unitId]) }
        _uiState.value = _uiState.value.copy(isLoading = false, tag = detail.tag, units = unitRows)
    }

    fun onTagUpdated(tag: CommunityApi.CommunityTag) {
        _uiState.value = _uiState.value.copy(tag = tag)
    }

    fun reportTag(reason: String? = null) {
        val id = tagId ?: return
        val a = api ?: return
        viewModelScope.launch {
            val ok = runCatching { a.reportUnitTagOption(id, reason) }.getOrDefault(false)
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
