package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole

// =============================================================================
// ジャケの格子セル (docs/DESIGN_SYSTEM.md §6.6)。iOS `Media/ImasArtworkCell.swift` の移植。
//
// 用途      アルバム・シリーズなど「ジャケ + 題」を格子で並べる一覧 (3 列)。
// 使わない  アイドル・ユニットの格子 → `ImasIdolCell`
// 構成      ジャケ (正方形、列幅いっぱい) + 題 (2 行まで) + 副題 (任意、1 行)
// 押せるようにするのは呼び出し側 (`Modifier.imasPress`)。
// =============================================================================

/**
 * ジャケ + 題の格子セル (iOS `ImasArtworkCell`。アルバム・シリーズの一覧)。
 *
 * @param fallbackIcon 画像が無いときの記号 (実体ごとに違う。例: シリーズは円盤の束)。
 */
@Composable
fun ImasArtworkCell(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    seed: String? = null,
    brand: String? = null,
    imageUrl: String? = null,
    fallbackIcon: ImageVector = Icons.Filled.MusicNote
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight + 2.dp)) {
        // 下の題で同じ名前を読むので、ジャケ自体は読み上げから隠す (二重読み防止)。
        BoxWithConstraints(
            Modifier
                .fillMaxWidth()
                .aspectRatio(1f)
                .clearAndSetSemantics { }
        ) {
            ImasArtwork(
                title = title,
                seed = seed,
                brand = brand,
                size = maxWidth,
                imageUrl = imageUrl,
                fallbackIcon = fallbackIcon
            )
        }
        Text(title, style = ImasTextRole.ROW_LABEL.style, color = DS.ink, maxLines = 2)
        if (subtitle != null) {
            Text(subtitle, style = ImasTextRole.META.style, color = ImasTextRole.META.color)
        }
    }
}
