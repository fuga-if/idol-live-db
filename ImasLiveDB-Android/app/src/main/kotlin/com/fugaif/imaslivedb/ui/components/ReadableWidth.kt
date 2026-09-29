package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/** 広い画面 (タブレット) で一覧の本文が伸びきらない幅。iOS の `DS.readableContentWidth` と同じ値。 */
val ReadableContentWidth: Dp = 880.dp

/**
 * 一覧の本文を [ReadableContentWidth] に収めるための左右の余白を渡す。
 * LazyColumn の `contentPadding` に入れるので、余白部分でもスクロールが効く
 * (`widthIn(max)` で縮めると余白で掴めなくなる)。狭い画面では 0。
 * iOS の `readableContentMargins()` と対。
 */
@Composable
fun ReadableWidth(content: @Composable (PaddingValues) -> Unit) {
    BoxWithConstraints {
        val side = ((maxWidth - ReadableContentWidth) / 2).coerceAtLeast(0.dp)
        content(PaddingValues(horizontal = side))
    }
}
