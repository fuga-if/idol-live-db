package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasTheme

// =============================================================================
// ティアー表 (docs/DESIGN_SYSTEM.md §10.6)。iOS `ImasTierList.swift` の移植。
//
// ImasTierHeader   表の名前と振り分けの進み。押すと名前と段の編集を開く (鉛筆の記号つき)。
// ImasTierBoard    段を縦に積む枠。段の間は 2pt の細い隙間、外を角丸で切る。
// ImasTierRow      1 段。左に段の色の札、右に置いたものの面。何かを選んでいるときだけ、札と面が
//                  「ここへ移す」の押し先になる (選んでいないときは押せない)。
// ImasTierLabel    段の色の札。2 文字以下 (S・神) は大きく、長い名前は小さく 2 行まで。
//                  種類: 行の頭 (ROW)・移す先のボタン (BUTTON)・編集の色見本 (SWATCH)。
// ImasTierItems    段の中・未分類の並び。段の中は回り込み (FLOW)、未分類は数千件になりうるので
//                  見えている分だけ描く格子 (GRID) を呼び出し側が選べる。空のときは 1 行の文。
// ImasTierChip     表に置く 1 枚 (ジャケかアイコン + 名前 1 行)。選ぶと色の地と枠で浮く。
// ImasTierMoveBar  選んでいる間だけ下に出す「〇〇をどこへ？」の帯。段のボタンを 6 列で折り返し、
//                  最後に未分類へ戻すボタン。
//
// 使わない場面: 順位 (→ ImasRankingRow)・段階の記録 (→ ImasLevelCell)。
// 段の色は段ごとのシード (`TierDef.colorSeed`) を色エンジンに通した accent / onAccent。
// =============================================================================

/** 表の名前と振り分けの進み。押すと名前と段の編集を開く。 */
@Composable
fun ImasTierHeader(title: String, subtitle: String, onEdit: () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(DS.sp1),
        modifier = Modifier
            .fillMaxWidth()
            .imasPress(onClickLabel = "名前と段を編集", onClick = onEdit)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.sp2)) {
            ImasText(title, ImasTextRole.SECTION_TITLE)
            Icon(Icons.Filled.Edit, contentDescription = null, tint = DS.ink3, modifier = Modifier.width(15.dp))
        }
        ImasText(subtitle, ImasTextRole.META)
    }
}

/** 段を縦に積む枠。 */
@Composable
fun ImasTierBoard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(DS.sp1),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(DS.rMD)),
        content = content
    )
}

/** 段の色の札の種類。 */
enum class ImasTierLabelStyle {
    /** 行の頭。幅 60・行の高さいっぱい・角なし (枠の角丸で切る)。 */
    ROW,

    /** 移す先のボタン。幅いっぱい・押せる高さ。 */
    BUTTON,

    /** 編集の色見本 (押すと色が変わる)。 */
    SWATCH
}

/** 段の色の札。2 文字以下は大きく、長い名前は小さくして 2 行まで。 */
@Composable
fun ImasTierLabel(label: String, seed: String?, style: ImasTierLabelStyle, modifier: Modifier = Modifier) {
    val theme = imasTheme(seed = seed, brand = null)
    val (large, small) = when (style) {
        ImasTierLabelStyle.ROW -> 24.sp to 14.sp
        ImasTierLabelStyle.BUTTON -> 18.sp to 11.sp
        ImasTierLabelStyle.SWATCH -> 16.sp to 10.sp
    }
    val text = @Composable {
        ImasFitText(
            label,
            style = ImasType.text(if (label.length <= 2) large else small, FontWeight.Black),
            color = theme.onAccent,
            textAlign = TextAlign.Center,
            maxLines = 2,
            minScale = 0.6f
        )
    }
    when (style) {
        ImasTierLabelStyle.ROW -> Box(
            modifier.width(60.dp).fillMaxHeight().background(theme.accent).padding(horizontal = DS.sp2),
            contentAlignment = Alignment.Center
        ) { text() }
        ImasTierLabelStyle.BUTTON -> Box(
            modifier
                .fillMaxWidth()
                .heightIn(min = DS.Size.touch)
                .clip(RoundedCornerShape(DS.rSM))
                .background(theme.accent)
                .padding(horizontal = DS.sp1),
            contentAlignment = Alignment.Center
        ) { text() }
        ImasTierLabelStyle.SWATCH -> Box(
            modifier.width(48.dp).heightIn(min = 34.dp).clip(RoundedCornerShape(DS.rXS)).background(theme.accent),
            contentAlignment = Alignment.Center
        ) { text() }
    }
}

/**
 * 1 段。札と面は [isTarget] のときだけ「ここへ移す」の押し先になる。
 *
 * @param accessibilityLabel 札の読み上げ (「S 3件」など)。
 */
@Composable
fun ImasTierRow(
    label: String,
    seed: String?,
    isTarget: Boolean,
    accessibilityLabel: String,
    onMoveHere: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
        ImasTierLabel(
            label, seed, ImasTierLabelStyle.ROW,
            modifier = Modifier
                .clickable(enabled = isTarget, onClick = onMoveHere)
                .semantics {
                    contentDescription = accessibilityLabel
                    if (isTarget) stateDescription = "選んだものをここへ移す"
                }
        )
        Box(
            Modifier
                .weight(1f)
                .heightIn(min = 72.dp)
                .background(DS.surface)
                .clickable(enabled = isTarget, onClick = onMoveHere),
            contentAlignment = Alignment.TopStart,
            content = content
        )
    }
}

/** 段の中・未分類の並びの並べ方。 */
enum class ImasTierItemsLayout {
    /** 回り込み。段の中 (数が少ない)。 */
    FLOW,

    /** 見えている分だけ描く格子。未分類など、数千件になりうる並びで使う。 */
    GRID
}

/** 段の中・未分類の並び。空のときは 1 行の文 ([emptyText]、null なら何も出さない)。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun <T> ImasTierItems(
    ids: List<T>,
    layout: ImasTierItemsLayout = ImasTierItemsLayout.FLOW,
    emptyText: String? = null,
    modifier: Modifier = Modifier,
    cell: @Composable (T) -> Unit
) {
    if (ids.isEmpty()) {
        ImasText(emptyText ?: "", ImasTextRole.META, modifier = modifier.padding(DS.sp4))
        return
    }
    when (layout) {
        ImasTierItemsLayout.FLOW -> FlowRow(
            modifier = modifier.fillMaxWidth().padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) { ids.forEach { cell(it) } }
        ImasTierItemsLayout.GRID -> LazyVerticalGrid(
            columns = GridCells.Adaptive(66.dp),
            modifier = modifier.fillMaxWidth().padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) { items(ids) { cell(it) } }
    }
}

/** [ImasTierChip] の `media` に渡す大きさ (ジャケ・アイコン 52)。 */
val ImasTierChipMediaSize: Dp = 52.dp

/**
 * 表に置く 1 枚。[media] は渡された大きさ ([ImasTierChipMediaSize]) のジャケかアイコン。
 *
 * @param accessibilityTitle 読み上げの名前。項目が読めなかったときの「不明」など、表示と変えたいときだけ渡す。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ImasTierChip(
    title: String,
    seed: String?,
    brand: String?,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    accessibilityTitle: String? = null,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    media: @Composable (Dp) -> Unit
) {
    val theme = imasTheme(seed, brand)
    val shape = RoundedCornerShape(DS.rSM)
    val scaleValue by animateFloatAsState(if (isSelected) 1.06f else 1f, label = "tierChipScale")
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
        modifier = modifier
            .scale(scaleValue)
            .clip(shape)
            .background(if (isSelected) theme.tint else Color.Transparent)
            .border(if (isSelected) 2.5.dp else 0.dp, theme.accent, shape)
            .then(
                if (onClick != null) Modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick) else Modifier
            )
            .padding(3.dp)
            .semantics {
                contentDescription = accessibilityTitle ?: title
                selected = isSelected
            }
    ) {
        media(ImasTierChipMediaSize)
        Text(
            title, style = ImasType.text(10.sp), color = DS.ink2, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 60.dp)
        )
    }
}

/** 選んでいる間だけ下に出す「〇〇をどこへ？」の帯。 */
@Composable
fun ImasTierMoveBar(
    title: String,
    tiers: List<ImasTierSpec>,
    onCancel: () -> Unit,
    onMove: (String) -> Unit,
    onUnplace: () -> Unit
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(DS.sp3),
        modifier = Modifier.fillMaxWidth().background(DS.surface).padding(horizontal = DS.sp5, vertical = DS.sp3)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                title, style = ImasType.text(15.sp, FontWeight.SemiBold), color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(DS.sp2))
            Text(
                "やめる", style = ImasType.text(15.sp), color = DS.ink2,
                modifier = Modifier.imasPress(onClickLabel = "やめる", onClick = onCancel).padding(DS.sp1)
            )
        }
        // 段は最大 10。6 列で折り返す (1 行に詰めると押せない幅になる)。
        val columns = minOf(6, tiers.size + 1)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth().heightIn(min = DS.Size.touch).height((DS.Size.touch + 6.dp) * (tiers.size / columns + 1))
        ) {
            items(tiers) { tier ->
                Box(modifier = Modifier.imasPress(onClick = { onMove(tier.id) })) {
                    ImasTierLabel(label = tier.label, seed = tier.seed, style = ImasTierLabelStyle.BUTTON)
                }
            }
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = DS.Size.touch)
                        .clip(RoundedCornerShape(DS.rSM))
                        .background(DS.fill)
                        .imasPress(onClickLabel = "未分類へ", onClick = onUnplace),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.Inbox, contentDescription = "未分類へ", tint = DS.ink2, modifier = Modifier.width(18.dp))
                }
            }
        }
    }
}

/** [ImasTierMoveBar] に渡す段の軽い写し (id・名前・色の種だけ)。 */
data class ImasTierSpec(val id: String, val label: String, val seed: String?)
