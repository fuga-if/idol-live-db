package com.fugaif.imaslivedb.ui.schedule

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

/** グリッドのドット・フィルタチップの種別。序数がドットの並び順になる。 */
enum class CalendarCategory {
    SHOW,
    RELEASE,
    BIRTHDAY,
    STAFF_BIRTHDAY,
    ANNIVERSARY,
    TICKET
}

data class CalendarUiState(
    /**
     * グリッドの「今日」。JST 固定 (公演日は日本の開催日なので端末ローカルだと海外で 1 日ずれる)。
     * 判定は FFI なので描画のたびに引かず、読込のたびに 1 回だけ確定させて state に載せる。
     */
    val today: LocalDate = JstDay.date(),
    val yearMonth: YearMonth = YearMonth.from(today),
    val byDay: Map<Int, List<CalendarEntry>> = emptyMap(),
    val selectedDay: Int? = null,
    val showShows: Boolean = true,
    val showReleases: Boolean = true,
    val showBirthdays: Boolean = false,
    val showStaffBirthdays: Boolean = false,
    val showAnniversaries: Boolean = true,
    val showTickets: Boolean = true,
    /** false=月表示 / true=週表示 (選択日を含む1週間)。 */
    val weekMode: Boolean = false,
    val isLoading: Boolean = true
) {
    /** [category] が現在表示対象か。 */
    fun isVisible(category: CalendarCategory): Boolean = when (category) {
        CalendarCategory.SHOW -> showShows
        CalendarCategory.RELEASE -> showReleases
        CalendarCategory.BIRTHDAY -> showBirthdays
        CalendarCategory.STAFF_BIRTHDAY -> showStaffBirthdays
        CalendarCategory.ANNIVERSARY -> showAnniversaries
        CalendarCategory.TICKET -> showTickets
    }
}

/**
 * エントリの種別 (フィルタ・日詳細リストの色分けに使う)。チケットは単日点と受付期間で同色。
 *
 * 受付期間もこの写像で TICKET になるのでフィルタチップ 1 つで両方が切れる。ただしグリッドの
 * 点は [CalendarViewModel.dotsFor] が受付期間を落とすので、点に出るのは単日側だけ。
 */
val CalendarEntry.category: CalendarCategory
    get() = when (this) {
        is CalendarEntry.Show -> CalendarCategory.SHOW
        is CalendarEntry.Release -> CalendarCategory.RELEASE
        is CalendarEntry.Birthday -> CalendarCategory.BIRTHDAY
        is CalendarEntry.StaffBirthday -> CalendarCategory.STAFF_BIRTHDAY
        is CalendarEntry.Anniversary -> CalendarCategory.ANNIVERSARY
        is CalendarEntry.Ticket, is CalendarEntry.TicketPeriod -> CalendarCategory.TICKET
    }

class CalendarViewModel(app: Application) : AndroidViewModel(app) {

    private val calendar = AppModule.from(app).calendarRepository

    private val _uiState = MutableStateFlow(CalendarUiState())
    val uiState: StateFlow<CalendarUiState> = _uiState.asStateFlow()

    init { load() }

    /** 外部 (同期完了時など) からの再読込。現在の月を取り直す。 */
    fun reload() = load()

    private fun load() {
        val month = _uiState.value.yearMonth
        viewModelScope.launch {
            val entries = calendar.fetchEntries(month)
            _uiState.value = _uiState.value.copy(
                today = JstDay.date(),
                byDay = buildByDay(entries, month),
                isLoading = false
            )
        }
    }

    /**
     * 表示順の確定したエントリ列を日ごとに振り分ける。
     *
     * 絞り込み・年展開・並び替えはすべて共有コアが済ませているので、ここは「どの日のセルに
     * 載せるか」だけを決める (iOS `CalendarView.groupByDate` と同じ責務)。
     * 受付期間の帯だけは被覆する各日に複製して入れる。
     */
    private fun buildByDay(entries: List<CalendarEntry>, month: YearMonth): Map<Int, List<CalendarEntry>> {
        val map = HashMap<Int, MutableList<CalendarEntry>>()
        fun add(day: Int, entry: CalendarEntry) {
            if (day in 1..month.lengthOfMonth()) map.getOrPut(day) { mutableListOf() }.add(entry)
        }
        for (entry in entries) {
            if (entry is CalendarEntry.TicketPeriod) {
                for (day in coveredDays(entry.row.start, entry.row.end, month)) add(day, entry)
                continue
            }
            dayOf(entry.date, month)?.let { add(it, entry) }
        }
        return map
    }

    /** その月に属する "yyyy-MM-dd" なら日番号。他の月の日付 (受付期間の端など) は null。 */
    private fun dayOf(date: String, month: YearMonth): Int? {
        if (date.take(7) != "%04d-%02d".format(month.year, month.monthValue)) return null
        return date.substringAfterLast('-').toIntOrNull()
    }

    /** [start]〜[end] (両端含む) を [month] 内へクリップした日番号の列。 */
    private fun coveredDays(start: String, end: String, month: YearMonth): List<Int> {
        val first = runCatching { LocalDate.parse(start) }.getOrNull() ?: return emptyList()
        val last = runCatching { LocalDate.parse(end) }.getOrNull() ?: return emptyList()
        if (last < first) return emptyList()
        val monthStart = month.atDay(1)
        val monthEnd = month.atEndOfMonth()
        var day = maxOf(first, monthStart)
        val stop = minOf(last, monthEnd)
        val days = mutableListOf<Int>()
        while (!day.isAfter(stop)) {
            days += day.dayOfMonth
            day = day.plusDays(1)
        }
        return days
    }

    fun goToMonth(delta: Long) {
        _uiState.value = _uiState.value.copy(
            yearMonth = _uiState.value.yearMonth.plusMonths(delta),
            selectedDay = null,
            isLoading = true
        )
        load()
    }

    fun selectDay(day: Int?) {
        _uiState.value = _uiState.value.copy(selectedDay = day)
    }

    fun toggleWeekMode() { _uiState.value = _uiState.value.copy(weekMode = !_uiState.value.weekMode) }
    fun toggleShows() { _uiState.value = _uiState.value.copy(showShows = !_uiState.value.showShows) }
    fun toggleReleases() { _uiState.value = _uiState.value.copy(showReleases = !_uiState.value.showReleases) }
    fun toggleBirthdays() { _uiState.value = _uiState.value.copy(showBirthdays = !_uiState.value.showBirthdays) }
    fun toggleStaffBirthdays() { _uiState.value = _uiState.value.copy(showStaffBirthdays = !_uiState.value.showStaffBirthdays) }
    fun toggleAnniversaries() { _uiState.value = _uiState.value.copy(showAnniversaries = !_uiState.value.showAnniversaries) }
    fun toggleTickets() { _uiState.value = _uiState.value.copy(showTickets = !_uiState.value.showTickets) }

    /** フィルタ適用後の、指定日のエントリ。 */
    fun entriesFor(day: Int): List<CalendarEntry> {
        val state = _uiState.value
        return (state.byDay[day] ?: emptyList()).filter { state.isVisible(it.category) }
    }

    /**
     * その日に出ている種別 (フィルタ適用後)。グリッドのドット表示用。
     *
     * 受付期間 ([CalendarEntry.TicketPeriod]) は数えない。iOS の日セルは単日エントリだけを
     * 並べ、受付期間は週レーンの帯 (CalendarPeriodBand) として別に描くため点にはならない
     * (`MonthCalendarView.barEntries` が .ticketPeriod を除外している)。ここで数えると
     * 受付期間の全日にチケット点が連なり、iOS に無い表示になる。
     * 単日の申込締切・当落発表 ([CalendarEntry.Ticket]) は iOS と同じく対象のまま。
     */
    fun dotsFor(day: Int): Set<CalendarCategory> {
        val state = _uiState.value
        return (state.byDay[day] ?: emptyList())
            .filterNot { it is CalendarEntry.TicketPeriod }
            .map { it.category }
            .filterTo(sortedSetOf<CalendarCategory>()) { state.isVisible(it) }
    }
}
