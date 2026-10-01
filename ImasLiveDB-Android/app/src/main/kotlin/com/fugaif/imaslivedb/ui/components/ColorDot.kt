package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.designsystem.ImasSwatch

/**
 * イメージカラーの点 — アイドル名の前に置く (iOS `ColorDotView` と対)。中身は DS の [ImasSwatch]。
 *
 * @param isDecorative 名前が隣に書いてあり、色名を読み上げなくてよいとき。
 */
@Composable
fun ColorDot(
    hexColor: String?,
    size: Dp = 8.dp,
    modifier: Modifier = Modifier,
    isDecorative: Boolean = true
) {
    ImasSwatch(hex = hexColor, diameter = size, isDecorative = isDecorative, modifier = modifier)
}
