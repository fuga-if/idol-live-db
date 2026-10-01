package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.ImasMotion
import com.fugaif.imaslivedb.ui.theme.QS

// =============================================================================
// ステージの数タイル (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStageStatTile.swift` の移植。
//
// ImasStageStatTile   ステージの暗い面に「ラベル + 大きな数字」を 1 枚で見せる (クイズの結果・
//                      ハブの QUIZ STAGE チケット・イントロドンのタイムなど)。
// ImasStageBadgeStamp  「自己ベスト更新」のような達成を知らせる傾いた印。
//
// 色はどちらもステージ固定の `QS` (ライト/ダークで反転させない)。
// =============================================================================

/**
 * ステージ上の「ラベル + 大きな数字」のタイル (iOS `ImasStageStatTile`)。単値でも、対比 (前 → 後) でも、
 * 右に添える印 ([trailing]。自己ベスト更新など) とも使える。[value] の文字の既定の色は QS.ink。
 */
@Composable
fun ImasStageStatTile(
    label: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
    value: @Composable () -> Unit
) {
    Row(
        modifier
            .fillMaxWidth()
            .background(QS.panel, RoundedCornerShape(16.dp))
            .padding(horizontal = 14.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = QS.text(12, FontWeight.Bold), color = QS.dim)
            CompositionLocalProvider(LocalContentColor provides QS.ink) { value() }
        }
        trailing?.invoke()
    }
}

/**
 * 達成を知らせる傾いた印 (iOS `ImasStageBadgeStamp`。「自己ベスト更新」「ベストタイム更新」)。
 *
 * @param detail 旧値 → 新値の併記 (「700 → 755」)。無ければ文言だけ。
 * @param appeared 出たか。false → true で大きい所から押されたように現れる。
 */
@Composable
fun ImasStageBadgeStamp(title: String, modifier: Modifier = Modifier, detail: String? = null, appeared: Boolean = true) {
    val t by animateFloatAsState(if (appeared) 1f else 0f, ImasMotion.standard(), label = "stamp")
    Column(
        modifier
            .graphicsLayer {
                val s = 1.8f - 0.8f * t
                scaleX = s
                scaleY = s
                alpha = t
            }
            .rotate(-5f)
            .border(2.dp, QS.stamp, RoundedCornerShape(8.dp))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(1.dp)
    ) {
        Text(title, style = QS.text(13, FontWeight.Black), color = QS.stamp)
        if (detail != null) Text(detail, style = QS.mono(11), color = QS.stamp)
    }
}
