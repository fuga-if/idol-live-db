package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.AllPerformerRow
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
            val setlist = module.database.setlistDao().fetchSetlist(showId)
            val allPerformers: List<AllPerformerRow> =
                module.database.setlistDao().fetchAllPerformers(showId)

            // Group performers by setlist item id
            val performersByItemId = allPerformers
                .groupBy { it.setlistItemId }
                .mapValues { (_, rows) ->
                    rows.map { row ->
                        PerformerRow(
                            id = row.castId,
                            name = row.name,
                            idolColor = row.idolColor,
                            idolName = row.idolName,
                            idolId = row.idolId
                        )
                    }
                }

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
