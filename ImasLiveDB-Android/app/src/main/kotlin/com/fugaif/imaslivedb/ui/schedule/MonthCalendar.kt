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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import java.time.LocalDate

/**
 * 月グリッドの縦寸法。日セルで共有する (iOS `MonthGridMetric` と同値)。
 */
private object MonthGridMetric {
    /** 日番号ゾーン (今日サークル) の高さ。 */
    val numberZone = 26.dp
    /** 日番号ゾーンとバーゾーンの間隔。 */
    val zoneSpacing = 2.dp
    /** 単日バー 1 本の高さ。 */
    val barHeight = 10.dp
    /** バー同士・バーと "+n" の間隔。 */
    val barSpacing = 2.dp
    /** "+n" 行の高さ。 */
    val overflowHeight = 10.dp
    /** バーゾーンの開始 Y (日番号ゾーンの直下)。 */
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

/** 1 週 (行) ぶん。日セルを 7 つ並べる。 */
@Composable
private fun WeekRow(
    state: CalendarUiState,
    weekDays: List<LocalDate>,
    cellHeight: Dp,
    onSelectDate: (LocalDate) -> Unit,
    onShowDay: (LocalDate) -> Unit
) {
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
                    onSelect = { onSelectDate(date) },
                    onShowDay = { onShowDay(date) }
                )
            }
        }
    }
}

/**
 * 月カレンダーの 1 日セル。日番号 + 単日バーを表示する。
 * バーの表示本数はフィットグリッドが割り付けたセル高から逆算し、収まらない分は "+n" に集約する。
 */
@Composable
private fun DayCell(
    state: CalendarUiState,
    date: LocalDate,
    width: Dp,
    height: Dp,
    onSelect: () -> Unit,
    onShowDay: () -> Unit
) {
    val isToday = date == state.today
    val isSelected = date == state.selectedDate
    val isCurrentMonth = date.year == state.yearMonth.year && date.monthValue == state.yearMonth.monthValue

    val bars = state.entriesOn(date)
    val plan = barPlan(bars.size, height)
    val overflow = plan.overflow

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
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(MonthGridMetric.barSpacing)
        ) {
            bars.take(plan.visible).forEach { entry ->
                CalendarEntryBar(entry = entry, height = MonthGridMetric.barHeight)
            }
            if (overflow > 0) {
                Text(
                    "+$overflow",
                    style = ImasTextRole.MICRO.style,
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
 * バーゾーンの利用可能高から表示本数を決める。
 * 1 本も入らないときも必ず "+n" だけは出す — 「その日は空」と誤読させないため。
 */
private fun barPlan(count: Int, cellHeight: Dp): BarPlan {
    if (count <= 0) return BarPlan(0, 0)
    val zone = (cellHeight - MonthGridMetric.bandTop).coerceAtLeast(0.dp)
    val all = MonthGridMetric.barHeight * count + MonthGridMetric.barSpacing * (count - 1)
    if (all <= zone) return BarPlan(count, 0)
    // "+n" の行ぶんを空けてから入る本数を数える。
    val slot = MonthGridMetric.barHeight + MonthGridMetric.barSpacing
    val fit = ((zone - MonthGridMetric.overflowHeight) / slot).toInt()
    val visible = fit.coerceIn(0, count - 1)
    return BarPlan(visible, count - visible)
}
