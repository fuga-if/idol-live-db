package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.hexToColor

/**
 * Small solid circle — displayed before idol names to show their image color.
 * Mirrors iOS ColorDotView.
 */
@Composable
fun ColorDot(
    hexColor: String?,
    size: Dp = 8.dp,
    modifier: Modifier = Modifier
) {
    val color = if (hexColor != null) hexToColor(hexColor) else Color.Gray
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(color)
    )
}
