package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

// =============================================================================
// 帯の時間軸 (ガント) (docs/DESIGN_SYSTEM.md §6.7 会場の部品)。iOS `Events/ImasTimeline.swift` の移植。
//
// 用途: 1 つのライブのチケット受付 (先行・一般・リセール・当日…) の期間を、同じ時間軸の上に
//       横の帯で並べて「いつ何が受付中か・次は何か」を一目で読ませる。
// 使わない場面: 日付が 1 つしかないもの (札か ImasDateMark)。月の予定 (月カレンダー)。
// 構成: ImasTimelineAxis (上の目盛と「今日」) + 行ごとの ImasTimelineTrack (帯・当落の◆・
//       今日の朱の線・公演日の点線・目盛の薄い線) + ImasTimelineLegend (記号の凡例)。
//       軸の位置 (0.0〜1.0) はすべて imas-core が計算して渡す (画面で日付の割り算をしない)。
// 種類: 帯の見え方は 3 つ。ACTIVE 墨の塗り (受付中) / AHEAD 墨の線 (受付前) / PAST 灰の塗り (締切後)。
// 状態: 開始・締切が登録されていない端は閉じずに刻みで描く。角は丸めない。光・影・グラデーションは無い。
// =============================================================================

/** 時間軸の上の 1 点 (目盛・公演日)。[at] は軸の左端 0.0 〜 右端 1.0。 */
@Immutable
data class ImasTimelineMark(val at: Double, val label: String)

/** 軸の目盛と、全行に引く縦の線 (今日・公演日)。 */
@Immutable
data class ImasTimelineScale(
    val ticks: List<ImasTimelineMark>,
    /** 今日の位置。範囲の外なら null。 */
    val today: Double?,
    val shows: List<ImasTimelineMark>
)

/** 帯 1 本。 */
@Immutable
data class ImasTimelineBar(
    val start: Double,
    val end: Double,
    val startOpen: Boolean = false,
    val endOpen: Boolean = false,
    val style: Style
) {
    enum class Style {
        /** 受付中 (墨の塗り)。 */
        ACTIVE,
        /** 受付前 (墨の線)。 */
        AHEAD,
        /** 締切後 (灰の塗り)。 */
        PAST
    }
}

/** 上の目盛 (日付) と「今日」の札。 */
@Composable
fun ImasTimelineAxis(scale: ImasTimelineScale, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().clearAndSetSemantics { }) {
        TimelineLabels(scale.ticks.map { it.at }) { i -> ImasText(scale.ticks[i].label, role = ImasTextRole.META) }
        scale.today?.let { today ->
            TimelineLabels(listOf(today)) { ImasText("今日", role = ImasTextRole.BADGE, color = DS.stamp) }
        }
    }
}

/** 帯 1 本ぶんの線路。目盛の薄い線・公演日の点線・今日の朱の線を下敷きに、帯と当落の◆を描く。 */
@Composable
fun ImasTimelineTrack(
    scale: ImasTimelineScale,
    bar: ImasTimelineBar?,
    modifier: Modifier = Modifier,
    result: Double? = null,
    resultPending: Boolean = false
) {
    val sep = DS.sep
    val ink = DS.ink
    val ink2 = DS.ink2
    val ink3 = DS.ink3
    val line = DS.line
    val surface = DS.surface
    val stamp = DS.stamp
    val density = LocalDensity.current
    val unit = with(density) { 1.dp.toPx() }
    Canvas(modifier.fillMaxWidth().height(18.dp).clearAndSetSemantics { }) {
        val w = size.width
        val h = size.height
        fun x(at: Double) = at.toFloat() * w
        drawLine(sep, Offset(0f, h / 2), Offset(w, h / 2), strokeWidth = unit)
        scale.ticks.forEach { drawRect(sep, Offset(x(it.at), 0f), Size(unit, h)) }
        scale.shows.forEach {
            drawLine(
                ink2, Offset(x(it.at), 0f), Offset(x(it.at), h), strokeWidth = unit,
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(2 * unit, 2 * unit))
            )
        }
        bar?.let { drawBar(it, unit, ink, ink3, line, surface) }
        result?.let { at ->
            val r = h * 0.36f
            val cx = x(at).coerceIn(h * 0.3f, w - h * 0.3f)
            val diamond = Path().apply {
                moveTo(cx, h / 2 - r); lineTo(cx + r, h / 2); lineTo(cx, h / 2 + r); lineTo(cx - r, h / 2); close()
            }
            drawPath(diamond, surface)
            drawPath(diamond, if (resultPending) ink else ink3, style = Stroke(width = 1.5f * unit))
            if (resultPending) {
                val s = r * 0.45f
                drawPath(
                    Path().apply { moveTo(cx, h / 2 - s); lineTo(cx + s, h / 2); lineTo(cx, h / 2 + s); lineTo(cx - s, h / 2); close() },
                    ink
                )
            }
        }
        scale.today?.let { drawRect(stamp, Offset(x(it) - 0.75f * unit, 0f), Size(1.5f * unit, h)) }
    }
}

private fun DrawScope.drawBar(bar: ImasTimelineBar, unit: Float, ink: Color, ink3: Color, line: Color, surface: Color) {
    val w = size.width
    val h = size.height
    val barH = h * 0.7f
    val y = (h - barH) / 2
    val x0 = bar.start.toFloat() * w
    // 1 日の受付でも見えるよう、最低限の幅を持たせる。
    val x1 = maxOf(bar.end.toFloat() * w, x0 + 3 * unit)
    // 開いた端は「刻み」で描く: 実線の帯を刻みの長さぶん手前で止め、残りを細い縦の刻みにする。
    val notch = minOf(12 * unit, (x1 - x0) / 3)
    val solidStart = if (bar.startOpen) x0 + notch else x0
    val solidEnd = if (bar.endOpen) x1 - notch else x1
    val color = if (bar.style == ImasTimelineBar.Style.PAST) ink3 else ink
    val bodySize = Size(maxOf(solidEnd - solidStart, unit), barH)
    when (bar.style) {
        ImasTimelineBar.Style.ACTIVE -> drawRect(ink, Offset(solidStart, y), bodySize)
        ImasTimelineBar.Style.PAST -> drawRect(line, Offset(solidStart, y), bodySize)
        ImasTimelineBar.Style.AHEAD -> {
            drawRect(surface, Offset(solidStart, y), bodySize)
            val inset = 0.75f * unit
            drawRect(
                ink, Offset(solidStart + inset, y + inset),
                Size(bodySize.width - 2 * inset, bodySize.height - 2 * inset), style = Stroke(width = 1.5f * unit)
            )
        }
    }
    fun notches(from: Float, to: Float) {
        var cursor = from
        while (cursor < to - unit) {
            drawRect(color, Offset(cursor, y), Size(1.5f * unit, barH))
            cursor += 3.5f * unit
        }
    }
    if (bar.startOpen) notches(x0, solidStart)
    if (bar.endOpen) notches(solidEnd + 2 * unit, x1)
}

/** 帯の 1 段: 上に受付名 (と段階)、下に線路。段を縦に詰めて重ねるとガントの表になる (iOS `ImasTimelineLane`)。 */
@Composable
fun ImasTimelineLane(
    title: String,
    scale: ImasTimelineScale,
    bar: ImasTimelineBar?,
    modifier: Modifier = Modifier,
    trailing: String? = null,
    result: Double? = null,
    resultPending: Boolean = false
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            ImasText(
                title, role = ImasTextRole.ROW_SUBTITLE, color = DS.ink, maxLines = 1,
                overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
            )
            trailing?.let { ImasText(it, role = ImasTextRole.META) }
        }
        ImasTimelineTrack(scale, bar, result = result, resultPending = resultPending)
    }
}

/** 記号の凡例 (受付中の帯・受付前の帯・当落の◆・公演日・今日)。カードの下に 1 行で添える。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImasTimelineLegend(modifier: Modifier = Modifier) {
    val empty = ImasTimelineScale(emptyList(), null, emptyList())
    FlowRow(
        modifier.clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        LegendItem("受付中", empty, ImasTimelineBar(0.1, 0.9, style = ImasTimelineBar.Style.ACTIVE))
        LegendItem("受付前", empty, ImasTimelineBar(0.1, 0.9, style = ImasTimelineBar.Style.AHEAD))
        LegendItem("締切後", empty, ImasTimelineBar(0.1, 0.9, style = ImasTimelineBar.Style.PAST))
        LegendItem("当落発表", empty, null, result = 0.5)
        LegendItem("公演日", empty.copy(shows = listOf(ImasTimelineMark(0.5, ""))), null)
        LegendItem("今日", empty.copy(today = 0.5), null)
    }
}

@Composable
private fun LegendItem(label: String, scale: ImasTimelineScale, bar: ImasTimelineBar?, result: Double? = null) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasTimelineTrack(scale, bar, Modifier.width(22.dp), result = result, resultPending = true)
        ImasText(label, role = ImasTextRole.META)
    }
}

/** 軸の位置 (0〜1) に文字を置く。端の文字は枠からはみ出さないよう内側へ寄せる。 */
@Composable
private fun TimelineLabels(positions: List<Double>, label: @Composable (Int) -> Unit) {
    Layout(
        content = { positions.indices.forEach { label(it) } },
        modifier = Modifier.fillMaxWidth()
    ) { measurables, constraints ->
        val placeables = measurables.map { it.measure(constraints.copy(minWidth = 0)) }
        val width = constraints.maxWidth
        val height = placeables.maxOfOrNull { it.height } ?: 0
        layout(width, height) {
            placeables.forEachIndexed { i, p ->
                val center = (positions[i] * width).toInt()
                val x = when {
                    positions[i] < 0.08 -> center
                    positions[i] > 0.92 -> center - p.width
                    else -> center - p.width / 2
                }.coerceIn(0, maxOf(0, width - p.width))
                p.place(x, 0)
            }
        }
    }
}
