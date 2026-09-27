package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.EventAttendance
import com.fugaif.imaslivedb.data.model.EventStats
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.EventCostumesRecord
import uniffi.imas_core.EventHeroRecord
import uniffi.imas_core.TicketSale

data class EventDetailUiState(
    val isLoading: Boolean = true,
    val eventName: String = "",
    val shows: List<Show> = emptyList(),
    val stats: EventStats? = null,
    val attendance: EventAttendance? = null,
    val isJoint: Boolean = false,
    /** ブランドのテーマシード色 (hex)。合同ライブは中立にするため画面側で isJoint と合わせて使う。 */
    val brandColorHex: String? = null,
    /** 主ブランドの ID。画面の部品の `brand` に渡す (部品がマスタの色へ引く)。 */
    val brandId: String? = null,
    val brandShortName: String? = null,
    /** そのイベントのチケット受付一覧。段階・並びはコアが確定させた順のまま。 */
    val ticketSales: List<TicketSale> = emptyList(),
    val ticketUrl: String? = null,
    /** ヒーロー (開催期間 ・ 会場・今後か・参加の札)。組み立ても判定もコア。 */
    val hero: EventHeroRecord? = null,
    /** このイベントで着られた衣装 (共通・個別)。分け方も並びも共有コア。 */
    val costumes: EventCostumesRecord? = null
) {
    /** 最初の公演日が今日以降か (チケット情報の節を出すか)。 */
    val isFutureEvent: Boolean get() = hero?.isUpcoming == true
}

class EventDetailViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(EventDetailUiState())
    val uiState: StateFlow<EventDetailUiState> = _uiState.asStateFlow()

    private var heroRequest: Triple<String, Set<String>, Boolean>? = null

    /**
     * ヒーローを引き直す (参加マークが変わったとき)。参加の札はマークに依るので、
     * 画面が持つ今のマークを渡す。
     */
    fun refreshHero(context: Context, eventId: String, attendedShowIds: Set<String>, eventMarked: Boolean) {
        heroRequest = Triple(eventId, attendedShowIds, eventMarked)
        viewModelScope.launch {
            val hero = AppModule.from(context).eventRepository.fetchEventHero(eventId, attendedShowIds, eventMarked)
            if (heroRequest == Triple(eventId, attendedShowIds, eventMarked)) {
                _uiState.value = _uiState.value.copy(hero = hero)
            }
        }
    }

    fun load(context: Context, eventId: String) {
        viewModelScope.launch {
            val module = AppModule.from(context)
            val repo = module.eventRepository
            val eventInfo = repo.fetchEventInfo(eventId)
            val event = eventInfo?.event
            val shows = repo.fetchShows(eventId)
            val stats = repo.fetchEventStats(eventId)
            val attendance = repo.fetchEventAttendance(eventId)
            val brand = event?.brandId?.let { repo.fetchBrand(it) }
            val ticketSales = repo.fetchTicketSales(eventId)
            val costumes = repo.fetchEventCostumes(eventId)
            _uiState.value = EventDetailUiState(
                isLoading = false,
                eventName = event?.name ?: "",
                shows = shows,
                stats = stats,
                attendance = attendance,
                isJoint = eventInfo?.isJoint == true,
                brandColorHex = brand?.color,
                brandId = brand?.id,
                brandShortName = brand?.shortName,
                ticketSales = ticketSales,
                ticketUrl = event?.ticketUrl?.takeIf { it.isNotBlank() },
                // ヒーローは参加マークに依るので refreshHero が持つ。読み直しで消さない。
                hero = _uiState.value.hero,
                costumes = costumes
            )
        }
    }
}
