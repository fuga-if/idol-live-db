package com.fugaif.imaslivedb.ui.schedule

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.model.CalendarEntry
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import java.time.LocalDate

/**
 * 月グリッドの縦寸法。日セルと週行の帯オーバーレイで共有し、両者の縦位置を必ず揃える
 * (iOS `MonthGridMetric` と同値)。
 */
private object MonthGridMetric {
    /** 日番号ゾーン (今日サークル) の高さ。 */
    val numberZone = 26.dp
    /** 日番号ゾーンと帯ゾーンの間隔。 */
    val zoneSpacing = 2.dp
    /** 単日バー 1 本の高さ。 */
    val barHeight = 10.dp
    /** バー同士・バーと "+n" の間隔。 */
    val barSpacing = 2.dp
    /** "+n" 行の高さ。 */
    val overflowHeight = 10.dp
    /** 受付期間帯 1 本の高さ。 */
    val bandHeight = 11.dp
    /** 帯 1 レーンぶんの縦送り。 */
    val bandSlot = bandHeight + barSpacing
    /** 帯ゾーンの開始 Y (日番号ゾーンの直下)。 */
    val bandTop = numberZone + zoneSpacing

    val rowSpacing = 2.dp
    val columnSpacing = 3.dp
    const val ROWS = 6
    const val COLUMNS = 7
}

/** 左右スワイプの判定。誤爆しないよう距離を要求し、連続発火はしない。 */
private val SwipeThreshold = 50.dp

/**
 * フィット型の月グリッド。
 *
 * 親から与えられた高さに 6 行 × 7 列を必ず収める (Apple 純正カレンダーと同方式)。
 * セル高 = (利用可能高 - 行間) / 6 で全セル均等割り付けし、帯はセル高に収まる本数だけ
 * 表示して残りを "+n" に集約するので、どの月・どの端末サイズでもあふれない。
 */
@Composable
fun MonthCalendar(
    state: CalendarUiState,
    onSelectDate: (LocalDate) -> Unit,
    onShowDay: (LocalDate) -> Unit,
    onMonthDelta: (Long) -> Unit,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current
    val threshold = with(density) { SwipeThreshold.toPx() }
    var dragTotal by remember { mutableFloatStateOf(0f) }

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .pointerInput(state.yearMonth) {
                detectHorizontalDragGestures(
                    onDragStart = { dragTotal = 0f },
                    onDragEnd = {
                        // 左スワイプ = 次の月 (紙をめくる向き)。
                        if (dragTotal <= -threshold) onMonthDelta(1)
                        else if (dragTotal >= threshold) onMonthDelta(-1)
                    },
                    onHorizontalDrag = { _, delta -> dragTotal += delta }
                )
            }
    ) {
        val cellHeight = ((maxHeight - MonthGridMetric.rowSpacing * (MonthGridMetric.ROWS - 1)) /
            MonthGridMetric.ROWS).coerceAtLeast(0.dp)
        Column(verticalArrangement = Arrangement.spacedBy(MonthGridMetric.rowSpacing)) {
            for (row in 0 until MonthGridMetric.ROWS) {
                WeekRow(
                    state = state,
                    weekDays = state.weekDays(row),
                    cellHeight = cellHeight,
                    onSelectDate = onSelectDate,
                    onShowDay = onShowDay
                )
            }
        }
    }
}

/**
 * 1 週 (行) ぶん。日セルを 7 つ並べ、その上に受付期間の連続帯を重ねる。
 * 帯を行のオーバーレイにするのは、セル間の隙間も塗って 1 本に繋げるため
 * (セルごとに描くとセグメントが切れて線が途切れて見える)。
 */
@Composable
private fun WeekRow(
    state: CalendarUiState,
    weekDays: List<LocalDate>,
    cellHeight: Dp,
    onSelectDate: (LocalDate) -> Unit,
    onShowDay: (LocalDate) -> Unit
) {
    // 帯詰めはコアへの FFI を挟むので、週と読み込み結果が変わらない限り引き直さない。
    val bands = remember(weekDays.first(), state.byDate, state.showTickets) {
        if (state.showTickets) packPeriodBands(weekDays, state.byDate) else emptyList()
    }
    val lanes = laneCount(bands)
    val bandInset = MonthGridMetric.bandSlot * lanes

    BoxWithConstraints(modifier = Modifier.fillMaxWidth().height(cellHeight)) {
        val cellWidth = (maxWidth - MonthGridMetric.columnSpacing * (MonthGridMetric.COLUMNS - 1)) /
            MonthGridMetric.COLUMNS
        Row(horizontalArrangement = Arrangement.spacedBy(MonthGridMetric.columnSpacing)) {
            weekDays.forEach { date ->
                DayCell(
                    state = state,
                    date = date,
                    width = cellWidth,
                    height = cellHeight,
                    bandInset = bandInset,
                    onSelect = { onSelectDate(date) },
                    onShowDay = { onShowDay(date) }
                )
            }
        }
        bands.forEach { band ->
            val step = cellWidth + MonthGridMetric.columnSpacing
            PeriodBandView(
                band = band,
                x = step * band.startCol,
                y = MonthGridMetric.bandTop + MonthGridMetric.bandSlot * band.lane,
                width = step * (band.endCol - band.startCol) + cellWidth,
                height = MonthGridMetric.bandHeight,
                fontSize = 8.sp,
                // 帯は週をまたぐので、この週で帯が始まる列の日を開く。
                onClick = { onShowDay(weekDays[band.startCol]) }
            )
        }
    }
}

/** 受付期間の連続帯。週をまたぐ端は角を丸めないので「まだ続く」ことが見える。 */
@Composable
private fun PeriodBandView(
    band: CalendarPeriodBand,
    x: Dp,
    y: Dp,
    width: Dp,
    height: Dp,
    fontSize: androidx.compose.ui.unit.TextUnit,
    onClick: () -> Unit
) {
    val accent = TicketColor
    val radius = 2.dp
    Box(
        modifier = Modifier
            .offset(x = x, y = y)
            .width(width)
            .height(height)
            .clip(
                RoundedCornerShape(
                    topStart = if (band.roundLeading) radius else 0.dp,
                    bottomStart = if (band.roundLeading) radius else 0.dp,
                    topEnd = if (band.roundTrailing) radius else 0.dp,
                    bottomEnd = if (band.roundTrailing) radius else 0.dp
                )
            )
            .background(accent)
            .clickable(onClick = onClick)
            .padding(horizontal = 3.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        // ラベルは受付開始の週にだけ出す。続きの週にも出すと同じ文字列が毎週並んでうるさい。
        if (band.roundLeading) {
            Text(
                "受付 ${band.name}",
                color = ImasTheme.onColor(accent),
                fontSize = fontSize,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    }
}

/**
 * 月カレンダーの 1 日セル。日番号 + 単日バーを表示する。
 *
 * 受付期間の帯は週行オーバーレイ側で描くので、上部に [bandInset] (この週のレーン数ぶん) を
 * 空けてバーが帯と重ならないようにする。バーの表示本数はフィットグリッドが割り付けた
 * セル高から逆算し、収まらない分は "+n" に集約する。
 */
@Composable
private fun DayCell(
    state: CalendarUiState,
    date: LocalDate,
    width: Dp,
    height: Dp,
    bandInset: Dp,
    onSelect: () -> Unit,
    onShowDay: () -> Unit
) {
    val isToday = date == state.today
    val isSelected = date == state.selectedDate
    val isCurrentMonth = date.year == state.yearMonth.year && date.monthValue == state.yearMonth.monthValue

    // 受付期間は帯で描くのでバーからは外す (iOS `barEntries` と同じ)。
    val bars = state.entriesOn(date).filterNot { it is CalendarEntry.TicketPeriod }
    val plan = barPlan(bars.size, height, bandInset)

    Column(
        modifier = Modifier
            .width(width)
            .height(height)
            .clip(RoundedCornerShape(6.dp))
            .background(if (isSelected && !isToday) DS.fill else Color.Transparent)
            .clickable(onClick = onSelect),
        verticalArrangement = Arrangement.spacedBy(MonthGridMetric.zoneSpacing)
    ) {
        Box(
            modifier = Modifier.fillMaxWidth().height(MonthGridMetric.numberZone),
            contentAlignment = Alignment.Center
        ) {
            Box(
                modifier = Modifier
                    .size(MonthGridMetric.numberZone)
                    .clip(CircleShape)
                    .background(if (isToday) DS.sys else Color.Transparent),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "${date.dayOfMonth}",
                    fontSize = 13.sp,
                    fontWeight = if (isToday) FontWeight.Bold else FontWeight.Medium,
                    color = when {
                        isToday -> DS.onSys
                        !isCurrentMonth -> DS.ink3
                        else -> DS.ink
                    }
                )
            }
        }
        Column(
            modifier = Modifier.fillMaxWidth().padding(top = bandInset),
            verticalArrangement = Arrangement.spacedBy(MonthGridMetric.barSpacing)
        ) {
            bars.take(plan.visible).forEach { entry ->
                CalendarEntryBar(entry = entry, height = MonthGridMetric.barHeight)
            }
            if (plan.overflow > 0) {
                Text(
                    "+${plan.overflow}",
                    fontSize = 8.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = DS.ink3,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(MonthGridMetric.overflowHeight)
                        .clickable(onClick = onShowDay)
                )
            }
        }
    }
}

/** (表示本数, "+n" の n)。 */
private data class BarPlan(val visible: Int, val overflow: Int)

/**
 * バーゾーンの利用可能高 (帯ぶんを差し引いた残り) から表示本数を決める。
 * 1 本も入らないときも必ず "+n" だけは出す — 「その日は空」と誤読させないため。
 */
private fun barPlan(count: Int, cellHeight: Dp, bandInset: Dp): BarPlan {
    if (count <= 0) return BarPlan(0, 0)
    val zone = (cellHeight - MonthGridMetric.bandTop - bandInset).coerceAtLeast(0.dp)
    val all = MonthGridMetric.barHeight * count + MonthGridMetric.barSpacing * (count - 1)
    if (all <= zone) return BarPlan(count, 0)
    val slot = MonthGridMetric.barHeight + MonthGridMetric.barSpacing
    val fit = ((zone - MonthGridMetric.overflowHeight) / slot).toInt()
    val visible = fit.coerceIn(0, count - 1)
    return BarPlan(visible, count - visible)
}
