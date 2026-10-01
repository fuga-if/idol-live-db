package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.QS
import kotlinx.coroutines.delay
import kotlin.random.Random

// =============================================================================
// ステージの再生の印 (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStageEqualizer.swift` の移植。
//
// ImasStageEqualizer  「再生中」を示す音楽の目盛り (N 列 × M 段の点が明滅する)。
// =============================================================================

/** 列ごとの高さの基準 (iOS と同じ並び)。 */
private val EqualizerBaseHeights = listOf(2, 3, 4, 2, 5, 3, 4, 5, 3, 5, 4, 2, 5, 3, 2, 3)

/**
 * 「再生中」を示す音楽の目盛り (iOS `ImasStageEqualizer`)。[isAnimating] が false の間は 1 段だけ点いて止まる。
 *
 * @param intervalMillis 高さを替える間隔。
 */
@Composable
fun ImasStageEqualizer(
    modifier: Modifier = Modifier,
    columns: Int = 16,
    rows: Int = 5,
    dotSize: Dp = 10.dp,
    spacing: Dp = 3.dp,
    intervalMillis: Long = 600,
    color: Color = QS.ink,
    isAnimating: Boolean = true
) {
    var heights by remember { mutableStateOf(EqualizerBaseHeights) }
    LaunchedEffect(isAnimating, rows, columns) {
        if (!isAnimating) {
            heights = List(columns) { 1 }
            return@LaunchedEffect
        }
        while (true) {
            heights = EqualizerBaseHeights.indices.map { i ->
                (EqualizerBaseHeights[i] + Random.nextInt(-1, 2)).coerceIn(1, rows)
            }
            delay(intervalMillis)
        }
    }
    Row(
        modifier.clearAndSetSemantics { },
        horizontalArrangement = Arrangement.spacedBy(spacing),
        verticalAlignment = Alignment.Bottom
    ) {
        repeat(columns) { col ->
            Column(verticalArrangement = Arrangement.spacedBy(spacing)) {
                for (row in (0 until rows).reversed()) {
                    val on = row < heights[col % heights.size]
                    val alpha by animateFloatAsState(if (on) 0.85f else 0.12f, tween(400), label = "eq")
                    Box(
                        Modifier
                            .size(dotSize)
                            .graphicsLayer { this.alpha = alpha }
                            .background(color)
                    )
                }
            }
        }
    }
}
