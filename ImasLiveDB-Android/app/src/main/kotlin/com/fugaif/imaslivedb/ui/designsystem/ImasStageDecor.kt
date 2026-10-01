package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.Circle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.QS

// =============================================================================
// ステージの小さな飾り (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStageDecor.swift` の移植。
//
// ImasStageWordmark     墨塗りの角丸四角に文字 1〜2 字 (ハブの QUIZ STAGE チケットの「@」)。
// ImasStagePanel        QS.panel の面に中身を乗せる汎用の面 (音声判定の状態表示など)。
// ImasStagePreviewCard  QS.bg の色でカードの形に切り抜く (明るい一覧の中に埋め込むステージのプレビュー)。
// ImasStageRushFlash    正誤を知らせる大きな ○ / × の一瞬のフラッシュ。
// ImasStagePulse        「聴取中」のような続いている状態を示す点滅の点。
// ImasStagePenlightBars 歌唱メンバーの色を細い棒で並べる (セトリ当てクイズ)。
//
// 色はステージ固定の `QS` (ライト/ダークで反転させない)。
// =============================================================================

/** 墨塗りの角丸四角に短い文字 (iOS `ImasStageWordmark`)。飾りなので読み上げない。 */
@Composable
fun ImasStageWordmark(text: String, modifier: Modifier = Modifier, size: Dp = 22.dp) {
    Box(
        modifier
            .size(size)
            .background(QS.ink, RoundedCornerShape(6.dp))
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center
    ) {
        Text(text, style = QS.text(14, FontWeight.Black), color = QS.bg, textAlign = TextAlign.Center, maxLines = 1)
    }
}

/**
 * QS.panel の面に中身を乗せる汎用の面 (iOS `ImasStagePanel`)。既定は角丸 14・縦の余白のみ。
 * 角丸・余白を変えれば大きな面 (INTRO パネルなど) にも使える。中身は横の真ん中に寄せる。
 */
@Composable
fun ImasStagePanel(
    modifier: Modifier = Modifier,
    corner: Dp = 14.dp,
    horizontalPadding: Dp = 0.dp,
    topPadding: Dp = 18.dp,
    bottomPadding: Dp = 18.dp,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier
            .fillMaxWidth()
            .background(QS.panel, RoundedCornerShape(corner))
            .padding(start = horizontalPadding, end = horizontalPadding, top = topPadding, bottom = bottomPadding),
        horizontalAlignment = Alignment.CenterHorizontally,
        content = content
    )
}

/**
 * QS.bg の色でカードの形に切り抜く (iOS `ImasStagePreviewCard`)。明るい一覧の中に「ここから先は会場」と
 * 分かるステージのプレビューを埋め込むときに使う (ハブの QUIZ STAGE チケットなど)。
 */
@Composable
fun ImasStagePreviewCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier
            .clip(shape)
            .background(QS.bg, shape),
        content = content
    )
}

/**
 * 正誤を知らせる大きな ○ / × の一瞬のフラッシュ (iOS `ImasStageRushFlash`。ラッシュ系クイズ)。
 * 出た瞬間に縮んだ所から広がる。押せない (下の操作を邪魔しない)。
 */
@Composable
fun ImasStageRushFlash(isCorrect: Boolean, modifier: Modifier = Modifier) {
    val color = if (isCorrect) DS.success else DS.danger
    val appear = remember { Animatable(0f) }
    LaunchedEffect(Unit) { appear.animateTo(1f, tween(180, easing = FastOutSlowInEasing)) }
    Box(
        modifier
            .size(120.dp)
            .graphicsLayer {
                val s = 0.6f + 0.4f * appear.value
                scaleX = s
                scaleY = s
                alpha = appear.value
            }
            .drawBehind {
                // 記号のまわりの光 (iOS `.shadow(radius: 16)`)。
                drawCircle(
                    Brush.radialGradient(listOf(color.copy(alpha = 0.35f), Color.Transparent), center, size.minDimension * 0.6f),
                    radius = size.minDimension * 0.6f
                )
            }
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            if (isCorrect) Icons.Outlined.Circle else Icons.Filled.Close,
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(96.dp)
        )
    }
}

/** 歌唱メンバーの色を細い棒で並べる (iOS `ImasStagePenlightBars`。セトリ当てクイズの歌唱メンバー欄)。 */
@Composable
fun ImasStagePenlightBars(colors: List<Color>, modifier: Modifier = Modifier) {
    Row(modifier.clearAndSetSemantics { }, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        colors.forEach { color ->
            Box(
                Modifier
                    .size(width = 8.dp, height = 20.dp)
                    .background(color, RoundedCornerShape(50))
            )
        }
    }
}

/** 「聴取中」のような続いている状態を示す点滅の点 (iOS `ImasStagePulse`)。 */
@Composable
fun ImasStagePulse(modifier: Modifier = Modifier, color: Color = DS.pick) {
    val transition = rememberInfiniteTransition(label = "stagePulse")
    val t by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(900, easing = FastOutSlowInEasing), RepeatMode.Restart),
        label = "stagePulseT"
    )
    Box(modifier.size(22.dp).clearAndSetSemantics { }, contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .size(14.dp)
                .graphicsLayer {
                    val s = 1f + 0.6f * t
                    scaleX = s
                    scaleY = s
                    alpha = 1f - t
                }
                .background(color.copy(alpha = 0.3f), CircleShape)
        )
        Box(Modifier.size(8.dp).background(color, CircleShape))
    }
}
