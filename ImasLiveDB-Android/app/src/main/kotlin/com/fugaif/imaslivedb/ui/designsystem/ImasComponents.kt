package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.components.Copyable
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasThemeProvider
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand

// =============================================================================
// 移行中の部品 (docs/DESIGN_SYSTEM.md)。iOS `ImasComponents.swift` の移植。
//
// 新しい部品は DesignSystem の各ファイルに置く。ここには旧い呼び名のまま使われている部品を、
// 新しい部品の上に組み直して残している。画面を移したら消す。
//
//   ImasMetricBadge   → ImasMetric
//   ImasTagChip       → ImasBadge
//   ImasLabeledRow    → ImasValueRow
//   ImasListContainer → ImasCardList (PANEL)
// =============================================================================

// MARK: - 数字 (→ ImasMetric)

/** 旧い呼び方の数字 (→ [ImasMetric] の中)。 */
@Composable
fun ImasMetricBadge(value: String, unit: String = "", emphasized: Boolean = true, seed: String? = null) {
    ImasThemeProvider(seed = seed) {
        ImasMetric(value, unit = unit, size = ImasNumeralSize.MEDIUM, emphasized = emphasized)
    }
}

// MARK: - 順位の行

/**
 * 順位 + ジャケ/画像 + 題 + 数 (iOS `ImasRankingRow`)。1〜3 位は墨、4 位から灰。
 *
 * @param metric 並べ替えの根拠の数。根拠を出さない順位 (自分の並べ替えの結果) は null。
 * @param lead ジャケ (`ImasArtwork` 44) かアイコン (`ImasAvatar` 40。写真が無ければ判子)。
 */
@Composable
fun ImasRankingRow(
    rank: Int,
    title: String,
    metric: String?,
    unit: String = "回",
    sub: String? = null,
    seed: String? = null,
    brand: String? = null,
    onClick: (() -> Unit)? = null,
    lead: @Composable () -> Unit
) {
    ImasThemeProvider(seed = seed, brand = brand) {
        Row(
            Modifier
                .fillMaxWidth()
                .then(if (onClick != null) Modifier.imasPress(onClick = onClick) else Modifier)
                .background(DS.surface)
                .heightIn(min = DS.Size.touch)
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ImasRankNumber(rank)
            lead()
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                Text(
                    title,
                    style = ImasTextRole.ROW_TITLE.style,
                    color = DS.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                if (sub != null) {
                    Text(
                        sub,
                        style = ImasTextRole.ROW_SUBTITLE.style,
                        color = DS.ink2,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis
                    )
                }
            }
            if (metric != null) {
                ImasMetric(metric, unit = unit, size = ImasNumeralSize.MEDIUM, emphasized = rank <= 3)
            }
        }
    }
}

// MARK: - 札 (→ ImasBadge)

/**
 * 旧い呼び方の札 (→ [ImasBadge])。実体の色の線の札 ([ImasBadgeKind.THEMED]) で出す
 * (今の呼び出しは衣装の出典・出演の役割のような「実体に属する文字」なので、色の手がかりを線に残す)。
 *
 * @param outlined 旧い引数。線か塗りかの区別はもう無い (色で塗った札は使わない)。受けるだけ。
 * @param kind 札の種類を明示したいとき。
 */
@Composable
fun ImasTagChip(
    text: String,
    seed: String? = null,
    brand: String? = null,
    @Suppress("UNUSED_PARAMETER") outlined: Boolean = false,
    kind: ImasBadgeKind = ImasBadgeKind.THEMED
) {
    ImasBadge(text, kind = kind, seed = seed, brand = brand)
}

// MARK: - 項目と値の行 (→ ImasValueRow)

/**
 * 旧い呼び方の「項目: 値」の行 (iOS `ImasLabeledRow`)。見た目は [ImasValueRow] と同じ寸法で、面を敷く。
 *
 * [copyable] が true (既定) なら長押しで値をコピーできる (外部で検索したり貼りたくなる値の行なので既定の性質)。
 *
 * @param tappable 値が押せる。値を実体の色にし、矢印を出す ([showChevron] の既定)。
 * @param expandable 押すと省略を解除して全文を改行表示する (特技など長文向け)。値が 1 行に収まっている
 *   行ではトグルも押す動作も出さない (押しても何も起きない行を作らない)。
 */
@Composable
fun ImasLabeledRow(
    key: String,
    value: String,
    showSwatch: Boolean = false,
    mono: Boolean = false,
    tappable: Boolean = false,
    copyable: Boolean = true,
    seed: String? = null,
    brand: String? = null,
    onClick: (() -> Unit)? = null,
    showChevron: Boolean = tappable,
    expandable: Boolean = false
) {
    val t = imasThemeForBrand(seed, brand)
    var expanded by rememberSaveable(key, value) { mutableStateOf(false) }
    var truncated by remember(key, value) { mutableStateOf(false) }
    val showsToggle = expandable && (truncated || expanded)
    val valueStyle = if (mono) ImasTextRole.VALUE.style.copy(fontFeatureSettings = "tnum") else ImasTextRole.VALUE.style
    val row: @Composable () -> Unit = {
        Row(
            Modifier
                .fillMaxWidth()
                .background(DS.surface)
                .heightIn(min = DS.Size.touch)
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(key, style = ImasTextRole.VALUE.style, color = DS.ink2, maxLines = 1)
            Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap), verticalAlignment = Alignment.CenterVertically) {
                    if (showSwatch) Box(Modifier.size(16.dp).background(t.accent, CircleShape))
                    Text(
                        value,
                        style = valueStyle,
                        color = if (tappable) t.accent else DS.ink,
                        maxLines = if (expandable && expanded) Int.MAX_VALUE else 1,
                        overflow = TextOverflow.Ellipsis,
                        textAlign = TextAlign.End,
                        onTextLayout = { if (expandable && !expanded) truncated = it.hasVisualOverflow }
                    )
                }
            }
            if (showChevron) {
                ImasRowChevron(tint = if (tappable) t.accent else DS.ink3)
            } else if (showsToggle) {
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = DS.ink3,
                    modifier = Modifier
                        .size(with(LocalDensity.current) { 14.sp.toDp() })
                        .rotate(if (expanded) 180f else 0f)
                )
            }
        }
    }
    val tap: (() -> Unit)? = if (showsToggle) ({ expanded = !expanded }) else onClick
    // 省略表示されていても原文 (value) を渡すので全文がコピーできる。
    Copyable(
        items = if (copyable) listOf(CopyItem("${key}をコピー", value)) else emptyList(),
        modifier = Modifier.fillMaxWidth(),
        onClick = tap,
        content = row
    )
}

// MARK: - 行のまとまり (→ ImasCardList)

/**
 * 旧い呼び方の行のまとまり (→ `ImasCardList(PANEL)` と同じ面)。行の間の線は呼び出し側が引いている。
 * 横幅は今の呼び出しのまま (画面いっぱい)。
 */
@Composable
fun ImasListContainer(content: @Composable ColumnScope.() -> Unit) {
    val shape = RoundedCornerShape(DS.rCard)
    Column(
        Modifier
            .fillMaxWidth()
            .imasSurface(shape)
            .clip(shape),
        content = content
    )
}
