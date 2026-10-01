package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasMotion
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasRowPress

// =============================================================================
// 開閉トグルの行 (iOS `Events/ImasDisclosureRow.swift` の移植)。
//
// 行・区画の中身をその場で開閉する (個別衣装・歌唱メンバー予想など)。押すたびに矢印が回転する。
// =============================================================================

/**
 * 開閉トグルの行 (iOS `ImasDisclosureRow`)。題 + 件数 + 開閉の矢印。
 * 読み上げは「題 件数」、押したときの操作は「開く / 畳む」。
 */
@Composable
fun ImasDisclosureRow(
    title: String,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    count: String? = null
) {
    val angle by animateFloatAsState(if (isExpanded) 180f else 0f, ImasMotion.standard(), label = "disclosure")
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = listOfNotNull(title, count).joinToString(" ")
                stateDescription = if (isExpanded) "開いている" else "畳んでいる"
            }
            .imasRowPress(onClickLabel = if (isExpanded) "畳む" else "開く", onClick = onToggle)
            .heightIn(min = DS.Size.touch)
            .padding(horizontal = DS.Space.rowH),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(title, style = ImasTextRole.ROW_LABEL.style, color = DS.ink, modifier = Modifier.clearAndSetSemantics { })
        if (count != null) {
            Text(count, style = ImasTextRole.META.style, color = ImasTextRole.META.color, modifier = Modifier.clearAndSetSemantics { })
        }
        Spacer(Modifier.weight(1f))
        Icon(
            Icons.Filled.KeyboardArrowDown,
            contentDescription = null,
            tint = DS.ink3,
            modifier = Modifier
                .size(with(LocalDensity.current) { 16.sp.toDp() })
                .rotate(angle)
        )
    }
}
