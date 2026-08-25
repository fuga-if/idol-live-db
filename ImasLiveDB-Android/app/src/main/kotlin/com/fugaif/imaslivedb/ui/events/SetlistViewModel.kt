package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.PerformerRow
import com.fugaif.imaslivedb.data.model.SetlistRow
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SetlistSection(
    val sectionName: String,
    val items: List<SetlistRow>
)

data class SetlistUiState(
    val isLoading: Boolean = true,
    val show: Show? = null,
    val brandId: String? = null,
    val setlist: List<SetlistRow> = emptyList(),
    val performersByItemId: Map<String, List<PerformerRow>> = emptyMap()
) {
    val sections: List<SetlistSection>
        get() {
            val result = mutableListOf<SetlistSection>()
            for (item in setlist) {
                val sectionName = item.section ?: "本編"
                if (result.lastOrNull()?.sectionName == sectionName) {
                    val last = result.last()
                    result[result.lastIndex] = last.copy(items = last.items + item)
                } else {
                    result.add(SetlistSection(sectionName = sectionName, items = listOf(item)))
                }
            }
            return result
        }
}

class SetlistViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SetlistUiState())
    val uiState: StateFlow<SetlistUiState> = _uiState.asStateFlow()

    fun load(context: Context, showId: String) {
        viewModelScope.launch {
            val module = AppModule.from(context)
            val show = module.eventRepository.fetchShow(showId)
            val brandId = show?.eventId?.let { module.eventRepository.fetchEvent(it)?.brandId }
            // 画面の 2 つの半分 (曲と出演者) は同じ所有者から読む。DAO を直接叩くと
            // どちらの経路がいつ更新されるかがリポジトリの外に散り、片方だけ古い値を
            // 表示する事故に戻る。
            val setlist = module.eventRepository.fetchSetlist(showId)
            // 曲ごとのグループ化と並びは共有コア (showSetlistPerformers) が持つ。
            val performersByItemId = module.eventRepository.fetchPerformersByItem(showId)

            _uiState.value = SetlistUiState(
                isLoading = false,
                show = show,
                brandId = brandId,
                setlist = setlist,
                performersByItemId = performersByItemId
            )
        }
    }
}
