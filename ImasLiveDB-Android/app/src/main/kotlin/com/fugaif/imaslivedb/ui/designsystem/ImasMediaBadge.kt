package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType

// =============================================================================
// 画像サムネイルの角の印 (iOS `Idols/ImasMediaBadge.swift` の移植)。
//
// 写真サムネイルの角に乗せる小さな印 (アイコン設定・スライドショー対象外など)。
// 下の写真は何色か分からないので、実体色ではなく半透明の黒 + 白で乗せる
// (字幕の下の黒い帯と同じ考え方。記号に地を敷かない原則の例外)。
// =============================================================================

/** 写真の上に乗せる地と文字の色 (写真の色に関わらず読めるように固定)。 */
private val MediaBadgeBackground = Color.Black.copy(alpha = 0.55f)
private val MediaBadgeInk = Color.White

/**
 * 写真サムネイルの角に乗せる小さな印 (iOS `ImasMediaBadge`)。[label] があれば記号 + 文字の札、無ければ記号だけの丸。
 *
 * @param accessibilityLabel 記号だけのときの読み上げ。[label] も無ければ読み上げに出さない。
 */
@Composable
fun ImasMediaBadge(
    icon: ImageVector,
    modifier: Modifier = Modifier,
    label: String? = null,
    accessibilityLabel: String? = null
) {
    val spoken = accessibilityLabel ?: label
    val iconSize = with(LocalDensity.current) { 12.sp.toDp() }
    Box(
        modifier
            .padding(DS.Space.gapTight)
            .clearAndSetSemantics { if (spoken != null) contentDescription = spoken }
    ) {
        if (label != null) {
            Row(
                Modifier
                    .background(MediaBadgeBackground, RoundedCornerShape(50))
                    .padding(horizontal = DS.Space.gapTight + 2.dp, vertical = DS.Space.gapTight),
                horizontalArrangement = Arrangement.spacedBy(3.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(icon, contentDescription = null, tint = MediaBadgeInk, modifier = Modifier.size(iconSize))
                Text(label, style = ImasType.text(11.sp, FontWeight.Bold), color = MediaBadgeInk, maxLines = 1)
            }
        } else {
            Box(
                Modifier
                    .background(MediaBadgeBackground, CircleShape)
                    .padding(DS.Space.gapTight)
            ) {
                Icon(icon, contentDescription = null, tint = MediaBadgeInk, modifier = Modifier.size(iconSize))
            }
        }
    }
}
