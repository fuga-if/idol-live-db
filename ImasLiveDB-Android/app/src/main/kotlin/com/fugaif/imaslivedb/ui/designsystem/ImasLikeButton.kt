package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ThumbUp
import androidx.compose.material.icons.outlined.ThumbUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics

// =============================================================================
// Good ボタン (docs/DESIGN_SYSTEM.md §9・§5.6)。iOS `Events/ImasLikeButton.swift` の移植。
//
// セトリの行の「この曲が良かった」トグル。親指の記号と、件数があれば下に小さく。
// ON は担当色 (DS.pick)、OFF は薄い墨。行の末尾 (`ImasRowTrailing.Custom`) に置く。
// =============================================================================

/**
 * セトリの行の Good トグル (iOS `ImasLikeButton`)。
 *
 * @param count 今の票数。0 なら数字を出さない。
 * @param isBusy 連打防止 (通信中)。
 */
@Composable
fun ImasLikeButton(
    isOn: Boolean,
    count: Int,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    isBusy: Boolean = false
) {
    val haptics = rememberImasHaptics()
    var last by remember { mutableStateOf(isOn) }
    LaunchedEffect(isOn) {
        if (isOn != last) {
            last = isOn
            haptics.impactLight()
        }
    }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(1.dp)) {
        Box(
            Modifier
                .sizeIn(minWidth = DS.Size.touch, minHeight = DS.Size.chip)
                .clearAndSetSemantics { contentDescription = if (isOn) "Good を取り消す" else "この曲が良かった" }
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    enabled = !isBusy,
                    role = Role.Button,
                    onClick = onClick
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (isOn) Icons.Filled.ThumbUp else Icons.Outlined.ThumbUp,
                contentDescription = null,
                tint = if (isOn) DS.pick else DS.ink3,
                modifier = Modifier.size(with(LocalDensity.current) { 20.sp.toDp() })
            )
        }
        if (count > 0) {
            Text(
                "$count",
                style = ImasType.text(10.sp, FontWeight.SemiBold).copy(fontFeatureSettings = "tnum"),
                color = DS.ink3
            )
        }
    }
}
