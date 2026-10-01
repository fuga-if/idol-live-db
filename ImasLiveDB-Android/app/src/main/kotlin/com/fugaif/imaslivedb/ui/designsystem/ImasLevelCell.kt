package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS

// =============================================================================
// 段階 1 マス (docs/DESIGN_SYSTEM.md §10.4)。iOS `ImasLevelCell.swift` の移植。
//
// ImasLevelCell  習熟度の 1 曲・クイズの 1 項目のような「段階のマス」。未設定 (0) は
//                面を持たず線の枠だけ。連続する割合なら `ImasMeter`、輪なら `ImasProgressRing`。
//                色の塗り分けは呼び出し側のドメイン (習熟度の段階の色など) に委ねる。
// =============================================================================

/**
 * 段階のマス 1 つ (iOS `ImasLevelCell`)。
 *
 * @param fill 0 以外の段の塗り色 (段, 段の数) → 色。ドメインごとの段階の色 (習熟度の段階色など) を渡す。
 */
@Composable
fun ImasLevelCell(
    level: UByte,
    steps: UByte,
    modifier: Modifier = Modifier,
    size: Dp = 14.dp,
    fill: (UByte, UByte) -> Color
) {
    val shape = RoundedCornerShape(if (size > 10.dp) 3.dp else 2.dp)
    Box(
        modifier
            .size(size)
            .then(
                if (level.toInt() == 0) Modifier.border(1.dp, DS.ink3, shape)
                else Modifier.background(fill(level, steps), shape)
            )
    )
}
