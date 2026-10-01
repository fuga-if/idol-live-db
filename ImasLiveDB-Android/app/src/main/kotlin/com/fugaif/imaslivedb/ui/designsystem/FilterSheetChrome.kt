package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress

// =============================================================================
// フィルタシート共通の体裁 (iOS `FilterSheetChrome.swift` の移植)。
//
// ライブ / アイドル / タグ / 楽曲のフィルタシートで、地・題・「リセット」「適用」の置き場所を揃える。
// 地は `ImasFormBackdrop`、中身は `ImasListSection` で組み、頭にこの帯を置く。
// =============================================================================

/**
 * フィルタシート共通の頭の帯 (iOS `filterSheetToolbar`): 左「リセット」/ 真ん中「フィルタ」/ 右「適用」。
 *
 * リセットは **この帯にだけ** 置く (同じ操作を 1 画面に 2 つ置かない)。
 * 条件が何も付いていないとき ([canReset] = false) は押せなくして、押せる/押せないで状態を示す。
 */
@Composable
fun ImasFilterSheetToolbar(
    canReset: Boolean,
    onReset: () -> Unit,
    onApply: () -> Unit,
    modifier: Modifier = Modifier,
    title: String = "フィルタ"
) {
    Box(
        modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .padding(horizontal = DS.Space.gap)
    ) {
        WordButton("リセット", enabled = canReset, bold = false, onClick = onReset, modifier = Modifier.align(Alignment.CenterStart))
        Text(
            title,
            style = ImasType.heading(17.sp, FontWeight.Bold),
            color = DS.ink,
            maxLines = 1,
            modifier = Modifier
                .align(Alignment.Center)
                .semantics { heading() }
        )
        WordButton("適用", enabled = true, bold = true, onClick = onApply, modifier = Modifier.align(Alignment.CenterEnd))
    }
}

/** 文字のボタン (帯の左右)。 */
@Composable
private fun WordButton(title: String, enabled: Boolean, bold: Boolean, onClick: () -> Unit, modifier: Modifier) {
    Box(
        modifier
            .heightIn(min = DS.Size.touch)
            .imasPress(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = DS.Space.gap),
        contentAlignment = Alignment.Center
    ) {
        Text(
            title,
            style = ImasType.text(17.sp, if (bold) FontWeight.Bold else FontWeight.Normal),
            color = if (enabled) DS.ink else DS.ink3,
            maxLines = 1
        )
    }
}
