package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.model.CalReleaseRow
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.data.model.TicketCalendarRow
import com.fugaif.imaslivedb.data.model.TicketDateKind
import com.fugaif.imaslivedb.data.model.TicketPeriodRow
import com.fugaif.imaslivedb.data.repository.CalendarShowDetail
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.brandColor
import com.fugaif.imaslivedb.ui.theme.hexToColor

/**
 * 選択日の予定 1 行。スケジュール画面のインラインリストと日詳細シートで共有する
 * (iOS `DayEntryRow` と同じ位置づけ)。
 *
 * [trailing] は行末に足す操作 (日詳細シートの「セトリ」「カレンダーに追加」)。
 * インラインリストでは渡さないので、既存の見え方は変わらない。
 */
@Composable
internal fun CalendarEntryRow(
    entry: CalendarEntry,
    showDetail: CalendarShowDetail?,
    onNavigateToShow: (String) -> Unit,
    onNavigateToSong: (String) -> Unit,
    onNavigateToIdol: (String) -> Unit,
    onNavigateToEvent: (String) -> Unit,
    trailing: (@Composable () -> Unit)? = null
) {
    when (entry) {
        is CalendarEntry.Show -> EntryRow(
            accent = ShowColor,
            label = AppPreferences.eventDisplayName(entry.row.eventName),
            // 公演名・開始時刻・会場を 1 行に畳む (iOS の showRow と同じ並び)。
            title = listOfNotNull(
                entry.row.showName.takeIf { it.isNotBlank() },
                showDetail?.startTime,
                showDetail?.venue
            ).joinToString(" ・ ").ifEmpty { entry.row.eventName },
            brand = brandColor(entry.row.brandId),
            trailing = trailing,
            onClick = { onNavigateToShow(entry.row.showId) }
        )

        is CalendarEntry.Birthday -> EntryRow(
            accent = BirthdayColor,
            label = "誕生日",
            title = entry.row.name,
            brand = brandColor(entry.row.brandId),
            trailing = trailing,
            onClick = { onNavigateToIdol(entry.row.id) }
        )

        is CalendarEntry.Release -> ReleaseRows(entry.songs, onNavigateToSong)

        is CalendarEntry.StaffBirthday -> IconEntryRow(
            accent = StaffColor,
            icon = Icons.Filled.Person,
            label = "${entry.row.name} 誕生日",
            sub = entry.row.role ?: "",
            brand = brandColor(entry.row.brandId),
            trailing = trailing
        )

        is CalendarEntry.Anniversary -> IconEntryRow(
            accent = AnniversaryColor,
            icon = Icons.Filled.AutoAwesome,
            label = if (entry.years == 0) "${entry.row.label} (初日)" else "${entry.years}周年 ・ ${entry.row.label}",
            sub = "${entry.row.date.take(4)} 起点",
            brand = brandColor(entry.row.brandId),
            trailing = trailing
        )

        is CalendarEntry.Ticket -> TicketRow(entry.row, trailing) { onNavigateToEvent(entry.row.eventId) }

        is CalendarEntry.TicketPeriod ->
            TicketPeriodRowView(entry.row, trailing) { onNavigateToEvent(entry.row.eventId) }
    }
}

/** チケット日程行 (申込締切 / 当落発表)。タップで親イベント詳細へ。 */
@Composable
private fun TicketRow(row: TicketCalendarRow, trailing: (@Composable () -> Unit)?, onClick: () -> Unit) {
    IconEntryRow(
        // 申込締切は「その日までにやること」なので緊急色、当落発表はチケット系の藍 (iOS と同じ)。
        accent = if (row.kind == TicketDateKind.DEADLINE) DS.danger else TicketColor,
        icon = if (row.kind == TicketDateKind.DEADLINE) {
            Icons.Filled.ConfirmationNumber
        } else {
            Icons.Filled.MailOutline
        },
        label = "${row.kind.label} ・ ${AppPreferences.eventDisplayName(row.eventName)}",
        sub = if (row.kind == TicketDateKind.DEADLINE) "チケット申込の締切" else "チケット当落発表",
        // コアが JOIN 済みの brand の color hex をそのまま使う (brand_id は返らない)。
        brand = row.brandColor?.let(::hexToColor) ?: Color.Gray,
        trailing = trailing,
        onClick = onClick
    )
}

/** チケット受付期間行。被覆する日すべてに出る (受付中であることがその日に分かるように)。 */
@Composable
private fun TicketPeriodRowView(
    row: TicketPeriodRow,
    trailing: (@Composable () -> Unit)?,
    onClick: () -> Unit
) {
    val range = listOfNotNull(monthDay(row.start), monthDay(row.end)).joinToString(" 〜 ")
    IconEntryRow(
        accent = TicketColor,
        icon = Icons.Filled.DateRange,
        label = "受付期間 ・ ${AppPreferences.eventDisplayName(row.eventName)}",
        sub = if (range.isEmpty()) "チケット受付期間" else "チケット受付  $range",
        brand = row.brandColor?.let(::hexToColor) ?: Color.Gray,
        trailing = trailing,
        onClick = onClick
    )
}

/** アイコン付きエントリ行 (事務員誕生日・記念日・チケットなど、リード画像を持たないエントリ用)。 */
@Composable
private fun IconEntryRow(
    accent: Color,
    icon: ImageVector,
    label: String,
    sub: String,
    brand: Color,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null
) {
    val base = Modifier.fillMaxWidth()
    Row(
        modifier = (if (onClick != null) base.clickable(onClick = onClick) else base)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(modifier = Modifier.size(width = 4.dp, height = 36.dp).clip(RoundedCornerShape(2.dp)).background(brand))
        Spacer(Modifier.size(12.dp))
        Icon(imageVector = icon, contentDescription = null, tint = accent, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = DS.ink, maxLines = 2)
            if (sub.isNotEmpty()) {
                Text(sub, style = MaterialTheme.typography.labelSmall, color = DS.ink2, maxLines = 1)
            }
        }
        trailing?.invoke()
    }
}

@Composable
private fun EntryRow(
    accent: Color,
    label: String,
    title: String,
    brand: Color,
    trailing: (@Composable () -> Unit)? = null,
    onClick: () -> Unit
) {
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
        trailing?.invoke()
    }
}

@Composable
private fun ReleaseRows(rows: List<CalReleaseRow>, onSong: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(0.dp)) {
        rows.forEach { song ->
            EntryRow(
                accent = ReleaseColor,
                label = "リリース",
                title = song.title,
                brand = brandColor(song.brandId),
                onClick = { onSong(song.id) }
            )
        }
    }
}
