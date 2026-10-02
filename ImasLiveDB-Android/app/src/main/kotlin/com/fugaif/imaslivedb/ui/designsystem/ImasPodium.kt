package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand

// =============================================================================
// ゲームの表彰台・対戦カード (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasPodium.swift` の移植。
//
// ImasPodium               1〜3 位を強調する表彰台 (1 位を中央に大きく + 2・3 位を左右)。
//                          ソートメーカー・ティアー表の結果で使う (地は紙面のまま、QS は使わない)。
// ImasVersusBadge          「VS」の丸い印 (対戦カードの間)。
// Modifier.imasAccentCard  実体の色の面をまとう選べるカード (対戦カードの縁・ティアー表のチップ)。
// =============================================================================

/**
 * 表彰台の 1 つ (iOS `ImasPodium.Entry`)。
 *
 * @param seed 実体の色 hex。[brand] はブランド ID。
 * @param visual アイコン・ジャケなどの見た目 (呼び出し側が組む)。
 */
class ImasPodiumEntry(
    val id: String,
    val rank: Int,
    val title: String,
    val subtitle: String? = null,
    val seed: String? = null,
    val brand: String? = null,
    val visual: @Composable () -> Unit,
    val onClick: () -> Unit
)

/** 1〜3 位を強調する表彰台 (iOS `ImasPodium`)。1 位を大きく中央に、2・3 位を横に並べる (先頭が 1 位)。 */
@Composable
fun ImasPodium(entries: List<ImasPodiumEntry>, modifier: Modifier = Modifier) {
    val first = entries.firstOrNull() ?: return
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PodiumCard(first, large = true, modifier = Modifier.fillMaxWidth())
        val rest = entries.drop(1).take(2)
        if (rest.isNotEmpty()) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                rest.forEach { PodiumCard(it, large = false, modifier = Modifier.weight(1f)) }
                if (rest.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun PodiumCard(entry: ImasPodiumEntry, large: Boolean, modifier: Modifier) {
    val theme = imasThemeForBrand(entry.seed, entry.brand)
    val shape = RoundedCornerShape(DS.rCard)
    // 副題 (歌唱名義 / CV) があれば読み上げにも足す (無ければ順位・題だけ)。
    val spoken = listOfNotNull("${entry.rank}位 ${entry.title}", entry.subtitle).joinToString(" ")
    Column(
        modifier
            .clearAndSetSemantics {
                contentDescription = spoken
                role = Role.Button
                onClick { entry.onClick(); true }
            }
            .imasPress(onClick = entry.onClick)
            .background(if (large) theme.tint else DS.surface, shape)
            .padding(if (large) 24.dp else DS.Space.card),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Box {
            entry.visual()
            val badge = if (large) 40.dp else 30.dp
            Box(
                Modifier
                    .offset(x = (-10).dp, y = (-10).dp)
                    .sizeIn(minWidth = badge, minHeight = badge)
                    .background(theme.accent, CircleShape)
                    .border(3.dp, DS.surface, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Text(
                    "${entry.rank}",
                    style = ImasType.text(if (large) 22.sp else 16.sp, FontWeight.Black).copy(fontFeatureSettings = "tnum"),
                    color = theme.onAccent
                )
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                entry.title,
                style = if (large) ImasTextRole.CARD_TITLE.style else ImasTextRole.ROW_TITLE.style,
                color = DS.ink,
                textAlign = TextAlign.Center,
                maxLines = 2
            )
            if (entry.subtitle != null) {
                Text(entry.subtitle, style = ImasTextRole.META.style, color = ImasTextRole.META.color, maxLines = 1)
            }
        }
    }
}

/** 対戦カードの間に置く「VS」の丸い印 (iOS `ImasVersusBadge`)。飾りなので読み上げない。 */
@Composable
fun ImasVersusBadge(modifier: Modifier = Modifier) {
    Box(
        modifier
            .size(36.dp)
            .background(DS.sys, CircleShape)
            .border(3.dp, DS.bg, CircleShape)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center
    ) {
        Text("VS", style = ImasType.text(13.sp, FontWeight.Black), color = DS.onSys)
    }
}

// MARK: - 選べるカードの面

/** 選べるカードの飾り方 (iOS `ImasAccentCardStyle`)。 */
enum class ImasAccentCardStyle {
    /** 面カード (いつも紙面、上に実体の色の帯、選んだときだけ太い縁)。対戦カード。 */
    CARD,

    /** チップ (選んだときだけ実体の色を薄く塗って縁取る)。ティアー表のチップ。 */
    CHIP
}

/**
 * 実体の色の面をまとう選べるカード (iOS `.imasAccentCard`。対戦カードの上の帯・ティアー表のチップの縁)。
 *
 * @param seed 実体の色 hex。[brand] はブランド ID。
 */
@Composable
fun Modifier.imasAccentCard(
    seed: String? = null,
    brand: String? = null,
    isSelected: Boolean = false,
    style: ImasAccentCardStyle = ImasAccentCardStyle.CARD
): Modifier {
    val t = imasThemeForBrand(seed, brand)
    val card = style == ImasAccentCardStyle.CARD
    val shape = RoundedCornerShape(if (card) DS.rCard else DS.rSM)
    val fill = if (card) DS.surface else if (isSelected) t.tint else Color.Transparent
    val accent = t.accent
    val border = if (isSelected) (if (card) 3.dp else 2.5.dp) else 0.dp
    return this
        .background(fill, shape)
        .then(if (border > 0.dp) Modifier.border(border, accent, shape) else Modifier)
        .then(
            if (card) {
                Modifier.drawWithContent {
                    drawContent()
                    // 上の実体の色の帯 (幅 36・高さ 4)。
                    val w = 36.dp.toPx()
                    val h = 4.dp.toPx()
                    drawRoundRect(
                        accent,
                        topLeft = Offset((size.width - w) / 2, 6.dp.toPx()),
                        size = Size(w, h),
                        cornerRadius = CornerRadius(h / 2)
                    )
                }
            } else {
                Modifier
            }
        )
}
