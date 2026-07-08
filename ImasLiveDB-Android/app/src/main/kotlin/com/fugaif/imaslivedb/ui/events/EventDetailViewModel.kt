package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.format.DateTimeFormatter

data class EventDetailUiState(
    val isLoading: Boolean = true,
    val eventName: String = "",
    val shows: List<Show> = emptyList(),
    val stats: EventStats? = null,
    val attendance: EventAttendance? = null,
    val isJoint: Boolean = false,
    /** ブランドのテーマシード色 (hex)。合同ライブは中立にするため画面側で isJoint と合わせて使う。 */
    val brandColorHex: String? = null,
    val brandShortName: String? = null,
    val ticketDeadline: String? = null,
    val ticketLotteryDate: String? = null,
    val ticketUrl: String? = null
) {
    /** 開催日レンジ ・ 会場 (ヒーローのサブ行)。 */
    val heroSub: String
        get() {
            val dates = shows.map { it.date }.filter { it.isNotEmpty() }
            val datePart = if (dates.isNotEmpty()) {
                if (dates.first() == dates.last()) dates.first() else "${dates.first()}–${dates.last()}"
            } else null
            val venue = shows.mapNotNull { it.venue }.distinct().sorted().firstOrNull()
            return listOfNotNull(datePart, venue).joinToString(" ・ ")
        }

    /** 最初の公演日が今日以降かどうか (チケット情報セクションの表示判定・参加予定チップに使う)。 */
    val isFutureEvent: Boolean
        get() {
            val firstDate = shows.firstOrNull()?.date ?: return false
            val today = LocalDate.now().format(DateTimeFormatter.ISO_LOCAL_DATE)
            return firstDate >= today
        }
}

class EventDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(EventDetailUiState())
    val uiState: StateFlow<EventDetailUiState> = _uiState.asStateFlow()

    fun load(context: Context, eventId: String) {
        viewModelScope.launch {
            val module = AppModule.from(context)
            val repo = module.eventRepository
            val event = repo.fetchEvent(eventId)
            val shows = repo.fetchShows(eventId)
            val stats = repo.fetchEventStats(eventId)
            val castRows = repo.fetchEventShowCast(eventId)
            val brandRoster = event?.brandId?.let { repo.fetchBrandRoster(it) } ?: emptyList()
            val brand = event?.brandId?.let { repo.fetchBrand(it) }
            _uiState.value = EventDetailUiState(
                isLoading = false,
                eventName = event?.name ?: "",
                shows = shows,
                stats = stats,
                attendance = EventAttendance.build(shows, brandRoster, castRows),
                isJoint = !event?.jointBrandIds.isNullOrBlank(),
                brandColorHex = brand?.color,
                brandShortName = brand?.shortName,
                ticketDeadline = event?.ticketDeadline?.takeIf { it.isNotBlank() },
                ticketLotteryDate = event?.ticketLotteryDate?.takeIf { it.isNotBlank() },
                ticketUrl = event?.ticketUrl?.takeIf { it.isNotBlank() }
            )
        }
    }
}
