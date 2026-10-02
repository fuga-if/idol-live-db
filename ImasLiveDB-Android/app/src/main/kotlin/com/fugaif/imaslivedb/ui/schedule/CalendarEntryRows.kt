package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Album
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.MailOutline
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Person
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import com.fugaif.imaslivedb.data.model.CalReleaseRow
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.data.model.TicketCalendarRow
import com.fugaif.imaslivedb.data.model.TicketDateKind
import com.fugaif.imaslivedb.data.model.TicketPeriodRow
import com.fugaif.imaslivedb.data.model.Vocab
import com.fugaif.imaslivedb.data.repository.CalendarShowDetail
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeadBar
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.imasRowPress

/**
 * 選択日の予定 1 行。スケジュール画面のインラインリストと日詳細シートで共有する
 * (iOS `DayEntryRow` と同じ位置づけ)。記号 (`ImasRowLeading.Icon`) 自体を種別の色で点け、
 * 行頭に別立ての色の帯は敷かない (iOS と同じ構成。iOS にある記念日アイコンの出し分け・
 * 誕生日の gift アイコン・公演のスワイプは Android に無い機能なので足さない)。
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
        is CalendarEntry.Show -> {
            // 公演名・開始時刻・会場を副題に畳む (iOS の showRow と同じ並び)。
            val sub = listOfNotNull(
                entry.row.showName.takeIf { it.isNotBlank() },
                showDetail?.startTime,
                showDetail?.venue
            ).joinToString(" ・ ")
            EntryRow(
                icon = Icons.Filled.Mic,
                brand = entry.row.brandId,
                leadBar = ImasRowLeadBar(brand = entry.row.brandId),
                title = AppPreferences.eventDisplayName(entry.row.eventName),
                subtitle = sub.ifEmpty { null },
                trailing = trailing,
                onClick = { onNavigateToShow(entry.row.showId) }
            )
        }

        is CalendarEntry.Birthday -> EntryRow(
            icon = Icons.Filled.CardGiftcard,
            // CalBirthdayRow はアイドル本人の色を運んでいないので、誕生日の桃で点ける (前の Android と同じ)。
            seed = CalendarThemeSeed.STAFF_BIRTHDAY,
            tone = ImasIconTileTone.THEMED,
            leadBar = ImasRowLeadBar(brand = entry.row.brandId),
            title = entry.row.name,
            subtitle = "誕生日",
            trailing = trailing,
            onClick = { onNavigateToIdol(entry.row.id) }
        )

        is CalendarEntry.Release -> ReleaseRows(entry.songs, trailing, onNavigateToSong)

        is CalendarEntry.StaffBirthday -> EntryRow(
            icon = Icons.Filled.Person,
            seed = CalendarThemeSeed.STAFF_BIRTHDAY,
            leadBar = ImasRowLeadBar(brand = entry.row.brandId),
            title = "${entry.row.name} 誕生日",
            subtitle = entry.row.role,
            trailing = trailing
        )

        is CalendarEntry.Anniversary -> EntryRow(
            icon = Icons.Filled.AutoAwesome,
            seed = CalendarThemeSeed.ANNIVERSARY,
            leadBar = ImasRowLeadBar(brand = entry.row.brandId),
            title = if (entry.years == 0) "${entry.row.label} (初日)" else "${entry.years}周年 ・ ${entry.row.label}",
            subtitle = "${entry.row.date.take(4)} 起点",
            showsChevron = false,
            trailing = trailing
        )

        is CalendarEntry.Ticket -> TicketRow(entry.row, trailing) { onNavigateToEvent(entry.row.eventId) }

        is CalendarEntry.TicketPeriod ->
            TicketPeriodRowView(entry.row, trailing) { onNavigateToEvent(entry.row.eventId) }
    }
}

/** チケット日程行 (受付開始 / 申込締切 / 当落発表)。タップで親イベント詳細へ。 */
@Composable
private fun TicketRow(row: TicketCalendarRow, trailing: (@Composable () -> Unit)?, onClick: () -> Unit) {
    EntryRow(
        icon = when (row.kind) {
            TicketDateKind.DEADLINE -> Icons.Filled.ConfirmationNumber
            TicketDateKind.LOTTERY -> Icons.Filled.MailOutline
            TicketDateKind.START -> Icons.Filled.DateRange
        },
        // 申込締切は「その日までにやること」なので緊急の記号色、それ以外はチケット系の藍 (iOS と同じ)。
        seed = if (row.kind == TicketDateKind.DEADLINE) null else CalendarThemeSeed.TICKET,
        tone = if (row.kind == TicketDateKind.DEADLINE) ImasIconTileTone.NEGATIVE else ImasIconTileTone.THEMED,
        // コアが JOIN 済みの brand の色 (brand_id は返らない)。
        leadBar = ImasRowLeadBar(seed = row.brandColor),
        // ライブ名が分かるように、コアが組んだ label (`"{event_name} ({sale_name})"`) をそのまま使う (M2)。
        title = "${row.kind.label} ・ ${row.label}",
        subtitle = when (row.kind) {
            TicketDateKind.DEADLINE -> "チケット申込の締切"
            TicketDateKind.LOTTERY -> "チケット当落発表"
            TicketDateKind.START -> "チケット受付開始"
        },
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
    EntryRow(
        icon = Icons.Filled.DateRange,
        seed = CalendarThemeSeed.TICKET,
        leadBar = ImasRowLeadBar(seed = row.brandColor),
        title = "${Vocab.table.ticketPeriodLabel} ・ ${row.label}",
        subtitle = if (range.isEmpty()) "チケット受付期間" else "チケット受付  $range",
        trailing = trailing,
        onClick = onClick
    )
}

/**
 * 予定 1 行の共通シェル (iOS `DayEntryRow.rowShell` = `ImasRow(density: .compact)`)。
 * [seed] / [brand] は記号を点ける色の手がかり (渡さなければ墨)。
 */
@Composable
private fun EntryRow(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    seed: String? = null,
    brand: String? = null,
    tone: ImasIconTileTone = ImasIconTileTone.THEMED,
    leadBar: ImasRowLeadBar? = null,
    showsChevron: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)? = null
) {
    ImasRow(
        title = title,
        modifier = modifier.then(if (onClick != null) Modifier.imasRowPress(onClick = onClick) else Modifier),
        subtitle = subtitle,
        leading = ImasRowLeading.Icon(icon, tone = tone, seed = seed, brand = brand),
        leadBar = leadBar,
        trailing = when {
            trailing != null -> ImasRowTrailing.Custom(trailing)
            showsChevron && onClick != null -> ImasRowTrailing.Chevron
            else -> ImasRowTrailing.None
        },
        density = ImasRowDensity.COMPACT
    )
}

@Composable
private fun ReleaseRows(rows: List<CalReleaseRow>, trailing: (@Composable () -> Unit)?, onSong: (String) -> Unit) {
    rows.forEach { song ->
        EntryRow(
            icon = Icons.Filled.Album,
            tone = ImasIconTileTone.ATTENTION,
            leadBar = ImasRowLeadBar(brand = song.brandId),
            title = song.title,
            subtitle = "リリース",
            trailing = trailing,
            onClick = { onSong(song.id) }
        )
    }
}
