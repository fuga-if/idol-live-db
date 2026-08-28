package com.fugaif.imaslivedb.ui.schedule

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.data.model.JstDay
import com.fugaif.imaslivedb.data.repository.CalendarShowDetail
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
    /**
     * 暦日 → その日に出るエントリ (フィルタ適用前)。
     *
     * 日番号ではなく `LocalDate` を鍵にしているのは、月グリッドが前後の月の日も 6 行ぶん
     * 描き、週表示は月をまたいだ 1 週間を描くため。日番号だと「隣の月の 1 日」を
     * 当月の 1 日と区別できない。
     */
    val byDate: Map<LocalDate, List<CalendarEntry>> = emptyMap(),
    /** show_id → 開始時刻・会場 (週の時間グリッドと日詳細で使う)。 */
    val showDetails: Map<String, CalendarShowDetail> = emptyMap(),
    val selectedDate: LocalDate? = null,
    val showShows: Boolean = true,
    val showReleases: Boolean = true,
    val showBirthdays: Boolean = false,
    val showStaffBirthdays: Boolean = false,
    val showAnniversaries: Boolean = true,
    val showTickets: Boolean = true,
    /** false=月表示 / true=週表示 (選択日を含む1週間の時間グリッド)。 */
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

    /** 月グリッド左上の日 ([yearMonth] の 1 日を含む週の日曜)。週の切り出しもここが基準。 */
    val gridStart: LocalDate
        get() = yearMonth.atDay(1).let { it.minusDays(((it.dayOfWeek.value % 7)).toLong()) }
}

/**
 * エントリの種別 (フィルタ・日詳細リストの色分けに使う)。チケットは単日点と受付期間で同色。
 *
 * 受付期間もこの写像で TICKET になるのでフィルタチップ 1 つで両方が切れる。
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

    /**
     * 表示中の月グリッド 42 日ぶんを読み込む。
     *
     * 暦月ちょうどではなく 6 行 × 7 列の実描画範囲を取るのは、月グリッドが前後の月の日も
     * 描くようになったため (iOS `CalendarView.monthGridInterval` と同じ範囲)。
     * 週表示が見るのは必ずこの 42 日の内側なので、週送りでも追加の読み込みは要らない。
     */
    private fun load() {
        val state = _uiState.value
        val gridStart = state.gridStart
        val gridEnd = gridStart.plusDays(GRID_DAYS - 1)
        viewModelScope.launch {
            val data = calendar.fetchRange(gridStart, gridEnd)
            _uiState.value = _uiState.value.copy(
                today = JstDay.date(),
                byDate = buildByDate(data.entries, gridStart, gridEnd),
                showDetails = data.showDetails,
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
    private fun buildByDate(
        entries: List<CalendarEntry>,
        gridStart: LocalDate,
        gridEnd: LocalDate
    ): Map<LocalDate, List<CalendarEntry>> {
        val map = HashMap<LocalDate, MutableList<CalendarEntry>>()
        fun add(date: LocalDate, entry: CalendarEntry) {
            if (date < gridStart || date > gridEnd) return
            map.getOrPut(date) { mutableListOf() }.add(entry)
        }
        for (entry in entries) {
            if (entry is CalendarEntry.TicketPeriod) {
                var day = parseDate(entry.row.start) ?: continue
                val last = parseDate(entry.row.end) ?: continue
                if (last < day) continue
                // 表示範囲の外へはみ出す端はここで捨てる (帯の丸めは範囲内かどうかで決まる)。
                while (!day.isAfter(last)) {
                    add(day, entry)
                    day = day.plusDays(1)
                }
                continue
            }
            parseDate(entry.date)?.let { add(it, entry) }
        }
        return map
    }

    private fun parseDate(value: String): LocalDate? = runCatching { LocalDate.parse(value) }.getOrNull()

    fun goToMonth(delta: Long) {
        val next = _uiState.value.yearMonth.plusMonths(delta)
        _uiState.value = _uiState.value.copy(
            yearMonth = next,
            // 月を変えたら選択は解除。週表示のときだけ「その月の同じ曜日並び」を保てないので、
            // 選択日は改めてユーザーに選ばせる (iOS も月送りで選択日は動かさない)。
            selectedDate = null,
            isLoading = true
        )
        load()
    }

    fun selectDate(date: LocalDate?) {
        _uiState.value = _uiState.value.copy(selectedDate = date)
        alignMonthTo(date)
    }

    /** 週送り。選択日を [delta] 週ぶん動かし、月をまたいだら読み込み範囲も追従させる。 */
    fun goToWeek(delta: Long, anchor: LocalDate) {
        val next = anchor.plusWeeks(delta)
        _uiState.value = _uiState.value.copy(selectedDate = next)
        alignMonthTo(next)
    }

    /**
     * 選択日が読み込み済みの 42 日から外れたら、その日の月へ表示月を移して読み直す。
     * 週送りで月境界を越えたときに空の週が出るのを防ぐ。
     */
    private fun alignMonthTo(date: LocalDate?) {
        if (date == null) return
        val state = _uiState.value
        val gridStart = state.gridStart
        if (!date.isBefore(gridStart) && !date.isAfter(gridStart.plusDays(GRID_DAYS - 1))) return
        _uiState.value = state.copy(yearMonth = YearMonth.from(date), isLoading = true)
        load()
    }

    fun toggleWeekMode() {
        val state = _uiState.value
        // 週表示は必ず基準日が要る (どの週を出すか決まらない)。未選択なら今日 or 月初に寄せる。
        val fallback = if (YearMonth.from(state.today) == state.yearMonth) state.today else state.yearMonth.atDay(1)
        _uiState.value = state.copy(
            weekMode = !state.weekMode,
            selectedDate = state.selectedDate ?: fallback
        )
    }

    fun toggleShows() { _uiState.value = _uiState.value.copy(showShows = !_uiState.value.showShows) }
    fun toggleReleases() { _uiState.value = _uiState.value.copy(showReleases = !_uiState.value.showReleases) }
    fun toggleBirthdays() { _uiState.value = _uiState.value.copy(showBirthdays = !_uiState.value.showBirthdays) }
    fun toggleStaffBirthdays() { _uiState.value = _uiState.value.copy(showStaffBirthdays = !_uiState.value.showStaffBirthdays) }
    fun toggleAnniversaries() { _uiState.value = _uiState.value.copy(showAnniversaries = !_uiState.value.showAnniversaries) }
    fun toggleTickets() { _uiState.value = _uiState.value.copy(showTickets = !_uiState.value.showTickets) }

    private companion object {
        /** 月グリッドは常に 6 行 × 7 列。読み込み範囲もこの実描画範囲に合わせる。 */
        const val GRID_DAYS = 42L
    }
}

/** フィルタ適用後の、指定日のエントリ。並びはコアが確定させた表示順のまま。 */
fun CalendarUiState.entriesOn(date: LocalDate): List<CalendarEntry> =
    (byDate[date] ?: emptyList()).filter { isVisible(it.category) }

/** [gridStart] から数えて [row] 行目 (0 始まり) の 7 日。 */
fun CalendarUiState.weekDays(row: Int): List<LocalDate> =
    (0..6).map { gridStart.plusDays((row * 7 + it).toLong()) }

/** [date] を含む週の 7 日 (日曜始まり)。 */
fun weekOf(date: LocalDate): List<LocalDate> {
    val sunday = date.minusDays((date.dayOfWeek.value % 7).toLong())
    return (0..6).map { sunday.plusDays(it.toLong()) }
}

/** 日曜=0 の曜日番号 (グリッドの列に対応)。 */
val LocalDate.columnIndex: Int
    get() = dayOfWeek.value % 7
