package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.QS
import kotlin.math.roundToInt

// =============================================================================
// ステージの線メーター (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStageProgressBar.swift` の移植。
//
// ImasStageProgressBar  ペンライトが 20 本を超える・総数が決まらないときの進みの線。
//                        イントロドンのラッシュ (残り時間)・全曲チャレンジ (進んだ量) で使う。
// =============================================================================

/**
 * ペンライトの代わりに使う細い線メーター (iOS `ImasStageProgressBar`)。読み上げは「N パーセント」。
 *
 * @param fraction 0〜1。
 * @param isUrgent 残りわずか・急ぎのときに朱へ替える。
 */
@Composable
fun ImasStageProgressBar(fraction: Double, modifier: Modifier = Modifier, isUrgent: Boolean = false) {
    val f = fraction.coerceIn(0.0, 1.0).toFloat()
    val animated by animateFloatAsState(f, tween(150, easing = LinearEasing), label = "stageProgress")
    val shape = RoundedCornerShape(50)
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(6.dp)
            .background(QS.raised, shape)
            .clearAndSetSemantics { contentDescription = "${(fraction * 100).roundToInt()}パーセント" }
    ) {
        Box(
            Modifier
                .fillMaxHeight()
                .width(maxOf(4.dp, maxWidth * animated))
                .background(if (isUrgent) QS.stamp else QS.ink, shape)
        )
    }
}
