package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS

// =============================================================================
// 読み込み中の形 (docs/DESIGN_SYSTEM.md §11)。iOS `SkeletonView.swift` の移植。
//
// ImasListSkeleton  一覧の初回 (ジャケ/アイコン + 2 行の文字)。行の間に区切り線。
// ImasGridSkeleton  アイドルの格子の初回 (丸 + 名前)。
// SkeletonBox       角丸の塊 (部品の中で組むとき)。
// 光沢は塊ごとでなく全体に 1 回だけ流す。読み上げには出さない。
// =============================================================================

/**
 * 左→右に光沢を流すスケルトン用シマーをコンテナ全体に重ねる。iOS の ImasShimmer と対の実装。
 */
@Composable
private fun shimmerOverlay(content: @Composable () -> Unit) {
    val t = rememberInfiniteTransition(label = "shimmer")
    val p by t.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1200, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "p"
    )
    Box(
        Modifier.drawWithContent {
            drawContent()
            val w = size.width
            val center = (p * 2f - 0.5f) * w
            val band = w * 0.4f
            // 加算で重ねる (iOS の `.blendMode(.plusLighter)` と同じ)。ふつうの重ね方だと、ライトの明るい地では
            // 白 12% がほとんど足されず、光が流れていないように見える。
            drawRect(
                brush = Brush.linearGradient(
                    colors = listOf(Color.Transparent, Color.White.copy(alpha = 0.12f), Color.Transparent),
                    start = Offset(center - band, 0f),
                    end = Offset(center + band, size.height)
                ),
                blendMode = BlendMode.Plus
            )
        }
    ) { content() }
}

/** プレースホルダの角丸ブロック。 */
@Composable
fun SkeletonBox(width: Dp? = null, height: Dp = 12.dp, corner: Dp = 6.dp) {
    val base = Modifier
        .then(if (width != null) Modifier.width(width) else Modifier)
        .height(height)
        .clip(RoundedCornerShape(corner))
        .background(DS.fill)
    Box(base)
}

@Composable
private fun SkeletonCircle(size: Dp) {
    Box(Modifier.size(size).clip(CircleShape).background(DS.fill))
}

enum class SkeletonThumb { Square, Circle, None }

/** 楽曲/イベント等のリスト用スケルトン (サムネ + テキスト2行)。 */
@Composable
fun ImasListSkeleton(rows: Int = 10, thumb: SkeletonThumb = SkeletonThumb.Square) {
    val titleWidths = listOf(180.dp, 140.dp, 210.dp, 160.dp, 120.dp)
    val subWidths = listOf(90.dp, 70.dp, 110.dp, 80.dp, 60.dp)
    shimmerOverlay {
        Column(Modifier.fillMaxWidth().clearAndSetSemantics { }) {
            for (i in 0 until rows) {
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp3),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(DS.sp3)
                ) {
                    when (thumb) {
                        SkeletonThumb.Square -> SkeletonBox(44.dp, 44.dp, 8.dp)
                        SkeletonThumb.Circle -> SkeletonCircle(44.dp)
                        SkeletonThumb.None -> {}
                    }
                    Column(verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
                        SkeletonBox(titleWidths[i % 5], 13.dp)
                        SkeletonBox(subWidths[i % 5], 10.dp)
                    }
                }
                if (i < rows - 1) ImasRowDivider(inset = DS.sp5)
            }
        }
    }
}

/**
 * アイドルグリッド用スケルトン (アバター円 + 名前)。
 * 格子は Lazy にしない (縦にスクロールする親の中に置いても高さが決まるように。数は固定で少ない)。
 */
@Composable
fun ImasGridSkeleton(columns: Int = 4, count: Int = 16, avatar: Dp = 60.dp) {
    shimmerOverlay {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = DS.sp4, vertical = DS.sp4)
                .clearAndSetSemantics { },
            verticalArrangement = Arrangement.spacedBy(DS.sp5)
        ) {
            for (row in 0 until (count + columns - 1) / columns) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.sp3)) {
                    for (col in 0 until columns) {
                        val visible = row * columns + col < count
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(DS.sp2),
                            modifier = Modifier.weight(1f)
                        ) {
                            if (visible) {
                                SkeletonCircle(avatar)
                                SkeletonBox(48.dp, 10.dp)
                            }
                        }
                    }
                }
            }
        }
    }
}
