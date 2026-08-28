package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlinx.coroutines.delay
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Google カレンダー風の時間グリッド週ビュー (iOS `WeekTimeGridView` の移植)。
 *
 * 上から: 週送りヘッダ / 曜日+日付ヘッダ / 受付期間の連続帯 / 終日・時刻未定レーン /
 * 時間グリッド (縦スクロール)。列幅は (全体幅 - 時刻ガター) / 7 の固定値、時間軸も
 * 固定スケールなので、週送りやイベント数の増減でレイアウトが動かない。
 */
private object WeekMetric {
    /** 時間軸の表示範囲 (6:00 〜 24:00)。深夜公演は無いのでこの窓で足りる。 */
    const val START_HOUR = 6
    const val END_HOUR = 24
    val hourHeight = 44.dp
    /** 左端の時刻ラベル列の幅。 */
    val gutter = 44.dp
    /** 終了時刻データが無い公演に与える仮の長さ (分)。 */
    const val DEFAULT_SHOW_MINUTES = 120
    /** ブロックの最小高さ (短すぎてタップ不能になるのを防ぐ)。 */
    val minBlockHeight = 20.dp
    val gridHeight = hourHeight * (END_HOUR - START_HOUR)

    /** 終日レーンに出す最大帯数 (超過分は "+n")。 */
    const val MAX_ALL_DAY_BANDS = 2
    val allDayBarHeight = 15.dp
    val bandHeight = 16.dp
    val bandGap = 2.dp
}

private val WeekSwipeThreshold = 50.dp
private val WeekdaySymbols = listOf("日", "月", "火", "水", "木", "金", "土")

/** 時間グリッドに置く 1 ブロック。 */
private data class TimedBlock(
    val id: String,
    val entry: CalendarEntry,
    val startMinutes: Int,
    val endMinutes: Int,
    val lane: Int = 0,
    val isHalfWidth: Boolean = false
)

/** 2 列に収まらなかった分の集約バッジ。 */
private data class OverflowBadge(val startMinutes: Int, val count: Int)

@Composable
fun WeekTimeGrid(
    state: CalendarUiState,
    anchor: LocalDate,
    onSelectDate: (LocalDate) -> Unit,
    onSelectEntry: (CalendarEntry) -> Unit,
    onShowDay: (LocalDate) -> Unit,
    onWeekDelta: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    val weekDays = remember(anchor) { weekOf(anchor) }
    val density = LocalDensity.current
    val threshold = with(density) { WeekSwipeThreshold.toPx() }
    var dragTotal by remember { mutableFloatStateOf(0f) }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(anchor) {
                detectHorizontalDragGestures(
                    onDragStart = { dragTotal = 0f },
                    onDragEnd = {
                        if (dragTotal <= -threshold) onWeekDelta(1)
                        else if (dragTotal >= threshold) onWeekDelta(-1)
                    },
                    onHorizontalDrag = { _, delta -> dragTotal += delta }
                )
            }
    ) {
        val dayWidth = (maxWidth - WeekMetric.gutter) / 7
        Column(modifier = Modifier.fillMaxSize()) {
            WeekHeader(weekDays = weekDays, onWeekDelta = onWeekDelta)
            DayHeaderRow(state = state, weekDays = weekDays, dayWidth = dayWidth, onSelectDate = onSelectDate)
            PeriodBandLane(state = state, weekDays = weekDays, dayWidth = dayWidth, onShowDay = onShowDay)
            AllDayLane(
                state = state,
                weekDays = weekDays,
                dayWidth = dayWidth,
                onSelectEntry = onSelectEntry,
                onShowDay = onShowDay
            )
            HorizontalDivider(color = DS.sep)
            TimeGrid(
                state = state,
                weekDays = weekDays,
                dayWidth = dayWidth,
                onSelectEntry = onSelectEntry,
                onShowDay = onShowDay,
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun WeekHeader(weekDays: List<LocalDate>, onWeekDelta: (Long) -> Unit) {
    val start = weekDays.first()
    val end = weekDays.last()
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        IconButton(onClick = { onWeekDelta(-1) }) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "前の週", tint = DS.ink2)
        }
        Text(
            "${start.monthValue}/${start.dayOfMonth} 〜 ${end.monthValue}/${end.dayOfMonth}",
            modifier = Modifier.weight(1f),
            textAlign = TextAlign.Center,
            fontSize = 15.sp,
            fontWeight = FontWeight.Bold,
            color = DS.ink
        )
        IconButton(onClick = { onWeekDelta(1) }) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "次の週", tint = DS.ink2)
        }
    }
}

@Composable
private fun DayHeaderRow(
    state: CalendarUiState,
    weekDays: List<LocalDate>,
    dayWidth: Dp,
    onSelectDate: (LocalDate) -> Unit
) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Box(modifier = Modifier.width(WeekMetric.gutter))
        weekDays.forEachIndexed { index, date ->
            val isToday = date == state.today
            val isSelected = date == state.selectedDate
            Column(
                modifier = Modifier
                    .width(dayWidth)
                    .clickable { onSelectDate(date) }
                    .padding(vertical = 2.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                Text(
                    WeekdaySymbols[index],
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = if (isToday) DS.ink else DS.ink3
                )
                Box(
                    modifier = Modifier
                        .size(28.dp)
                        .clip(CircleShape)
                        .background(if (isToday) DS.sys else Color.Transparent)
                        // 選択日は輪郭だけ。今日と選択日が重なったときは塗りが勝つ。
                        .then(
                            if (isSelected && !isToday) Modifier.border(1.5.dp, DS.sys, CircleShape)
                            else Modifier
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Text(
                        "${date.dayOfMonth}",
                        fontSize = 14.sp,
                        fontWeight = if (isToday) FontWeight.Bold else FontWeight.Medium,
                        color = if (isToday) DS.onSys else DS.ink
                    )
                }
            }
        }
    }
}

/**
 * 受付期間の連続帯レーン。列インデックス算出とレーン詰めは月グリッドと共通
 * ([packPeriodBands])。座標系だけがここ専用 (ガター幅ぶん右にずれる)。
 */
@Composable
private fun PeriodBandLane(
    state: CalendarUiState,
    weekDays: List<LocalDate>,
    dayWidth: Dp,
    onShowDay: (LocalDate) -> Unit
) {
    val bands = remember(weekDays.first(), state.byDate, state.showTickets) {
        if (state.showTickets) packPeriodBands(weekDays, state.byDate) else emptyList()
    }
    val lanes = laneCount(bands)
    if (lanes == 0) return
    val laneHeight = WeekMetric.bandHeight + WeekMetric.bandGap
    Box(modifier = Modifier.fillMaxWidth().height(laneHeight * lanes - WeekMetric.bandGap)) {
        bands.forEach { band ->
            val accent = TicketColor
            val radius = 4.dp
            Box(
                modifier = Modifier
                    .offset(
                        x = WeekMetric.gutter + dayWidth * band.startCol + 1.dp,
                        y = laneHeight * band.lane
                    )
                    .width((dayWidth * (band.endCol - band.startCol + 1) - 2.dp).coerceAtLeast(0.dp))
                    .height(WeekMetric.bandHeight)
                    .clip(
                        RoundedCornerShape(
                            topStart = if (band.roundLeading) radius else 0.dp,
                            bottomStart = if (band.roundLeading) radius else 0.dp,
                            topEnd = if (band.roundTrailing) radius else 0.dp,
                            bottomEnd = if (band.roundTrailing) radius else 0.dp
                        )
                    )
                    .background(accent)
                    .clickable { onShowDay(weekDays[band.startCol]) }
                    .padding(horizontal = 6.dp),
                contentAlignment = Alignment.CenterStart
            ) {
                Text(
                    "受付 ${band.name}",
                    color = ImasTheme.onColor(accent),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
            }
        }
    }
}

/** 終日 / 時刻未定レーン。時間軸に置けないエントリはすべてここに落ちる。 */
@Composable
private fun AllDayLane(
    state: CalendarUiState,
    weekDays: List<LocalDate>,
    dayWidth: Dp,
    onSelectEntry: (CalendarEntry) -> Unit,
    onShowDay: (LocalDate) -> Unit
) {
    val laneHeight = WeekMetric.allDayBarHeight * WeekMetric.MAX_ALL_DAY_BANDS + 2.dp + 13.dp
    Row(modifier = Modifier.fillMaxWidth().height(laneHeight)) {
        Text(
            "終日",
            modifier = Modifier.width(WeekMetric.gutter),
            fontSize = 9.sp,
            fontWeight = FontWeight.SemiBold,
            color = DS.ink3,
            textAlign = TextAlign.Center
        )
        weekDays.forEach { date ->
            val entries = state.allDayEntries(date)
            Column(
                modifier = Modifier.width(dayWidth).padding(horizontal = 1.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp)
            ) {
                entries.take(WeekMetric.MAX_ALL_DAY_BANDS).forEach { entry ->
                    CalendarEntryBar(
                        entry = entry,
                        height = WeekMetric.allDayBarHeight,
                        fontSize = 9.sp,
                        modifier = Modifier.clickable { onSelectEntry(entry) }
                    )
                }
                if (entries.size > WeekMetric.MAX_ALL_DAY_BANDS) {
                    Text(
                        "+${entries.size - WeekMetric.MAX_ALL_DAY_BANDS}",
                        fontSize = 9.sp,
                        fontWeight = FontWeight.SemiBold,
                        color = DS.ink2,
                        modifier = Modifier.fillMaxWidth().clickable { onShowDay(date) }
                    )
                }
            }
        }
    }
}

@Composable
private fun TimeGrid(
    state: CalendarUiState,
    weekDays: List<LocalDate>,
    dayWidth: Dp,
    onSelectEntry: (CalendarEntry) -> Unit,
    onShowDay: (LocalDate) -> Unit,
    modifier: Modifier = Modifier
) {
    val scrollState = rememberScrollState()
    val density = LocalDensity.current

    // 初期スクロール位置: その週で一番早いイベントの時刻、無ければ 9:00。
    val firstHour = remember(weekDays.first(), state.byDate) {
        val minutes = weekDays.flatMap { state.timedBlocks(it) }.minOfOrNull { it.startMinutes }
        minutes?.let { (it / 60).coerceIn(WeekMetric.START_HOUR, WeekMetric.END_HOUR - 1) } ?: 9
    }
    LaunchedEffect(firstHour, weekDays.first()) {
        val y = with(density) { (WeekMetric.hourHeight * (firstHour - WeekMetric.START_HOUR)).toPx() }
        scrollState.scrollTo(y.toInt())
    }

    Box(modifier = modifier.fillMaxWidth().verticalScroll(scrollState)) {
        Box(modifier = Modifier.fillMaxWidth().height(WeekMetric.gridHeight + 24.dp)) {
            HourRows()
            VerticalSeparators(dayWidth)
            weekDays.forEachIndexed { index, date ->
                DayBlocks(
                    state = state,
                    date = date,
                    originX = WeekMetric.gutter + dayWidth * index,
                    dayWidth = dayWidth,
                    onSelectEntry = onSelectEntry,
                    onShowDay = onShowDay
                )
            }
            NowIndicator(state = state, weekDays = weekDays, dayWidth = dayWidth)
        }
    }
}

/** 1 時間ごとの罫線 + 時刻ラベル。 */
@Composable
private fun HourRows() {
    Column {
        for (hour in WeekMetric.START_HOUR until WeekMetric.END_HOUR) {
            Box(modifier = Modifier.fillMaxWidth().height(WeekMetric.hourHeight)) {
                HorizontalDivider(
                    modifier = Modifier.padding(start = WeekMetric.gutter),
                    color = DS.sep
                )
                Text(
                    "$hour:00",
                    modifier = Modifier
                        .width(WeekMetric.gutter - 6.dp)
                        .offset(y = (-5).dp),
                    textAlign = TextAlign.End,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Medium,
                    color = DS.ink3
                )
            }
        }
    }
}

@Composable
private fun VerticalSeparators(dayWidth: Dp) {
    for (i in 0..7) {
        Box(
            modifier = Modifier
                .offset(x = WeekMetric.gutter + dayWidth * i)
                .width(1.dp)
                .height(WeekMetric.gridHeight)
                .background(DS.sep)
        )
    }
}

/** 1 日ぶんのブロック + "+n" バッジ。 */
@Composable
private fun DayBlocks(
    state: CalendarUiState,
    date: LocalDate,
    originX: Dp,
    dayWidth: Dp,
    onSelectEntry: (CalendarEntry) -> Unit,
    onShowDay: (LocalDate) -> Unit
) {
    val layout = remember(date, state.byDate, state.showDetails) {
        layoutTimedBlocks(state.timedBlocks(date))
    }
    layout.first.forEach { block ->
        val width = if (block.isHalfWidth) (dayWidth - 2.dp) / 2 else dayWidth - 2.dp
        val x = originX + 1.dp + if (block.isHalfWidth) (dayWidth - 2.dp) / 2 * block.lane else 0.dp
        Column(
            modifier = Modifier
                .offset(x = x, y = yPosition(block.startMinutes))
                .width(width)
                .height(blockHeight(block))
                .clip(RoundedCornerShape(5.dp))
                .background(block.entry.accentColor())
                .clickable { onSelectEntry(block.entry) }
                .padding(4.dp)
        ) {
            Text(
                block.entry.barLabel(),
                color = block.entry.accentInk(),
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis
            )
            Text(
                timeLabel(block.startMinutes),
                color = block.entry.accentInk(),
                fontSize = 9.sp,
                fontWeight = FontWeight.Medium
            )
        }
    }
    layout.second.forEach { badge ->
        Box(
            modifier = Modifier
                .offset(x = originX + dayWidth - 26.dp, y = yPosition(badge.startMinutes) + 2.dp)
                .clip(RoundedCornerShape(50))
                .background(DS.sys)
                .clickable { onShowDay(date) }
                .padding(horizontal = 6.dp, vertical = 2.dp)
        ) {
            Text("+${badge.count}", color = DS.onSys, fontSize = 9.sp, fontWeight = FontWeight.Bold)
        }
    }
}

/**
 * 現在時刻の赤線。時刻は JST 固定 (グリッドの「今日」も JST なので、端末が別 TZ でも
 * 線と日付がずれない)。1 分ごとに引き直す。
 */
@Composable
private fun NowIndicator(state: CalendarUiState, weekDays: List<LocalDate>, dayWidth: Dp) {
    val todayIndex = weekDays.indexOf(state.today)
    if (todayIndex < 0) return
    val minutes by produceState(initialValue = nowMinutesJst()) {
        while (true) {
            value = nowMinutesJst()
            delay(60_000)
        }
    }
    if (minutes < WeekMetric.START_HOUR * 60 || minutes > WeekMetric.END_HOUR * 60) return
    Row(
        modifier = Modifier
            .offset(
                x = WeekMetric.gutter + dayWidth * todayIndex - 3.5.dp,
                y = yPosition(minutes) - 3.5.dp
            )
            .width(dayWidth + 3.5.dp)
            .height(7.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(modifier = Modifier.size(7.dp).clip(CircleShape).background(DS.danger))
        Box(modifier = Modifier.weight(1f).height(1.5.dp).background(DS.danger))
    }
}

private fun nowMinutesJst(): Int =
    ZonedDateTime.now(ZoneId.of("Asia/Tokyo")).let { it.hour * 60 + it.minute }

// ---- エントリの振り分けと重なりレイアウト ----

/** 終日レーン行き: 時刻を持たないエントリ。受付期間は連続帯で描くので除外する。 */
private fun CalendarUiState.allDayEntries(date: LocalDate): List<CalendarEntry> =
    entriesOn(date).filter { it !is CalendarEntry.TicketPeriod && startMinutesOf(it) == null }

/** 時間グリッド行き: 開始時刻を持つエントリをブロック化する。 */
private fun CalendarUiState.timedBlocks(date: LocalDate): List<TimedBlock> =
    entriesOn(date).mapNotNull { entry ->
        val start = startMinutesOf(entry) ?: return@mapNotNull null
        TimedBlock(
            id = blockId(entry),
            entry = entry,
            startMinutes = start,
            // 終了時刻のデータが無いので、公演は仮に 2 時間ぶんの高さで描く。
            endMinutes = (start + WeekMetric.DEFAULT_SHOW_MINUTES).coerceAtMost(24 * 60)
        )
    }

/**
 * 時間軸に置ける開始分。時刻を持つのは公演だけで、それも開始時刻が登録されている場合に限る
 * (誕生日・リリース・記念日・チケットは日付しか持たない)。
 */
private fun CalendarUiState.startMinutesOf(entry: CalendarEntry): Int? {
    if (entry !is CalendarEntry.Show) return null
    return parseTimeMinutes(showDetails[entry.row.showId]?.startTime)
}

private fun blockId(entry: CalendarEntry): String = when (entry) {
    is CalendarEntry.Show -> entry.row.showId
    is CalendarEntry.Release -> "release-${entry.date}"
    is CalendarEntry.Birthday -> "bd-${entry.row.id}"
    is CalendarEntry.StaffBirthday -> "sbd-${entry.row.id}"
    is CalendarEntry.Anniversary -> "ann-${entry.row.id}-${entry.date}"
    is CalendarEntry.Ticket -> "tk-${entry.row.eventId}-${entry.date}"
    is CalendarEntry.TicketPeriod -> "tp-${entry.row.eventId}"
}

/** "HH:MM" → 0:00 からの経過分。壊れた値・範囲外は null。 */
internal fun parseTimeMinutes(time: String?): Int? {
    val parts = time?.split(":") ?: return null
    if (parts.size != 2) return null
    val h = parts[0].toIntOrNull() ?: return null
    val m = parts[1].toIntOrNull() ?: return null
    if (h !in 0..23 || m !in 0..59) return null
    return h * 60 + m
}

/**
 * 同時刻の重なりを最大 2 列に振り分け、収まらない分を "+n" に集約する
 * (iOS `layoutTimedBlocks` の写し)。3 列以上に割ると 1 ブロックが細すぎて読めなくなる。
 */
private fun layoutTimedBlocks(blocks: List<TimedBlock>): Pair<List<TimedBlock>, List<OverflowBadge>> {
    val sorted = blocks.sortedWith(compareBy({ it.startMinutes }, { it.endMinutes }))
    val visible = mutableListOf<TimedBlock>()
    val hidden = mutableListOf<TimedBlock>()
    val laneEnds = intArrayOf(Int.MIN_VALUE, Int.MIN_VALUE)

    for (block in sorted) {
        val lane = laneEnds.indices.firstOrNull { laneEnds[it] <= block.startMinutes }
        if (lane == null) {
            hidden += block
        } else {
            laneEnds[lane] = block.endMinutes
            visible += block.copy(lane = lane)
        }
    }

    // 他の可視ブロックと時間帯が重なるものだけ半分幅にする (単独なら全幅で読みやすく)。
    val widened = visible.map { a ->
        a.copy(
            isHalfWidth = visible.any { b ->
                b.id != a.id && a.startMinutes < b.endMinutes && b.startMinutes < a.endMinutes
            }
        )
    }
    val overflow = hidden.groupBy { it.startMinutes }
        .map { (start, list) -> OverflowBadge(start, list.size) }
        .sortedBy { it.startMinutes }
    return widened to overflow
}

private fun yPosition(minutes: Int): Dp {
    val raw = WeekMetric.hourHeight * ((minutes - WeekMetric.START_HOUR * 60) / 60f)
    return raw.coerceIn(0.dp, WeekMetric.gridHeight)
}

private fun blockHeight(block: TimedBlock): Dp =
    (yPosition(block.endMinutes) - yPosition(block.startMinutes)).coerceAtLeast(WeekMetric.minBlockHeight)

private fun timeLabel(minutes: Int): String = "%d:%02d".format(minutes / 60, minutes % 60)
