package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import kotlin.math.roundToInt

// =============================================================================
// ImasStepSlider 段のついた横のスライダー。iOS `ImasStepSlider.swift` の移植。少数 (2〜5) の段から 1 つを、指で引いて選ぶ。
//
// 用途   段に順序のある値 (担当ブランドの「なし / 担当 / メイン」など)。並びが「弱い → 強い」の向きを持つもの。
// 使わない 順序の無い選択肢 → `ImasSegmented` / オンオフ → `ImasToggleRow`。
// 構成   墨の細い溝に段の目盛り (小さな丸)、選んだ段までを実体の色 (無ければ墨) で埋め、つまみ (紙の丸に色の縁) を置く。
//        段の名前は目盛りの下に並べ、選んだ段だけ墨の太字。
// 操作   横に引くとつまみが指に付いてきて、段をまたぐたびに触覚を返し、離すと近い段に吸い付く。段の名前を押しても選べる。
//        触れただけ・縦に引いただけでは動かない (一覧のスクロールの指で値を変えない)。
//        TalkBack では調整できる値 (音量キー・上下のスワイプで 1 段ずつ) として読む。
// 種類   `ImasStepSlider` (スライダーだけ) / `ImasStepSliderRow` (行頭の色の帯 + 題 + スライダーの 1 行。設定の一覧用)。
// 状態   段 0 は溝だけ (埋めない)。
// =============================================================================

/**
 * 段のついた横のスライダー。
 *
 * @param steps 段の名前 (左から)。
 * @param label 読み上げの題 (「765AS の担当」)。
 */
@Composable
fun ImasStepSlider(
    steps: List<String>,
    index: Int,
    onIndexChange: (Int) -> Unit,
    label: String,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null
) {
    val t = imasThemeForBrand(seed, brand)
    val accent = if (t.isNeutral) DS.sys else t.accent
    val haptics = rememberImasHaptics()
    val density = LocalDensity.current
    // iOS の @ScaledMetric(relativeTo: .body)。文字の大きさに合わせて広げる。
    val thumb = with(density) { 26.sp.toDp() }
    val tick = with(density) { 8.sp.toDp() }
    val groove = with(density) { 4.sp.toDp() }
    val last = (steps.size - 1).coerceAtLeast(1)
    val current by rememberUpdatedState(index)
    val change by rememberUpdatedState(onIndexChange)

    fun select(i: Int) {
        val clamped = i.coerceIn(0, steps.size - 1)
        if (clamped != current) {
            haptics.selection()
            change(clamped)
        }
    }

    /** 引いている間のつまみの位置 (溝の左端からの割合 0〜1)。離したら null に戻して段に吸い付かせる。 */
    var dragFraction by remember { mutableStateOf<Float?>(null) }
    val settled by animateFloatAsState(index.toFloat() / last, label = "step_slider")
    val fraction = dragFraction ?: settled
    val line = DS.line
    val surface = DS.surface
    val idle = DS.ink3

    Column(
        modifier
            .fillMaxWidth()
            .semantics {
                contentDescription = label
                stateDescription = steps.getOrElse(index) { "" }
                progressBarRangeInfo = ProgressBarRangeInfo(index.toFloat(), 0f..last.toFloat(), steps = (steps.size - 2).coerceAtLeast(0))
                setProgress { value ->
                    select(value.roundToInt())
                    true
                }
            },
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        Canvas(
            Modifier
                .fillMaxWidth()
                .height(thumb)
                .pointerInput(steps.size) {
                    val inset = thumb.toPx() / 2
                    // 横に引いたときだけ (縦の指は一覧のスクロールに渡す)。触れただけでは動かさない。
                    detectHorizontalDragGestures(
                        onDragStart = { dragFraction = current.toFloat() / last },
                        onDragEnd = { dragFraction = null },
                        onDragCancel = { dragFraction = null },
                        onHorizontalDrag = { change, _ ->
                            val w = (size.width - inset * 2).coerceAtLeast(1f)
                            val f = ((change.position.x - inset) / w).coerceIn(0f, 1f)
                            dragFraction = f
                            select((f * last).roundToInt())
                            change.consume()
                        }
                    )
                }
        ) {
            val inset = thumb.toPx() / 2
            val w = size.width - inset * 2
            val cy = size.height / 2
            val g = groove.toPx()
            val x = inset + w * fraction
            drawLine(line, Offset(inset, cy), Offset(inset + w, cy), strokeWidth = g, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            if (x > inset) {
                drawLine(accent, Offset(inset, cy), Offset(x, cy), strokeWidth = g, cap = androidx.compose.ui.graphics.StrokeCap.Round)
            }
            steps.indices.forEach { i ->
                val sx = inset + w * i / last
                drawCircle(if (sx <= x + 0.5f) accent else line, radius = tick.toPx() / 2, center = Offset(sx, cy))
            }
            drawCircle(surface, radius = inset, center = Offset(x, cy))
            drawCircle(
                if (index == 0 && dragFraction == null) idle else accent,
                radius = inset - g / 2, center = Offset(x, cy), style = Stroke(width = g)
            )
        }
        Row(Modifier.fillMaxWidth().clearAndSetSemantics { }) {
            steps.forEachIndexed { i, name ->
                Text(
                    name,
                    style = ImasTextRole.META.style.copy(fontWeight = if (i == index) FontWeight.Bold else FontWeight.Normal),
                    color = if (i == index) DS.ink else DS.ink3,
                    maxLines = 1,
                    // 端の段の名前は端に寄せ、間の段は真ん中 (目盛りの真下に来るように)。
                    textAlign = when (i) {
                        0 -> TextAlign.Start
                        steps.size - 1 -> TextAlign.End
                        else -> TextAlign.Center
                    },
                    modifier = Modifier.weight(1f).imasRowPress(onClick = { select(i) })
                )
            }
        }
    }
}

/** 行頭の色の帯 + 題 + 段のついたスライダーの 1 行 (設定の一覧で、ものごとに段を決める)。iOS `ImasStepSliderRow`。 */
@Composable
fun ImasStepSliderRow(
    title: String,
    steps: List<String>,
    index: Int,
    onIndexChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null
) {
    val density = LocalDensity.current
    val sliderWidth = with(density) { 188.sp.toDp() }
    // 文字が大きいときは題とスライダーを縦に積む (横に並べるとはみ出す)。
    val large = density.fontScale >= 1.5f
    Row(
        modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .heightIn(min = DS.Size.touch)
            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
        verticalAlignment = androidx.compose.ui.Alignment.CenterVertically
    ) {
        ImasLeadBar(seedHex = seed, brandId = brand, height = null, modifier = Modifier.fillMaxHeight())
        val slider = @Composable { m: Modifier ->
            ImasStepSlider(steps, index, onIndexChange, label = "${title}の担当", modifier = m, seed = seed, brand = brand)
        }
        if (large) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                Text(title, style = ImasTextRole.ROW_TITLE.style, color = DS.ink, maxLines = 2)
                slider(Modifier)
            }
        } else {
            Text(title, style = ImasTextRole.ROW_TITLE.style, color = DS.ink, maxLines = 2, modifier = Modifier.weight(1f))
            slider(Modifier.width(sliderWidth))
        }
    }
}
