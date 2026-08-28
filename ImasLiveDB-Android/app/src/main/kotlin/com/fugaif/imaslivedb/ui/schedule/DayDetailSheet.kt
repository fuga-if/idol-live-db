package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.EditCalendar
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.ui.theme.DS
import java.time.LocalDate

/**
 * 日詳細シート (iOS `CalendarDayDetailView` の移植)。
 *
 * 日付ヘッダ + 種別ごとの件数サマリバッジ + その日の予定リスト。
 * 公演行には「カレンダーに追加」と「セトリ」を直行ボタンとして置く — 一覧から
 * セトリまでのタップ数を減らすのがこのシートの目的なので、行タップ (イベント詳細) とは
 * 別に並べる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DayDetailSheet(
    state: CalendarUiState,
    date: LocalDate,
    onDismiss: () -> Unit,
    onNavigateToShow: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit
) {
    val context = LocalContext.current
    val entries = state.entriesOn(date)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = false)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = DS.bg
    ) {
        DayHeader(date = date, entries = entries)
        HorizontalDivider(color = DS.sep)
        if (entries.isEmpty()) {
            Text(
                "この日はライブ・リリース・誕生日の記録がありません",
                modifier = Modifier.fillMaxWidth().padding(32.dp),
                color = DS.ink3,
                fontSize = 14.sp
            )
        } else {
            LazyColumn(
                // シート内のリストは自前でスクロールする。上限を切らないと
                // 予定の多い日にシートが画面を突き抜ける。
                modifier = Modifier.heightIn(max = 520.dp),
                contentPadding = PaddingValues(bottom = 24.dp)
            ) {
                items(entries) { entry ->
                    CalendarEntryRow(
                        entry = entry,
                        showDetail = (entry as? CalendarEntry.Show)
                            ?.let { state.showDetails[it.row.showId] },
                        onNavigateToShow = onNavigateToShow,
                        onNavigateToSong = onNavigateToSong,
                        onNavigateToIdol = onNavigateToIdol,
                        onNavigateToEvent = onNavigateToEvent,
                        trailing = if (entry is CalendarEntry.Show) {
                            {
                                Row(horizontalArrangement = Arrangement.spacedBy(0.dp)) {
                                    IconButton(onClick = {
                                        DeviceCalendar.addShow(
                                            context,
                                            entry.row,
                                            state.showDetails[entry.row.showId]
                                        )
                                    }) {
                                        Icon(
                                            Icons.Filled.EditCalendar,
                                            contentDescription = "カレンダーに追加",
                                            tint = DS.success,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    }
                                    IconButton(onClick = { onNavigateToShow(entry.row.showId) }) {
                                        Icon(
                                            Icons.Filled.QueueMusic,
                                            contentDescription = "セトリ",
                                            tint = DS.ink2,
                                            modifier = Modifier.size(20.dp)
                                        )
                                    }
                                }
                            }
                        } else {
                            null
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun DayHeader(date: LocalDate, entries: List<CalendarEntry>) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DS.surface)
            .padding(horizontal = 20.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                "${date.year}年${date.monthValue}月${date.dayOfMonth}日",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = DS.ink
            )
            if (entries.isNotEmpty()) {
                Text("${entries.size}件のイベント", fontSize = 12.sp, color = DS.ink2)
            }
        }
        SummaryBadges(entries)
    }
}

/**
 * 種別ごとの件数バッジ。0 件の種別は出さない (その日に何があるかを一目で掴ませるため、
 * 空の枠は並べない)。アイドルと事務員の誕生日は同じ「贈り物」で束ねる (iOS と同じ)。
 */
@Composable
private fun SummaryBadges(entries: List<CalendarEntry>) {
    val shows = entries.count { it is CalendarEntry.Show }
    val releases = entries.count { it is CalendarEntry.Release }
    val birthdays = entries.count { it is CalendarEntry.Birthday || it is CalendarEntry.StaffBirthday }
    val anniversaries = entries.count { it is CalendarEntry.Anniversary }
    val tickets = entries.count { it is CalendarEntry.Ticket || it is CalendarEntry.TicketPeriod }

    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        if (shows > 0) SummaryBadge(shows, Icons.Filled.MusicNote, ShowColor)
        if (releases > 0) SummaryBadge(releases, Icons.Filled.QueueMusic, ReleaseColor)
        if (birthdays > 0) SummaryBadge(birthdays, Icons.Filled.CardGiftcard, BirthdayColor)
        if (anniversaries > 0) SummaryBadge(anniversaries, Icons.Filled.AutoAwesome, AnniversaryColor)
        if (tickets > 0) SummaryBadge(tickets, Icons.Filled.ConfirmationNumber, TicketColor)
    }
}

@Composable
private fun SummaryBadge(count: Int, icon: ImageVector, color: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(14.dp))
        Text("$count", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = color)
    }
}
