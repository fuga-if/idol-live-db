package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS

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

/**
 * 適用中フィルタを表す除去可能チップ (× タップで解除)。iOS ImasRemovableChip 相当。
 * 曲一覧の「担当」「お気に入り」「回収済み」「タグ」等、適用中フィルタの一覧行に使う。
 */
@Composable
fun ImasRemovableChip(
    text: String,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        shape = CircleShape,
        color = DS.fill,
        modifier = modifier
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
            modifier = Modifier.padding(start = 12.dp, end = 8.dp, top = 6.dp, bottom = 6.dp)
        ) {
            Text(text = text, style = MaterialTheme.typography.labelMedium, color = DS.ink)
            Icon(
                imageVector = Icons.Filled.Close,
                contentDescription = "${text}を解除",
                tint = DS.ink2,
                modifier = Modifier
                    .size(16.dp)
                    .clickable(onClick = onRemove)
            )
        }
    }
}
