package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
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
 *
 * @param subtitle 題の下の副題 (任意、既定 2 行まで)。渡すと題を [ImasTextRole.ROW_TITLE] の太さにする
 *   (ヘルプのカテゴリ行など、一覧の「もの」に近い行向け)。
 * @param subtitleLineLimit [subtitle] の行数 (切れてしまう長い説明では `Int.MAX_VALUE` を渡す)。
 * @param icon 先頭の記号 (任意)。渡すと [ImasIconTileSize.S28] の記号タイルを置く
 *   (本来は別画面へ進む一覧で使う行を、戻る操作を増やさないその場の開閉に転用する画面向け)。
 */
@Composable
fun ImasDisclosureRow(
    title: String,
    isExpanded: Boolean,
    onToggle: () -> Unit,
    modifier: Modifier = Modifier,
    count: String? = null,
    subtitle: String? = null,
    subtitleLineLimit: Int = 2,
    icon: ImageVector? = null,
    iconTone: ImasIconTileTone = ImasIconTileTone.THEMED,
    seed: String? = null
) {
    val angle by animateFloatAsState(if (isExpanded) 180f else 0f, ImasMotion.standard(), label = "disclosure")
    val titleRole = if (subtitle != null) ImasTextRole.ROW_TITLE else ImasTextRole.ROW_LABEL
    Row(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) {
                contentDescription = listOfNotNull(title, count, subtitle).joinToString(" ")
                stateDescription = if (isExpanded) "開いている" else "畳んでいる"
            }
            .imasRowPress(onClickLabel = if (isExpanded) "畳む" else "開く", onClick = onToggle)
            .heightIn(min = DS.Size.touch)
            .padding(horizontal = DS.Space.rowH, vertical = if (subtitle != null) DS.Space.rowVCompact else 0.dp),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) {
            ImasIconTile(icon, size = ImasIconTileSize.S28, tone = iconTone, seed = seed)
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                Text(title, style = titleRole.style, color = titleRole.color, modifier = Modifier.clearAndSetSemantics { })
                if (count != null) {
                    Text(count, style = ImasTextRole.META.style, color = ImasTextRole.META.color, modifier = Modifier.clearAndSetSemantics { })
                }
            }
            if (subtitle != null) {
                Text(
                    subtitle,
                    style = ImasTextRole.ROW_SUBTITLE.style,
                    color = ImasTextRole.ROW_SUBTITLE.color,
                    maxLines = subtitleLineLimit,
                    modifier = Modifier.clearAndSetSemantics { }
                )
            }
        }
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
