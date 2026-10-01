package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.QS

// =============================================================================
// 部分点のある判定カード (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStagePartialVerdictCard.swift` の移植。
//
// ImasStagePartialVerdictCard  正解/不正解の二値の判定カードとは別に、「全員中 N 人正解」のような
//                               部分点を出す (全問正解 = 生成りのカード、一部正解 = ステージの地の色)。
// =============================================================================

/**
 * 部分点のある判定カード (iOS `ImasStagePartialVerdictCard`)。出た瞬間に少し縮んだ所から広がる。
 *
 * @param isPerfect 満点 (生成りのカード) か、部分点 (ステージの地の色) か。
 * @param headline 大見出し (「全員正解！」「2 / 3 正解」)。
 */
@Composable
fun ImasStagePartialVerdictCard(number: Int, isPerfect: Boolean, headline: String, score: Int, modifier: Modifier = Modifier) {
    val ink = if (isPerfect) QS.paperInk else QS.ink
    val shape = RoundedCornerShape(24.dp)
    val appear = remember { Animatable(0f) }
    LaunchedEffect(Unit) { appear.animateTo(1f, tween(220)) }
    Row(
        modifier
            .fillMaxWidth()
            .graphicsLayer {
                val s = 0.94f + 0.06f * appear.value
                scaleX = s
                scaleY = s
                alpha = appear.value
            }
            .semantics(mergeDescendants = true) { }
            .background(if (isPerfect) QS.paper else QS.panel, shape)
            .then(if (isPerfect) Modifier else Modifier.border(1.dp, QS.line, shape))
            .padding(horizontal = 22.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Column(
            Modifier
                .weight(1f)
                .alignByBaseline(),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            Text(
                "Q.%02d — %s".format(number, if (isPerfect) "PERFECT" else "RESULT"),
                style = QS.mono(12, tracking = 1.4f),
                color = ink
            )
            ImasFitText(headline, style = QS.text(if (isPerfect) 40 else 34, FontWeight.Black), color = ink, minScale = 0.6f)
        }
        Text(
            "+$score",
            style = QS.num(64, FontWeight.Black),
            color = ink,
            maxLines = 1,
            modifier = Modifier.alignByBaseline()
        )
    }
}
