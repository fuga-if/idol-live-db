package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import kotlin.math.roundToInt

// =============================================================================
// 文字の無い線の進み具合 (docs/DESIGN_SYSTEM.md §10.4)。iOS `ImasProgressBar.swift` の移植。
//
// ImasProgressBar  0〜1 の割合を細い線で見せる (対戦の進み具合・つづきからの達成率)。
//                  文字つきの内訳なら `ImasStatBar`、輪なら `ImasProgressRing`。
// =============================================================================

/**
 * 0〜1 の割合を細い線で見せる (iOS `ImasProgressBar`)。色は実体の帯の色 (無ければ墨)。
 *
 * @param fraction 0〜1。
 */
@Composable
fun ImasProgressBar(
    fraction: Double,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null
) {
    val t = ImasChipColors.theme(seed, brand, null)
    val f by animateFloatAsState(fraction.coerceIn(0.0, 1.0).toFloat(), tween(300), label = "imasProgressBar")
    Box(
        modifier
            .fillMaxWidth()
            .height(6.dp)
            .background(DS.fill, CircleShape)
            .clearAndSetSemantics { contentDescription = "${(fraction * 100).roundToInt()}パーセント" }
    ) {
        Box(
            Modifier
                .fillMaxHeight()
                .widthIn(min = 6.dp)
                .fillMaxWidth(f)
                .background(if (t.isNeutral) DS.sys else t.bar, CircleShape)
        )
    }
}
