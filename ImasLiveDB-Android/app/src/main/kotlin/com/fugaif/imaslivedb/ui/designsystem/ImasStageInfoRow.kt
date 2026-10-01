package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.QS
import com.fugaif.imaslivedb.ui.theme.imasPress

// =============================================================================
// ステージの案内行 (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStageInfoRow.swift` の移植。
//
// ImasStageInfoRow   「記号 + 2 行文 (+ 矢印)」の案内行。押せる (別画面・リンク) か、案内だけかを選べる。
// =============================================================================

/**
 * ステージ上の「記号 + 2 行文」の案内行 (iOS `ImasStageInfoRow`)。
 *
 * @param showsChevron 遷移あり (押せる) なら矢印を出す。
 * @param isLoading 記号の代わりにくるくるを出す (次の問題の先読み待ちなど)。
 * @param onClick 渡すと押せる。
 */
@Composable
fun ImasStageInfoRow(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    showsChevron: Boolean = false,
    isLoading: Boolean = false,
    onClick: (() -> Unit)? = null
) {
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { }
            .then(if (onClick != null) Modifier.imasPress(onClick = onClick) else Modifier)
            .background(QS.panel, RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (isLoading) {
            CircularProgressIndicator(modifier = Modifier.size(20.dp), color = QS.dim, strokeWidth = 2.dp)
        } else {
            Icon(icon, contentDescription = null, tint = QS.dim, modifier = Modifier.size(20.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = QS.text(13, FontWeight.Bold), color = QS.ink)
            if (detail != null) Text(detail, style = QS.text(11), color = QS.dim)
        }
        Spacer(Modifier.weight(1f))
        if (showsChevron) {
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = QS.faint, modifier = Modifier.size(16.dp))
        }
    }
}
