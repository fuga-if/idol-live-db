package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.CalReleaseRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import java.time.LocalDate

private val ShowColor = Color(0xFF3E6DD6)
private val ReleaseColor = DS.warning
private val BirthdayColor = DS.pick

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CalendarScreen(
    onNavigateToShow: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToSearch: () -> Unit,
    onNavigateToSettings: () -> Unit,
    viewModel: CalendarViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    // 同期完了でカレンダーを再読込 (初回 full sync 完了直後にドットを反映)。
    val ctx = androidx.compose.ui.platform.LocalContext.current
    val syncState by com.fugaif.imaslivedb.di.AppModule.from(ctx).syncEngine.state.collectAsStateWithLifecycle()
    androidx.compose.runtime.LaunchedEffect(syncState) {
        if (syncState is com.fugaif.imaslivedb.data.sync.CloudKitSyncEngine.SyncState.Completed) {
            viewModel.reload()
        }
    }
    val ym = state.yearMonth
    val today = viewModel.today()
    val isCurrentMonth = today.year == ym.year && today.monthValue == ym.monthValue
    val selectedDay = state.selectedDay ?: if (isCurrentMonth) today.dayOfMonth else null

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("スケジュール", fontWeight = FontWeight.Bold) },
                actions = {
                    IconButton(onClick = onNavigateToSearch) {
                        Icon(Icons.Filled.Search, contentDescription = "検索")
                    }
                    IconButton(onClick = onNavigateToSettings) {
                        Icon(Icons.Filled.Settings, contentDescription = "設定・マイ")
                    }
                }
            )
        }
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            // フィルタチップ
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                CalFilterChip("公演", ShowColor, state.showShows) { viewModel.toggleShows() }
                CalFilterChip("リリース", ReleaseColor, state.showReleases) { viewModel.toggleReleases() }
                CalFilterChip("誕生日", BirthdayColor, state.showBirthdays) { viewModel.toggleBirthdays() }
            }

            // 月ナビ
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { viewModel.goToMonth(-1) }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "前の月")
                }
                Text(
                    "${ym.year}年 ${ym.monthValue}月",
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
                IconButton(onClick = { viewModel.goToMonth(1) }) {
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "次の月")
                }
                // 月/週 切替
                Box(
                    modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(DS.fill)
                        .clickable { viewModel.toggleWeekMode() }.padding(horizontal = 10.dp, vertical = 4.dp)
                ) {
                    Text(if (state.weekMode) "週" else "月", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                }
            }

            // 曜日ヘッダ
            Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
                val labels = listOf("日", "月", "火", "水", "木", "金", "土")
                labels.forEachIndexed { i, d ->
                    Text(
                        d,
                        modifier = Modifier.weight(1f),
                        textAlign = TextAlign.Center,
                        style = MaterialTheme.typography.labelSmall,
                        color = when (i) { 0 -> BirthdayColor; 6 -> ShowColor; else -> DS.ink2 }
                    )
                }
            }

            // 月グリッド / 週ストリップ
            if (state.weekMode) {
                WeekStrip(
                    ym = ym, today = today, selectedDay = selectedDay ?: 1,
                    dotsProvider = { viewModel.dotsFor(it) },
                    onSelect = { viewModel.selectDay(it) }
                )
            } else {
                MonthGrid(
                    ym = ym, today = today, selectedDay = selectedDay,
                    dotsProvider = { viewModel.dotsFor(it) },
                    onSelect = { viewModel.selectDay(it) }
                )
            }

            // 選択日のエントリ
            val entries = selectedDay?.let { viewModel.entriesFor(it) } ?: emptyList()
            DaySectionHeader(ym, selectedDay)
            LazyColumn(modifier = Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 16.dp)) {
                items(entries) { entry ->
                    when (entry) {
                        is CalEntry.Show -> EntryRow(ShowColor, entry.row.eventName, entry.row.showName,
                            brandColor(entry.row.brandId)) { onNavigateToShow(entry.row.showId) }
                        is CalEntry.Birthday -> EntryRow(BirthdayColor, "誕生日", entry.row.name,
                            brandColor(entry.row.brandId)) { onNavigateToIdol(entry.row.id) }
                        is CalEntry.Release -> ReleaseRows(entry.rows, onNavigateToSong)
                    }
                }
                if (selectedDay != null && entries.isEmpty()) {
                    item {
                        Text(
                            "この日の記録はありません",
                            modifier = Modifier.fillMaxWidth().padding(24.dp),
                            textAlign = TextAlign.Center,
                            color = DS.ink3,
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MonthGrid(
    ym: java.time.YearMonth,
    today: LocalDate,
    selectedDay: Int?,
    dotsProvider: (Int) -> Set<Int>,
    onSelect: (Int) -> Unit
) {
    val firstDow = LocalDate.of(ym.year, ym.monthValue, 1).dayOfWeek.value % 7 // 日=0
    val daysInMonth = ym.lengthOfMonth()
    val cells = firstDow + daysInMonth
    val rows = (cells + 6) / 7
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
        for (r in 0 until rows) {
            Row(modifier = Modifier.fillMaxWidth()) {
                for (c in 0 until 7) {
                    val cellIndex = r * 7 + c
                    val day = cellIndex - firstDow + 1
                    Box(modifier = Modifier.weight(1f).aspectRatio(1f), contentAlignment = Alignment.Center) {
                        if (day in 1..daysInMonth) {
                            DayCell(
                                day = day,
                                isToday = today.year == ym.year && today.monthValue == ym.monthValue && today.dayOfMonth == day,
                                isSelected = selectedDay == day,
                                dots = dotsProvider(day),
                                onClick = { onSelect(day) }
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun WeekStrip(
    ym: java.time.YearMonth,
    today: LocalDate,
    selectedDay: Int,
    dotsProvider: (Int) -> Set<Int>,
    onSelect: (Int) -> Unit
) {
    val firstDow = LocalDate.of(ym.year, ym.monthValue, 1).dayOfWeek.value % 7
    val daysInMonth = ym.lengthOfMonth()
    val cellIndex = firstDow + selectedDay - 1
    val weekStart = (cellIndex / 7) * 7
    Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp)) {
        for (c in 0 until 7) {
            val day = weekStart + c - firstDow + 1
            Box(modifier = Modifier.weight(1f).aspectRatio(1f), contentAlignment = Alignment.Center) {
                if (day in 1..daysInMonth) {
                    DayCell(
                        day = day,
                        isToday = today.year == ym.year && today.monthValue == ym.monthValue && today.dayOfMonth == day,
                        isSelected = selectedDay == day,
                        dots = dotsProvider(day),
                        onClick = { onSelect(day) }
                    )
                }
            }
        }
    }
}

@Composable
private fun DayCell(day: Int, isToday: Boolean, isSelected: Boolean, dots: Set<Int>, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .size(40.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (isSelected) DS.surface2 else Color.Transparent)
            .clickable(onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier.size(24.dp)
                .clip(CircleShape)
                .background(if (isToday) DS.ink else Color.Transparent),
            contentAlignment = Alignment.Center
        ) {
            Text(
                "$day",
                style = MaterialTheme.typography.bodySmall,
                color = if (isToday) DS.onSys else DS.ink,
                fontWeight = if (isToday) FontWeight.Bold else FontWeight.Normal
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.height(6.dp)) {
            dots.forEach { kind ->
                Box(
                    modifier = Modifier.size(5.dp).clip(CircleShape).background(
                        when (kind) { 0 -> ShowColor; 1 -> ReleaseColor; else -> BirthdayColor }
                    )
                )
            }
        }
    }
}

@Composable
private fun DaySectionHeader(ym: java.time.YearMonth, day: Int?) {
    if (day == null) return
    Text(
        "${ym.monthValue}月${day}日",
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, top = 8.dp, bottom = 4.dp),
        style = MaterialTheme.typography.titleSmall,
        fontWeight = FontWeight.Bold,
        color = DS.ink2
    )
}

@Composable
private fun EntryRow(accent: Color, label: String, title: String, brand: Color, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(modifier = Modifier.size(width = 4.dp, height = 36.dp).clip(RoundedCornerShape(2.dp)).background(brand))
        Spacer(Modifier.size(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.labelSmall, color = accent, fontWeight = FontWeight.Bold)
            Text(title, style = MaterialTheme.typography.bodyMedium, color = DS.ink, maxLines = 2)
        }
    }
}

@Composable
private fun ReleaseRows(rows: List<CalReleaseRow>, onSong: (String) -> Unit) {
    Column {
        rows.forEach { song ->
            EntryRow(ReleaseColor, "リリース", song.title, brandColor(song.brandId)) { onSong(song.id) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CalFilterChip(label: String, color: Color, selected: Boolean, onClick: () -> Unit) {
    FilterChip(
        selected = selected,
        onClick = onClick,
        label = { Text(label, style = MaterialTheme.typography.labelMedium) },
        leadingIcon = {
            Box(modifier = Modifier.size(8.dp).clip(CircleShape).background(color))
        },
        colors = FilterChipDefaults.filterChipColors(
            selectedContainerColor = DS.surface2
        )
    )
}
