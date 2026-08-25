package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.EventFilterCriteria

data class EventListUiState(
    val isLoading: Boolean = true,
    val brands: List<Brand> = emptyList(),
    val selectedBrandId: String? = null,
    val hideStreaming: Boolean = false,
    /** 0 = 今後の予定 / 1 = 開催済み */
    val timeFilter: Int = 0,
    /** 会場絞り込み (venue_id。null = 絞り込みなし)。名前でなく ID なので改名しても外れない。 */
    val venue: String? = null,
    /** 会場マスタ (ピッカー候補・当時名/キャパの解決)。 */
    val venueDirectory: VenueDirectory = VenueDirectory.EMPTY,
    /**
     * 絞り込み + 年グルーピング済みの表示データ。
     *
     * かつては UiState の getter で毎回計算していたが、判定本体が FFI (共有コア) に移った
     * いま同じ形にすると再構成のたびに境界を跨ぐ。VM が [EventListViewModel.rebuild] で
     * 1 回だけ計算して載せる (iOS EventListViewModel の groupedByYear / filteredCount と同じ形)。
     */
    val groupedByYear: List<YearGroup> = emptyList(),
    val filteredCount: Int = 0
)

class EventListViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(EventListUiState())
    val uiState: StateFlow<EventListUiState> = _uiState.asStateFlow()

    // 絞り込みの入力。画面には出さないので UiState には載せない
    // (載せると Compose 側から母集合を触れてしまい、行ごとの再計算を招く)。
    private var eventsWithDate: List<EventWithDateRange> = emptyList()
    private var venueEventIds: Set<String> = emptySet()

    // 常に最新の 1 本だけ走らせる。連打で古い結果があとから届いて表示が巻き戻るのを防ぐ。
    private var rebuildJob: Job? = null

    // 母集合を読み終えたか。[rebuild] の終端で isLoading を降ろしてよいかの判定に使う。
    // 読込前に絞り込みを触られると母集合が空のまま rebuild が走るので、その結果で
    // 「該当なし」を確定させてはいけない。
    private var sourceLoaded = false

    fun load(context: Context) {
        viewModelScope.launch {
            val module = AppModule.from(context)
            eventsWithDate = module.eventRepository.fetchEventsWithFirstDate()
            val brands = module.database.brandDao().fetchBrands()
            val directory = module.eventRepository.fetchVenueDirectory()
            sourceLoaded = true
            // isLoading はここでは降ろさない。groupedByYear の算出は下の scheduleRebuild が
            // 別コルーチン + Dispatchers.Default で行うため、先に降ろすと
            // (isLoading=false, groupedByYear=[]) という中間状態が必ず一度 publish され、
            // 画面がスケルトンでなく空状態 (「今後の予定はありません」) を描いてしまう。
            _uiState.value = _uiState.value.copy(
                brands = brands,
                venueDirectory = directory
            )
            // 読込中に絞り込みを触られていたら、そちらの (母集合が空のまま走った) 再構築を
            // 捨てて最新条件で組み直す。
            scheduleRebuild()
        }
    }

    fun selectBrand(brandId: String?) {
        _uiState.value = _uiState.value.copy(selectedBrandId = brandId)
        scheduleRebuild()
    }

    fun toggleHideStreaming() {
        _uiState.value = _uiState.value.copy(hideStreaming = !_uiState.value.hideStreaming)
        scheduleRebuild()
    }

    fun selectTimeFilter(index: Int) {
        _uiState.value = _uiState.value.copy(timeFilter = index)
        scheduleRebuild()
    }

    /**
     * 会場で絞り込む (null で解除)。
     * 会場は show 単位なので、絞り込みに使う event_id 集合をここで解決してから再構築する。
     */
    fun selectVenue(context: Context, venue: String?) {
        rebuildJob?.cancel()
        rebuildJob = viewModelScope.launch {
            venueEventIds = if (venue == null) {
                emptySet()
            } else {
                AppModule.from(context).eventRepository.fetchEventIdsAtVenue(venue)
            }
            _uiState.value = _uiState.value.copy(venue = venue)
            rebuild()
        }
    }

    private fun scheduleRebuild() {
        rebuildJob?.cancel()
        rebuildJob = viewModelScope.launch { rebuild() }
    }

    /**
     * 現在の絞り込み条件で表示データを組み直す (iOS EventListViewModel.rebuild と同じ責務)。
     *
     * 絞り込みと年グルーピングは共有コアの純粋関数。要素数によらず 1 回ずつしか跨がない。
     */
    private suspend fun rebuild() {
        val state = _uiState.value
        val source = eventsWithDate
        val criteria = EventFilterCriteria(
            // Android の UI はブランド単一選択。コア側は複数 OR なので 0/1 要素で渡す。
            selectedBrandIds = listOfNotNull(state.selectedBrandId),
            // kind 絞り込みの UI が無いので除外なし。
            excludedKinds = emptyList(),
            // 検索・参加・マーク絞り込みはライブ一覧に無い (検索は専用画面が持つ)。
            searchText = "",
            attendanceFilter = "all",
            attendedEventIds = emptyList(),
            requireFavorite = false,
            favoriteIds = emptyList(),
            requireNote = false,
            noteIds = emptyList(),
            // コアはこの文字列を on/off 判定にしか使わないので、会場名でなく venue_id を渡してよい。
            venue = state.venue.orEmpty(),
            venueEventIds = venueEventIds.toList()
        )
        val groups = withContext(Dispatchers.Default) {
            // 純粋関数だが FFI は呼び元スレッドをブロックするので UI スレッドから外す。
            var filtered = filterEvents(source, criteria)
            if (state.hideStreaming) {
                // events.is_streaming は互換のため残っている legacy 列で、コアの criteria にも
                // iOS の UI にも対応する軸が無い ("配信を除く" は Android だけのチップ)。
                // チップの意味を変えないため Kotlin 側の後段フィルタとして残す。
                filtered = filtered.filter { !it.event.isStreaming }
            }
            // 公演日との比較なので JST 固定 (端末ローカルだと海外で 1 日ずれる)。
            groupEventsByYear(filtered, upcoming = state.timeFilter == 0, todayKey = JstDay.today())
        }
        _uiState.value = _uiState.value.copy(
            groupedByYear = groups,
            filteredCount = groups.sumOf { it.events.size },
            // 表示データと同じ copy で降ろすことで、スケルトン→一覧の遷移を原子的にする。
            // 母集合の読込前に走った rebuild では降ろさない (空状態の誤表示になるため)。
            isLoading = !sourceLoaded
        )
    }
}
