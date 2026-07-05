package com.fugaif.imaslivedb.ui.tags

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.ColorMath
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.hexToColor

/**
 * タグ色の選択 UI。iOS TagColorPicker の移植 (プリセット10色 + 「なし」)。
 * SwiftUI の `ColorPicker` (システムカラーピッカー) に相当する任意色入力 UI は Compose 標準に無いため、
 * プリセットのみで構成する (十分な選択肢を用意)。
 */
private val PRESET_COLORS = listOf(
    "#FF6B6B", "#FF8C42", "#FFD93D", "#6BCB77", "#1DD1A1",
    "#4D96FF", "#5F6CAF", "#9B5DE5", "#F15BB5", "#8D99AE"
)

@Composable
fun TagColorPicker(selectedHex: String, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Swatch(fill = null, selected = selectedHex.isEmpty(), onClick = { onSelect("") })
        PRESET_COLORS.forEach { hex ->
            Swatch(
                fill = hexToColor(hex),
                selected = normalize(hex) == normalize(selectedHex),
                onClick = { onSelect(hex) }
            )
        }
    }
}

private fun normalize(s: String) = s.trimStart('#').lowercase()

@Composable
private fun Swatch(fill: androidx.compose.ui.graphics.Color?, selected: Boolean, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(34.dp)
            .clip(CircleShape)
            .then(if (fill != null) Modifier.background(fill) else Modifier.border(1.dp, DS.ink3, CircleShape))
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        if (fill == null) {
            Icon(Icons.Filled.Close, contentDescription = "色なし", tint = DS.ink3, modifier = Modifier.size(14.dp))
        } else if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = ColorMath.onColor(fill), modifier = Modifier.size(16.dp))
        }
        if (selected) {
            Box(modifier = Modifier.size(34.dp).clip(CircleShape).border(2.5.dp, DS.ink, CircleShape))
        }
    }
}
