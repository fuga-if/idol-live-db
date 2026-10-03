package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Badge
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.ui.components.AttendanceSwipeRow
import com.fugaif.imaslivedb.ui.designsystem.ImasChipRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import java.time.LocalDate

/**
 * 月表示の縦空間配分。グリッドはフィット型なので、ここで決めた高さに必ず 6 行が収まる
 * (iOS `CalendarView.MonthLayout` と同値)。
 */
private const val MONTH_GRID_FRACTION = 0.62f

/** タブレット等の大画面でグリッドだけが間延びしないための上限。 */
private val MonthGridMaxHeight = 520.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarScreen(
    onNavigateToShow: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit,
    onNavigateToSettings: () -> Unit,
    viewModel: CalendarViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // 同期完了でカレンダーを再読込 (初回 full sync 完了直後に予定を反映)。
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val syncState by com.fugaif.imaslivedb.di.AppModule.from(ctx).syncEngine.state.collectAsStateWithLifecycle()
    androidx.compose.runtime.LaunchedEffect(syncState) {
        if (syncState is com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine.SyncState.Completed) {
            viewModel.reload()
        }
    }

    // 「今日」は VM が JST で確定させたもの (端末ローカルだと海外で丸の位置が 1 日ずれる)。
    val ym = state.yearMonth
    val isCurrentMonth = ym == java.time.YearMonth.from(state.today)
    val selectedDate = state.selectedDate ?: if (isCurrentMonth) state.today else null

    // 日詳細シートの対象日 (null = 非表示)。
    var daySheetDate by remember { mutableStateOf<LocalDate?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("スケジュール", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = onNavigateToSettings) {
                        Icon(Icons.Filled.Settings, contentDescription = "設定・マイ")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            FilterBar(state, viewModel)

            if (state.weekMode) {
                WeekTimeGrid(
                    state = state,
                    // 週表示は必ず基準日を持つ (toggleWeekMode が入れる)。念のため今日で受ける。
                    anchor = selectedDate ?: state.today,
                    onSelectDate = { viewModel.selectDate(it) },
                    onSelectEntry = { openEntry(it, onNavigateToShow, onNavigateToSong, onNavigateToIdol, onNavigateToEvent) },
                    onShowDay = { daySheetDate = it },
                    onWeekDelta = { viewModel.goToWeek(it, selectedDate ?: state.today) },
                    modifier = Modifier.weight(1f)
                )
            } else {
                MonthNavRow(
                    title = "${ym.year}年 ${ym.monthValue}月",
                    onPrev = { viewModel.goToMonth(-1) },
                    onNext = { viewModel.goToMonth(1) }
                )
                WeekdayHeader()
                MonthPane(
                    state = state,
                    selectedDate = selectedDate,
                    onSelectDate = { viewModel.selectDate(it) },
                    onShowDay = { daySheetDate = it },
                    onMonthDelta = { viewModel.goToMonth(it) },
                    onNavigateToShow = onNavigateToShow,
                    onNavigateToSong = onNavigateToSong,
                    onNavigateToIdol = onNavigateToIdol,
                    onNavigateToEvent = onNavigateToEvent,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }

    daySheetDate?.let { date ->
        DayDetailSheet(
            state = state,
            date = date,
            onDismiss = { daySheetDate = null },
            onNavigateToShow = { daySheetDate = null; onNavigateToShow(it) },
            onNavigateToSong = { daySheetDate = null; onNavigateToSong(it) },
            onNavigateToIdol = { daySheetDate = null; onNavigateToIdol(it) },
            onNavigateToEvent = { daySheetDate = null; onNavigateToEvent(it) }
        )
    }
}

/** 週グリッドのブロック/帯タップ → 既存の詳細画面へ (行タップと同じ行き先に揃える)。 */
private fun openEntry(
    entry: CalendarEntry,
    onNavigateToShow: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit
) {
    when (entry) {
        is CalendarEntry.Show -> onNavigateToShow(entry.row.showId)
        is CalendarEntry.Release -> entry.songs.firstOrNull()?.let { onNavigateToSong(it.id) }
        is CalendarEntry.Birthday -> onNavigateToIdol(entry.row.id)
        is CalendarEntry.Ticket -> onNavigateToEvent(entry.row.eventId)
        is CalendarEntry.TicketPeriod -> onNavigateToEvent(entry.row.eventId)
        // 事務員誕生日と記念日は専用の詳細画面を持たないので遷移しない。
        is CalendarEntry.StaffBirthday, is CalendarEntry.Anniversary -> Unit
    }
}

/** カテゴリ chip + 月/週 切替 (iOS `CalendarView.topBar` と同じ並び)。 */
@Composable
private fun FilterBar(state: CalendarUiState, viewModel: CalendarViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasChipRow(modifier = Modifier.weight(1f), contentPadding = DS.Space.gapLoose) {
            CalFilterChip("公演", Icons.Filled.Mic, state.showShows) { viewModel.toggleShows() }
            CalFilterChip("リリース", Icons.Filled.Album, state.showReleases) { viewModel.toggleReleases() }
            CalFilterChip("誕生日", Icons.Filled.CardGiftcard, state.showBirthdays) { viewModel.toggleBirthdays() }
            CalFilterChip("事務員", Icons.Filled.Badge, state.showStaffBirthdays) { viewModel.toggleStaffBirthdays() }
            CalFilterChip("記念日", Icons.Filled.AutoAwesome, state.showAnniversaries) { viewModel.toggleAnniversaries() }
            CalFilterChip("チケット", Icons.Filled.ConfirmationNumber, state.showTickets) { viewModel.toggleTickets() }
        }
        ImasSegmented(
            labels = listOf("月", "週"),
            selection = if (state.weekMode) 1 else 0,
            onSelect = { index -> if ((index == 1) != state.weekMode) viewModel.toggleWeekMode() },
            // 高さは中身に任せる (固定するとアプリ内の文字サイズ倍率でラベルが切れる)。
            modifier = Modifier.padding(start = DS.Space.gap, end = DS.Space.gapLoose).width(78.dp)
        )
    }
}

@Composable
private fun MonthNavRow(title: String, onPrev: () -> Unit, onNext: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = onPrev) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "前の月")
        }
        ImasText(title, ImasTextRole.SECTION_TITLE, modifier = Modifier.weight(1f), textAlign = TextAlign.Center)
        IconButton(onClick = onNext) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "次の月")
        }
    }
}

@Composable
private fun WeekdayHeader() {
    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.gapTight)) {
        listOf("日", "月", "火", "水", "木", "金", "土").forEachIndexed { i, d ->
            ImasText(
                d,
                ImasTextRole.SECTION_LABEL,
                modifier = Modifier.weight(1f),
                textAlign = TextAlign.Center,
                color = when (i) { 0 -> BirthdayColor; 6 -> ShowColor; else -> DS.ink2 }
            )
        }
    }
}

/**
 * 月グリッド + 選択日リスト。
 *
 * 利用可能高を測ってグリッドに固定割合を割り付ける (グリッド側はフィット型なので、
 * 与えた高さに 6 行が必ず収まる)。残りは選択日リストが取り、リストは内部スクロールする
 * ためあふれない。
 */
@Composable
private fun MonthPane(
    state: CalendarUiState,
    selectedDate: LocalDate?,
    onSelectDate: (LocalDate) -> Unit,
    onShowDay: (LocalDate) -> Unit,
    onMonthDelta: (Long) -> Unit,
    onNavigateToShow: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit,
    modifier: Modifier = Modifier
) {
    BoxWithConstraints(modifier = modifier.fillMaxSize()) {
        val gridHeight = minOf(maxHeight * MONTH_GRID_FRACTION, MonthGridMaxHeight)
        Column(modifier = Modifier.fillMaxSize()) {
            MonthCalendar(
                state = state,
                onSelectDate = onSelectDate,
                onShowDay = onShowDay,
                onMonthDelta = onMonthDelta,
                modifier = Modifier.fillMaxWidth().height(gridHeight).padding(horizontal = 6.dp)
            )

            val entries = selectedDate?.let { state.entriesOn(it) } ?: emptyList()
            if (selectedDate != null) {
                DaySectionHeader(selectedDate, entries.size) { onShowDay(selectedDate) }
            }
            LazyColumn(modifier = Modifier.weight(1f), contentPadding = PaddingValues(bottom = 16.dp)) {
                items(entries) { entry ->
                    // 公演行だけ右スワイプで参加登録 (日詳細シートと同じ規則)。
                    if (entry is CalendarEntry.Show) {
                        AttendanceSwipeRow(showId = entry.row.showId, showName = entry.row.showName) {
                            CalendarEntryRow(
                                entry = entry,
                                showDetail = state.showDetails[entry.row.showId],
                                onNavigateToShow = onNavigateToShow,
                                onNavigateToSong = onNavigateToSong,
                                onNavigateToIdol = onNavigateToIdol,
                                onNavigateToEvent = onNavigateToEvent
                            )
                        }
                    } else {
                        CalendarEntryRow(
                            entry = entry,
                            showDetail = null,
                            onNavigateToShow = onNavigateToShow,
                            onNavigateToSong = onNavigateToSong,
                            onNavigateToIdol = onNavigateToIdol,
                            onNavigateToEvent = onNavigateToEvent
                        )
                    }
                }
                if (selectedDate != null && entries.isEmpty()) {
                    item {
                        ImasText(
                            "この日の記録はありません",
                            ImasTextRole.NOTE,
                            modifier = Modifier.fillMaxWidth().padding(24.dp),
                            textAlign = TextAlign.Center
                        )
                    }
                }
            }
        }
    }
}

/** 選択日の小見出し。タップで日詳細シート (種別サマリと直行ボタン) を開く (DS §5.10 `ImasNavRow`)。 */
@Composable
private fun DaySectionHeader(date: LocalDate, count: Int, onOpenSheet: () -> Unit) {
    ImasNavRow(
        title = "${date.monthValue}月${date.dayOfMonth}日",
        value = if (count > 0) "$count 件" else null,
        showsChevron = count > 0,
        onClick = onOpenSheet,
        // 押すと何が開くかを読み上げる (前の Android の「この日の詳細」)。
        modifier = if (count > 0) Modifier.semantics { onClick(label = "この日の詳細") { onOpenSheet(); true } } else Modifier
    )
}

/** カテゴリの絞り込みチップ。先頭に種別の記号 (iOS `CalendarFilterChip` と同じ。DS §8.2 `ImasFilterChip`)。 */
@Composable
private fun CalFilterChip(
    label: String,
    icon: ImageVector,
    selected: Boolean,
    onClick: () -> Unit
) {
    ImasFilterChip(
        label = label,
        selected = selected,
        onClick = onClick,
        icon = icon
    )
}
