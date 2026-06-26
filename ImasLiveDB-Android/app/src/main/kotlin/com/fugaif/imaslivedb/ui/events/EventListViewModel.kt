package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.EventWithDate
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class YearGroup(
    val year: String,
    val events: List<EventWithDate>
)

data class EventListUiState(
    val isLoading: Boolean = true,
    val eventsWithDate: List<EventWithDate> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val selectedBrandId: String? = null,
    val hideStreaming: Boolean = false
) {
    val filteredEvents: List<EventWithDate>
        get() {
            var result = eventsWithDate
            if (selectedBrandId != null) {
                result = result.filter { it.event.brandId == selectedBrandId }
            }
            if (hideStreaming) {
                result = result.filter { !it.event.isStreaming }
            }
            return result
        }

    val groupedByYear: List<YearGroup>
        get() {
            val yearMap = mutableMapOf<String, MutableList<EventWithDate>>()
            for (ew in filteredEvents) {
                val year = if (ew.firstDate != null && ew.firstDate.length >= 4) {
                    ew.firstDate.take(4) + "年"
                } else {
                    "年度不明"
                }
                yearMap.getOrPut(year) { mutableListOf() }.add(ew)
            }
            val sorted = yearMap.keys.sortedWith { a, b ->
                when {
                    a == "年度不明" -> 1
                    b == "年度不明" -> -1
                    else -> b.compareTo(a)
                }
            }
            return sorted.map { year -> YearGroup(year = year, events = yearMap[year]!!) }
        }
}

class EventListViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(EventListUiState())
    val uiState: StateFlow<EventListUiState> = _uiState.asStateFlow()

    fun load(context: Context) {
        viewModelScope.launch {
            val module = AppModule.from(context)
            val events = module.eventRepository.fetchEventsWithFirstDate()
            val brands = module.database.brandDao().fetchBrands()
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                eventsWithDate = events,
                brands = brands
            )
        }
    }

    fun selectBrand(brandId: String?) {
        _uiState.value = _uiState.value.copy(selectedBrandId = brandId)
    }

    fun toggleHideStreaming() {
        _uiState.value = _uiState.value.copy(hideStreaming = !_uiState.value.hideStreaming)
    }
}
