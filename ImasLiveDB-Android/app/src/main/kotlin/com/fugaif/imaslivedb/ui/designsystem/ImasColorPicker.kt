package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics

// =============================================================================
// タグの色選択 (docs/DESIGN_SYSTEM.md §7)。iOS `Community/ImasColorPicker.swift` の移植。
//
// 色の丸から 1 つ選ぶ。「なし」+ プリセット 10 色。選んだ色の丸に墨の輪、読み上げは色名。
// タグの色のように「データとしての色」をそのまま塗る数少ない部品 (`ImasSwatch` と同じ例外。§1.2)。
// iOS の「カスタム色を選ぶ」(OS の色の選択) は Android に同じ部品が無いので持たない。
// =============================================================================

/** 並べるプリセット (彩度・色相をばらして見分けやすい 10 色)。タグの色のデータ (iOS `ImasColorPicker.presets`)。 */
val ImasColorPickerPresets: List<String> = listOf(
    "#FF6B6B", "#FF8C42", "#FFD93D", "#6BCB77", "#1DD1A1",
    "#4D96FF", "#5F6CAF", "#9B5DE5", "#F15BB5", "#8D99AE"
)

private fun normalizeHex(s: String) = s.trimStart('#').uppercase()

/**
 * 色の丸から 1 つ選ぶ (iOS `ImasColorPicker`)。6 列の格子に「なし」とプリセットを並べる。
 *
 * @param selectedHex 選んでいる色。空文字なら「なし」。
 */
@Composable
fun ImasColorPicker(selectedHex: String, onSelect: (String) -> Unit, modifier: Modifier = Modifier) {
    val haptics = rememberImasHaptics()
    fun pick(hex: String) {
        if (normalizeHex(hex) != normalizeHex(selectedHex) || hex.isEmpty() != selectedHex.isEmpty()) haptics.selection()
        onSelect(hex)
    }
    val diameter = ImasSwatchSize.LARGE.diameter
    ImasGridLayout(columns = 6, spacing = DS.Space.gap, modifier = modifier) {
        // 「なし」(色をクリア)。
        val noneSelected = selectedHex.isEmpty()
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .size(diameter)
                    .clearAndSetSemantics {
                        contentDescription = "色なし"
                        role = Role.Button
                        selected = noneSelected
                        onClick { pick(""); true }
                    }
                    .imasPress { pick("") }
                    .background(DS.fill, CircleShape)
                    .border(if (noneSelected) 2.5.dp else 0.5.dp, if (noneSelected) DS.ink else DS.sep, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    Icons.Outlined.Block,
                    contentDescription = null,
                    tint = DS.ink2,
                    modifier = Modifier.size(with(LocalDensity.current) { 14.sp.toDp() })
                )
            }
        }
        ImasColorPickerPresets.forEach { hex ->
            val on = selectedHex.isNotEmpty() && normalizeHex(hex) == normalizeHex(selectedHex)
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(
                    Modifier
                        .clearAndSetSemantics {
                            contentDescription = "カラー: ${ImasColorNames.of(hex)}"
                            role = Role.Button
                            selected = on
                            onClick { pick(hex); true }
                        }
                        .imasPress { pick(hex) }
                ) {
                    ImasSwatch(hex, size = ImasSwatchSize.LARGE, isSelected = on, isDecorative = true)
                }
            }
        }
    }
}
