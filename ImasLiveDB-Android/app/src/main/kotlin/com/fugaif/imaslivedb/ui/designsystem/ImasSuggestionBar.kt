package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType

// =============================================================================
// 全幅・単発のアクション提案バー (iOS `Suggestion/ImasSuggestionBar.swift` の移植)。
//
// 用途      一覧の絞り込み結果から「この範囲でイントロドンを始める」のような、その場限りの単発の提案。
// 使わない  恒常的な入口 → `ImasEntryCard` / 読まないと困る注意 → `ImasNotice`
// 構成      [記号] [文言] [補足 (件数など、任意)] ……… [閉じる × (任意)]
// 種類      PROMINENT (強い提案。墨の塗り、無効時は薄灰) / SUBTLE (弱い提案。墨の薄い地)
// =============================================================================

/** 提案の強さ (iOS `ImasSuggestionBar.Style`)。 */
enum class ImasSuggestionBarStyle {
    /** 強い提案 (選択を確定させる導線など)。墨の塗り。 */
    PROMINENT,

    /** 弱い提案 (一覧の下にそっと置く誘い)。墨の薄い地。 */
    SUBTLE
}

/**
 * 全幅・単発のアクション提案バー (iOS `ImasSuggestionBar`)。
 *
 * @param detail 文言の後ろに添える補足 (「12曲」「4曲以上必要」)。
 * @param isEnabled false で PROMINENT は薄灰になり押せない。
 * @param showsChevron 右端に `>` を出す (押すと別画面・別の設定へ進む導線)。
 * @param onDismiss 右端の閉じる記号。渡すと出し、押すと提案そのものを隠す。読み上げは [dismissLabel]。
 */
@Composable
fun ImasSuggestionBar(
    icon: ImageVector,
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    detail: String? = null,
    style: ImasSuggestionBarStyle = ImasSuggestionBarStyle.SUBTLE,
    isEnabled: Boolean = true,
    showsChevron: Boolean = false,
    onDismiss: (() -> Unit)? = null,
    dismissLabel: String = "提案を閉じる"
) {
    val prominent = style == ImasSuggestionBarStyle.PROMINENT
    val background = if (prominent) (if (isEnabled) DS.sys else DS.fill) else DS.sys.copy(alpha = 0.10f)
    val titleColor = if (prominent) (if (isEnabled) DS.onSys else DS.ink3) else DS.sys
    val detailColor = if (prominent) titleColor.copy(alpha = 0.85f) else DS.ink2
    val density = LocalDensity.current
    Row(modifier.fillMaxWidth().background(background), verticalAlignment = Alignment.CenterVertically) {
        Row(
            Modifier
                .weight(1f)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    enabled = isEnabled,
                    role = Role.Button,
                    onClick = onClick
                )
                .padding(horizontal = DS.Space.screen, vertical = DS.Space.gap + 2.dp),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(icon, contentDescription = null, tint = titleColor, modifier = Modifier.size(with(density) { 16.sp.toDp() }))
            Text(title, style = ImasType.heading(15.sp, FontWeight.Bold), color = titleColor, maxLines = 1)
            if (detail != null) {
                Text(detail, style = ImasType.text(13.sp), color = detailColor, maxLines = 1)
            }
            Spacer(Modifier.weight(1f).widthIn(min = DS.Space.gap))
            if (showsChevron) {
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = titleColor,
                    modifier = Modifier.size(with(density) { 16.sp.toDp() })
                )
            }
        }
        if (onDismiss != null) {
            Box(
                Modifier
                    .clearAndSetSemantics {
                        contentDescription = dismissLabel
                        role = Role.Button
                        onClick { onDismiss(); true }
                    }
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onDismiss)
                    .padding(end = DS.Space.screen, top = DS.Space.gap + 2.dp, bottom = DS.Space.gap + 2.dp, start = DS.Space.gap),
                contentAlignment = Alignment.Center
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(with(density) { 14.sp.toDp() }))
            }
        }
    }
}
