package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Generic styled filter chip with capsule shape and optional color tint.
 * Used in filter rows for song type, brand, etc.
 *
 * @param label    Text displayed in the chip
 * @param selected Whether this chip is currently selected
 * @param tintColor Optional color for selected state (defaults to MaterialTheme primary)
 * @param onClick  Called when the chip is tapped
 */
@Composable
fun ImasFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    tintColor: Color = Color.Unspecified,
    modifier: Modifier = Modifier
) {
    val resolvedTint = if (tintColor == Color.Unspecified) {
        MaterialTheme.colorScheme.primary
    } else {
        tintColor
    }

    val backgroundColor = if (selected) resolvedTint.copy(alpha = 0.15f) else Color.Transparent
    val borderColor = if (selected) resolvedTint else MaterialTheme.colorScheme.outline
    val textColor = if (selected) resolvedTint else MaterialTheme.colorScheme.onSurface

    Surface(
        onClick = onClick,
        shape = CircleShape,
        color = backgroundColor,
        border = BorderStroke(width = 1.dp, color = borderColor),
        modifier = modifier
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelMedium,
            color = textColor,
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp)
        )
    }
}
