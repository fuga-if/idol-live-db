package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.EventCastRow
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class EventDetailUiState(
    val isLoading: Boolean = true,
    val eventName: String = "",
    val brandId: String? = null,
    val shows: List<Show> = emptyList(),
    val stats: EventStats? = null,
    val castMembers: List<EventCastRow> = emptyList()
)

class EventDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(EventDetailUiState())
    val uiState: StateFlow<EventDetailUiState> = _uiState.asStateFlow()

    fun load(context: Context, eventId: String) {
        viewModelScope.launch {
            val module = AppModule.from(context)
            val event = module.eventRepository.fetchEvent(eventId)
            val shows = module.eventRepository.fetchShows(eventId)
            val stats = module.eventRepository.fetchEventStats(eventId)
            val castMembers = module.eventRepository.fetchEventCastMembers(eventId)
            _uiState.value = EventDetailUiState(
                isLoading = false,
                eventName = event?.name ?: "",
                brandId = event?.brandId,
                shows = shows,
                stats = stats,
                castMembers = castMembers
            )
        }
    }
}
