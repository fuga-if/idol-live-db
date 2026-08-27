package com.fugaif.imaslivedb.ui.events

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.data.model.VenueDirectory
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import uniffi.imas_core.EventFilterCriteria

data class EventListUiState(
    val isLoading: Boolean = true,
    val brands: List<Brand> = emptyList(),
    /** 空 = 全ブランド。合同ライブは joint_brand_ids 側の一致でも残る (判定はコア)。 */
    val selectedBrandIds: Set<String> = emptySet(),
    /** 一覧から除外する events.kind。空 = 除外なし (全種別表示)。 */
    val excludedKinds: Set<String> = emptySet(),
    /** "all" / "attended" / "not_attended"。 */
    val attendanceFilter: String = "all",
    val requireFavorite: Boolean = false,
    val requireNote: Boolean = false,
    /**
     * 公演がまだ 1 つも登録されていないライブを一覧に出すか。
     * 既定 OFF は iOS (`events_show_empty`) と同じ。日付が無いイベントは「年度不明」に
     * まとめて積まれるだけで読めないので、既定では隠す。
     */
    val showEmptyEvents: Boolean = false,
    val hideStreaming: Boolean = false,
    /** 0 = 今後の予定 / 1 = 開催済み */
    val timeFilter: Int = 0,
    /** 会場絞り込み (venue_id。null = 絞り込みなし)。名前でなく ID なので改名しても外れない。 */
    val venue: String? = null,
    /** 会場マスタ (ピッカー候補・当時名/キャパの解決)。 */
    val venueDirectory: VenueDirectory = VenueDirectory.EMPTY,
    /** 入力欄に出ている検索語 (打鍵がそのまま入る)。 */
    val searchText: String = "",
    /**
     * 実際に絞り込みへ使う検索語。[searchText] が落ち着いてから反映する。
     *
     * 日本語 IME の変換中は 1 打鍵ごとに未確定文字が差し替わり、そのたびに一覧が
     * 「全件 ⇄ 0 件 ⇄ 数件」と作り直される。年グループ (見出し + 行) を伴うこの一覧は
     * その振動で描画が破綻するので、変換が落ち着くまで作り直しを待たせる。
     */
    val appliedSearchText: String = "",
    /**
     * 絞り込み + 年グルーピング済みの表示データ。
     *
     * かつては UiState の getter で毎回計算していたが、判定本体が FFI (共有コア) に移った
     * いま同じ形にすると再構成のたびに境界を跨ぐ。VM が [EventListViewModel.rebuild] で
     * 1 回だけ計算して載せる (iOS EventListViewModel の groupedByYear / filteredCount と同じ形)。
     */
    val groupedByYear: List<YearGroup> = emptyList(),
    val filteredCount: Int = 0
) {
    /** ツールバーのフィルタバッジ件数 (iOS EventListView.activeFilterCount と同じ数え方)。 */
    val activeFilterCount: Int
        get() = (if (selectedBrandIds.isEmpty()) 0 else 1) +
            (if (excludedKinds.isEmpty()) 0 else 1) +
            (if (attendanceFilter == "all") 0 else 1) +
            (if (requireFavorite) 1 else 0) +
            (if (requireNote) 1 else 0) +
            (if (showEmptyEvents) 1 else 0) +
            (if (hideStreaming) 1 else 0) +
            (if (venue == null) 0 else 1)
}

class EventListViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(EventListUiState())
    val uiState: StateFlow<EventListUiState> = _uiState.asStateFlow()

    // 絞り込みの入力。画面には出さないので UiState には載せない
    // (載せると Compose 側から母集合を触れてしまい、行ごとの再計算を招く)。
    private var eventsWithDate: List<EventWithDateRange> = emptyList()
    private var venueEventIds: Set<String> = emptySet()

    // マーク由来の id 集合 (参加/お気に入り/メモ)。母集合と同じく画面には出さない。
    private var attendedEventIds: Set<String> = emptySet()
    private var favoriteEventIds: Set<String> = emptySet()
    private var notedEventIds: Set<String> = emptySet()

    // 常に最新の 1 本だけ走らせる。連打で古い結果があとから届いて表示が巻き戻るのを防ぐ。
    private var rebuildJob: Job? = null

    // 検索語の確定待ち。打鍵のたびに張り替えて、前のジョブは cancel する。
    private var searchDebounceJob: Job? = null

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
            loadMarkSets(context)
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

    /**
     * 参加 / お気に入り / メモ の id 集合を解決する。
     *
     * 参加記録は公演 (show) 単位でも持つので、event 単位へ逆引きしてから渡す
     * (attendedEventTypeSets が event/show 双方のマークを event_id へ畳んでくれる)。
     */
    private suspend fun loadMarkSets(context: Context) {
        val module = AppModule.from(context)
        val marks = module.userMarkRepository
        val attended = marks.attendedEventTypeSets()
        attendedEventIds = attended.live + attended.stream + attended.liveViewing
        val dao = module.database.userMarkDao()
        favoriteEventIds = dao.idsFor(UserMark.EVENT, UserMark.FAVORITE).toSet()
        notedEventIds = dao.idsWithNote(UserMark.EVENT).toSet()
    }

    fun toggleBrand(brandId: String) {
        val current = _uiState.value.selectedBrandIds
        _uiState.value = _uiState.value.copy(
            selectedBrandIds = if (brandId in current) current - brandId else current + brandId
        )
        scheduleRebuild()
    }

    fun clearBrands() {
        _uiState.value = _uiState.value.copy(selectedBrandIds = emptySet())
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
     * 一覧内の絞り込み欄の入力。
     *
     * ここでは表示用の [EventListUiState.searchText] だけ即座に更新し、絞り込みに使う
     * [EventListUiState.appliedSearchText] は打鍵が落ち着いてから反映する。日本語 IME の
     * 変換中は 1 打鍵ごとに未確定文字が差し替わるので、そのまま引くと変換のたびに一覧が
     * 作り直されて入力が渋る。消したときだけは即座に全件へ戻す (待たせる理由が無い)。
     */
    fun setSearchText(text: String) {
        _uiState.value = _uiState.value.copy(searchText = text)
        searchDebounceJob?.cancel()
        if (text.isEmpty()) {
            _uiState.value = _uiState.value.copy(appliedSearchText = "")
            scheduleRebuild()
            return
        }
        searchDebounceJob = viewModelScope.launch {
            delay(SEARCH_DEBOUNCE_MS)
            _uiState.value = _uiState.value.copy(appliedSearchText = text)
            // 走行中の再構築があれば捨てて組み直す (rebuild を直に呼ぶと 2 本が同じ state を奪い合う)。
            scheduleRebuild()
        }
    }

    /** フィルタシートの「適用」。 */
    fun applyFilterSheet(
        brandIds: Set<String>,
        excludedKinds: Set<String>,
        attendanceFilter: String,
        requireFavorite: Boolean,
        requireNote: Boolean,
        showEmptyEvents: Boolean,
        hideStreaming: Boolean
    ) {
        _uiState.value = _uiState.value.copy(
            selectedBrandIds = brandIds,
            excludedKinds = excludedKinds,
            attendanceFilter = attendanceFilter,
            requireFavorite = requireFavorite,
            requireNote = requireNote,
            showEmptyEvents = showEmptyEvents,
            hideStreaming = hideStreaming
        )
        scheduleRebuild()
    }

    /** チップ列からの個別解除。 */
    fun removeExcludedKind(kind: String) {
        _uiState.value = _uiState.value.copy(excludedKinds = _uiState.value.excludedKinds - kind)
        scheduleRebuild()
    }

    fun clearAttendanceFilter() {
        _uiState.value = _uiState.value.copy(attendanceFilter = "all")
        scheduleRebuild()
    }

    fun clearFavoriteFilter() {
        _uiState.value = _uiState.value.copy(requireFavorite = false)
        scheduleRebuild()
    }

    fun clearNoteFilter() {
        _uiState.value = _uiState.value.copy(requireNote = false)
        scheduleRebuild()
    }

    fun clearShowEmptyEvents() {
        _uiState.value = _uiState.value.copy(showEmptyEvents = false)
        scheduleRebuild()
    }

    fun clearSearchText() {
        searchDebounceJob?.cancel()
        _uiState.value = _uiState.value.copy(searchText = "", appliedSearchText = "")
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
            selectedBrandIds = state.selectedBrandIds.toList(),
            excludedKinds = state.excludedKinds.toList(),
            searchText = state.appliedSearchText,
            attendanceFilter = state.attendanceFilter,
            attendedEventIds = attendedEventIds.toList(),
            requireFavorite = state.requireFavorite,
            favoriteIds = favoriteEventIds.toList(),
            requireNote = state.requireNote,
            noteIds = notedEventIds.toList(),
            // コアはこの文字列を on/off 判定にしか使わないので、会場名でなく venue_id を渡してよい。
            venue = state.venue.orEmpty(),
            venueEventIds = venueEventIds.toList()
        )
        val groups = withContext(Dispatchers.Default) {
            // 純粋関数だが FFI は呼び元スレッドをブロックするので UI スレッドから外す。
            var filtered = filterEvents(source, criteria)
            if (!state.showEmptyEvents) {
                // 公演が 1 つも無いイベント (= 初回公演日が無い) を落とす。コアの
                // eventsWithFirstDate は include_empty で同じことをするが、この一覧の母集合は
                // kind を絞らないため SQL 経路のままなので、ここで落とす。
                filtered = filtered.filter { !it.firstDate.isNullOrEmpty() }
            }
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

    private companion object {
        /** 変換が落ち着いたと見なすまでの待ち (iOS EventListView の 280ms と同値)。 */
        const val SEARCH_DEBOUNCE_MS = 280L
    }
}
