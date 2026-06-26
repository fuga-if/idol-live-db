package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Small capsule chip showing a performer with color dot.
 * For character lives: displays idol name as primary + "CV:castName" as sub-text.
 * For cast lives: displays cast name as primary + idol name as sub-text.
 * Mirrors iOS PerformerChip.
 *
 * @param name          Primary display name (cast or idol)
 * @param idolName      Associated idol name (nullable)
 * @param idolColorHex  Hex color for the dot (nullable)
 * @param isCharacterLive When true, treat as a character live (idol name is primary)
 */
@Composable
fun PerformerChip(
    name: String,
    idolName: String? = null,
    idolColorHex: String? = null,
    isCharacterLive: Boolean = false,
    modifier: Modifier = Modifier
) {
    val displayName = if (isCharacterLive) idolName ?: name else name
    val subName: String? = when {
        isCharacterLive && idolName != null -> "CV:$name"
        !isCharacterLive && idolName != null -> idolName
        else -> null
    }

    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = modifier
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.padding(horizontal = 7.dp, vertical = 3.dp)
        ) {
            ColorDot(hexColor = idolColorHex, size = 6.dp)

            Spacer(modifier = Modifier.width(4.dp))

            Column {
                Text(
                    text = displayName,
                    style = MaterialTheme.typography.labelSmall,
                    maxLines = 1
                )
                if (subName != null) {
                    Text(
                        text = subName,
                        style = MaterialTheme.typography.labelSmall.copy(fontSize = 8.sp),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        maxLines = 1
                    )
                }
            }
        }
    }
}
