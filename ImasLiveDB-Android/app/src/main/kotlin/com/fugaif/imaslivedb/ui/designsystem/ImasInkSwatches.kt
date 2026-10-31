package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics

/** 刷る色の選択肢 1 つ。`stamp` が null なら墨。 */
data class ImasInkSwatch(
    val name: String,
    val stamp: String? = null,
    val seed: String? = null,
    val brand: String? = null,
    val isSelected: Boolean,
    val accessibilityLabel: String,
)

/**
 * 刷る色の選択肢を横に並べる (P名刺の編集の「刷る色」)。iOS `ImasInkSwatches`。
 * 担当の色は判子 (`ImasAvatar`)、墨は墨の丸に字。選んだものだけ墨の輪で囲み、下に名前を添える。
 */
@Composable
fun ImasInkSwatches(items: List<ImasInkSwatch>, onSelect: (Int) -> Unit) {
    val haptics = rememberImasHaptics()
    Row(
        Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), verticalAlignment = Alignment.Top
    ) {
        items.forEachIndexed { i, item ->
            Column(
                Modifier
                    .clickable {
                        haptics.selection()
                        onSelect(i)
                    }
                    .semantics {
                        contentDescription = item.accessibilityLabel
                        selected = item.isSelected
                    },
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
            ) {
                Box(
                    Modifier.padding(3.dp).border(2.dp, if (item.isSelected) DS.ink else Color.Transparent, CircleShape)
                        .padding(3.dp)
                ) {
                    if (item.stamp != null) {
                        ImasAvatar(label = item.stamp, seed = item.seed, brand = item.brand, size = 34.dp,
                            reservesPickRing = false)
                    } else {
                        Box(Modifier.size(34.dp).background(DS.ink, CircleShape), contentAlignment = Alignment.Center) {
                            Text(item.name, style = ImasTextRole.ROW_LABEL.style, color = DS.bg, maxLines = 1)
                        }
                    }
                }
                Text(
                    item.name,
                    style = ImasTextRole.NOTE.style, color = if (item.isSelected) DS.ink else DS.ink2,
                    maxLines = 1, modifier = Modifier.widthIn(max = 64.dp)
                )
            }
        }
    }
}
