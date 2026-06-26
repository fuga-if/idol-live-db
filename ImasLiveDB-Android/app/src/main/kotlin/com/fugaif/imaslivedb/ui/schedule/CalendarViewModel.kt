package com.fugaif.imaslivedb.ui.schedule

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.CalBirthdayRow
import com.fugaif.imaslivedb.data.model.CalReleaseRow
import com.fugaif.imaslivedb.data.model.CalShowRow
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.YearMonth

/** カレンダーの1エントリ (公演/リリース/誕生日)。day はその月の日。 */
sealed class CalEntry {
    abstract val day: Int
    data class Show(val row: CalShowRow, override val day: Int) : CalEntry()
    data class Release(val rows: List<CalReleaseRow>, override val day: Int) : CalEntry()
    data class Birthday(val row: CalBirthdayRow, override val day: Int) : CalEntry()
}

data class CalendarUiState(
    val yearMonth: YearMonth = YearMonth.now(),
    val byDay: Map<Int, List<CalEntry>> = emptyMap(),
    val selectedDay: Int? = null,
    val showShows: Boolean = true,
    val showReleases: Boolean = true,
    val showBirthdays: Boolean = false,
    /** false=月表示 / true=週表示 (選択日を含む1週間)。 */
    val weekMode: Boolean = false,
    val isLoading: Boolean = true
)

class CalendarViewModel(app: Application) : AndroidViewModel(app) {

    private val cal = AppModule.from(app).database.calendarDao()

    private val _uiState = MutableStateFlow(CalendarUiState())
    val uiState: StateFlow<CalendarUiState> = _uiState.asStateFlow()

    init { load() }

    /** 外部 (同期完了時など) からの再読込。現在の月を取り直す。 */
    fun reload() = load()

    private fun load() {
        val ym = _uiState.value.yearMonth
        val ymStr = "%04d-%02d".format(ym.year, ym.monthValue)
        val mm = "%02d".format(ym.monthValue)
        viewModelScope.launch {
            val shows = cal.showsInMonth(ymStr)
            val releases = cal.releasesInMonth(ymStr)
            val birthdays = cal.birthdaysInMonth(mm)
            _uiState.value = _uiState.value.copy(
                byDay = buildByDay(shows, releases, birthdays),
                isLoading = false
            )
        }
    }

    private fun dayOf(date: String): Int? = date.substringAfterLast('-').toIntOrNull()
    private fun birthdayDay(b: String): Int? = b.removePrefix("--").substringAfter('-').toIntOrNull()

    private fun buildByDay(
        shows: List<CalShowRow>, releases: List<CalReleaseRow>, birthdays: List<CalBirthdayRow>
    ): Map<Int, List<CalEntry>> {
        val map = HashMap<Int, MutableList<CalEntry>>()
        fun add(day: Int, e: CalEntry) = map.getOrPut(day) { mutableListOf() }.add(e)
        shows.forEach { s -> dayOf(s.date)?.let { add(it, CalEntry.Show(s, it)) } }
        // リリースは同日多数なので日ごとに集約して1エントリ
        releases.groupBy { dayOf(it.releaseDate) }.forEach { (day, rows) ->
            if (day != null) add(day, CalEntry.Release(rows, day))
        }
        birthdays.forEach { b -> birthdayDay(b.birthday)?.let { add(it, CalEntry.Birthday(b, it)) } }
        return map
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

    /** フィルタ適用後の、指定日のエントリ。 */
    fun entriesFor(day: Int): List<CalEntry> {
        val s = _uiState.value
        return (s.byDay[day] ?: emptyList()).filter {
            when (it) {
                is CalEntry.Show -> s.showShows
                is CalEntry.Release -> s.showReleases
                is CalEntry.Birthday -> s.showBirthdays
            }
        }
    }

    /** その月にエントリ(フィルタ適用後)を持つ日→種別フラグ。グリッドのドット表示用。 */
    fun dotsFor(day: Int): Set<Int> {
        val s = _uiState.value
        val kinds = sortedSetOf<Int>()
        (s.byDay[day] ?: emptyList()).forEach {
            when (it) {
                is CalEntry.Show -> if (s.showShows) kinds.add(0)
                is CalEntry.Release -> if (s.showReleases) kinds.add(1)
                is CalEntry.Birthday -> if (s.showBirthdays) kinds.add(2)
            }
        }
        return kinds
    }

    fun today(): LocalDate = LocalDate.now()
}
