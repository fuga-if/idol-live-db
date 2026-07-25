package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate

data class YearGroup(
    val year: String,
    val events: List<EventWithDateRange>
)

data class EventListUiState(
    val isLoading: Boolean = true,
    val eventsWithDate: List<EventWithDateRange> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val selectedBrandId: String? = null,
    val hideStreaming: Boolean = false,
    /** 0 = 今後の予定 / 1 = 開催済み */
    val timeFilter: Int = 0,
    /** 会場絞り込み (venue_id。null = 絞り込みなし)。名前でなく ID なので改名しても外れない。 */
    val venue: String? = null,
    /** `venue` で公演があったイベントの id 集合 (会場は show 単位なので逆引きして持つ)。 */
    val venueEventIds: Set<String> = emptySet(),
    /** 会場マスタ (ピッカー候補・当時名/キャパの解決)。 */
    val venueDirectory: VenueDirectory = VenueDirectory.EMPTY,
    val todayKey: String = LocalDate.now().toString()
) {
    val filteredEvents: List<EventWithDateRange>
        get() {
            var result = eventsWithDate.filter { it.isUpcoming(todayKey) == (timeFilter == 0) }
            if (selectedBrandId != null) {
                result = result.filter { it.event.brandId == selectedBrandId || it.event.jointBrandIdList.contains(selectedBrandId) }
            }
            if (hideStreaming) {
                result = result.filter { !it.event.isStreaming }
            }
            if (venue != null) {
                result = result.filter { venueEventIds.contains(it.event.id) }
            }
            return result
        }

    val groupedByYear: List<YearGroup>
        get() {
            val yearMap = mutableMapOf<String, MutableList<EventWithDateRange>>()
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
                    timeFilter == 0 -> a.compareTo(b)
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
            val directory = module.eventRepository.fetchVenueDirectory()
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                eventsWithDate = events,
                brands = brands,
                venueDirectory = directory
            )
        }
    }

    fun selectBrand(brandId: String?) {
        _uiState.value = _uiState.value.copy(selectedBrandId = brandId)
    }

    fun toggleHideStreaming() {
        _uiState.value = _uiState.value.copy(hideStreaming = !_uiState.value.hideStreaming)
    }

    fun selectTimeFilter(index: Int) {
        _uiState.value = _uiState.value.copy(timeFilter = index)
    }

    /**
     * 会場で絞り込む (null で解除)。
     * 会場は show 単位なので、絞り込みに使う event_id 集合をここで解決して state に載せる。
     */
    fun selectVenue(context: Context, venue: String?) {
        if (venue == null) {
            _uiState.value = _uiState.value.copy(venue = null, venueEventIds = emptySet())
            return
        }
        viewModelScope.launch {
            val ids = AppModule.from(context).eventRepository.fetchEventIdsAtVenue(venue)
            _uiState.value = _uiState.value.copy(venue = venue, venueEventIds = ids)
        }
    }
}
