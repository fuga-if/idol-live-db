package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.AsyncImage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.LocalImasTheme
import com.fugaif.imaslivedb.ui.theme.imasEnvTheme
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import java.io.File

// =============================================================================
// チップ (docs/DESIGN_SYSTEM.md §8.2)。iOS `ImasChips.swift` の移植。
//
// 用途      ImasChip          情報の小さな札 (押せない)。ブランド・種類・タグ
//           ImasFilterChip    押すと選択が切り替わる。絞り込み・カテゴリ・歌唱メンバーの予想
//           ImasRemovableChip 押すと外れる。効いている絞り込み・選んだもの
// 使わない  状態を示す小さい札 (参加済・ユニット・NEW) → ImasBadge / 操作のボタン → ImasButton
// 構成      [先頭 (ペンライト・記号・アイコン、任意)] [文言] [× (Removable のみ)]
// 寸法      高さ 32、角丸 8 の四角 (カプセルにしない)、文字 14 中太、左右 12。
// 状態      未選択 (線) / 選択 (墨の塗り。ペンライトはそのまま光る) / 押下 / 無効 (薄く)
// 色        地は墨と灰だけ。アイドル・ブランドの色は先頭のペンライトに出す。淡い色の地 (v1) は使わない。
//
// 色の手がかりは Android の決まりで `seed` = 色 hex、`brand` = ブランド ID (色はマスタから引く)。
// =============================================================================

/** チップの先頭に置けるもの (iOS `ImasChipLeading`)。 */
@Immutable
sealed interface ImasChipLeading {
    /** 記号。 */
    data class Symbol(val icon: ImageVector) : ImasChipLeading

    /** ペンライト (アイドル・ブランドの色)。 */
    data object Dot : ImasChipLeading

    /**
     * アイドルのアイコン (22)。写真があれば写真、無ければ判子。
     * [entityId] を渡すと端末に取り込んだ写真を引く ([ImasAvatar] と同じ)。
     */
    data class Avatar(val label: String, val imageUrl: String? = null, val entityId: String? = null) : ImasChipLeading

    /** 読み込んだブランドのロゴ (端末の中のファイル、20 の丸)。 */
    data class Logo(val file: File) : ImasChipLeading
}

/** チップの見え方 (iOS `ImasChipStyle`)。 */
enum class ImasChipStyle {
    /** 線 + ペンライト。実体に属する情報 (ブランド・ユニット)。 */
    THEMED,

    /** 墨の塗り。選んだもの。 */
    SELECTED,

    /** 灰の地。目立たせない情報。 */
    NEUTRAL,

    /** 線だけ。押すとその画面へ行くチップ (最近見た・関連) と、選んでいない切り替え。 */
    OUTLINED
}

/**
 * 情報の小さな札 (iOS `ImasChip`)。押せるようにするなら [ImasFilterChip]。
 *
 * @param icon 先頭の記号 (iOS の `systemImage`)。[leading] を渡せばそちらが勝つ。
 * @param color 実体色そのもの (ユーザーが選んだタグ色等)。seed/brand より優先し、素の色を塗らずに
 *   WCAG の計算を通す (どんな明るさでも文字が読める側に倒れる)。
 * @param fillsWidth 格子の中で幅を揃えたいとき true。
 * @param onClick 押して行く先 (最近見た・関連)。iOS の `ImasChip` は押せないが、Android の今の呼び出し
 *   (アイドル詳細の属性・年表のブランド) が押して進むので受けておく。新しく押せるチップを作るなら [ImasFilterChip]。
 */
@Composable
fun ImasChip(
    text: String,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    style: ImasChipStyle = ImasChipStyle.NEUTRAL,
    seed: String? = null,
    brand: String? = null,
    color: Color? = null,
    fillsWidth: Boolean = false,
    leading: ImasChipLeading? = null,
    onClick: (() -> Unit)? = null
) {
    val t = ImasChipColors.theme(seed, brand, color)
    val c = ImasChipColors.colors(style)
    val shape = RoundedCornerShape(DS.rControl(DS.Size.chip))
    val lead = leading ?: icon?.let { ImasChipLeading.Symbol(it) } ?: if (style == ImasChipStyle.THEMED) ImasChipLeading.Dot else null
    val penlight = if (style == ImasChipStyle.SELECTED) ImasChipColors.penlightOnInk(seed, brand, color, t) else t.penlight
    Row(
        modifier
            .then(if (onClick != null) Modifier.imasPress(onClick = onClick) else Modifier)
            .heightIn(min = DS.Size.chip)
            .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
            .background(c.bg, shape)
            .then(if (c.stroke != null) Modifier.border(1.dp, c.stroke, shape) else Modifier)
            .padding(start = if (lead == null) 12.dp else 10.dp, end = 12.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, if (fillsWidth) Alignment.CenterHorizontally else Alignment.Start),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasChipLeadingView(lead, t, penlight, c.fg)
        Text(
            text,
            style = ImasTextRole.CHIP.style,
            color = c.fg,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

/**
 * 押して選択を切り替えるチップ (iOS `ImasFilterChip`)。フィルタ・カテゴリ・種別・タグ・歌唱メンバーの予想の「唯一の正」。
 * 見た目は [ImasChip] と同じで、押下と選択状態だけを足す (選択 = 墨の塗り、未選択 = 線)。
 *
 * 引数の名前は Android の今の呼び出しに合わせる (iOS の `text` / `isSelected` / `action` が
 * [label] / [selected] / [onClick])。
 *
 * 色の手がかり (seed / brand / tintColor) を渡して先頭を指定しないときは、先頭にペンライトを出す
 * (iOS は `leading: .dot` を明示する。Android の今のブランドのチップは色だけを渡していて、
 * 何もしないと選んだときの色が消えるため)。色の無いもの (ニュートラル) には出さない。
 *
 * @param tintColor 実体色そのもの (iOS の `color`)。
 * @param icon 先頭の記号 (iOS の `systemImage`)。
 */
@Composable
fun ImasFilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    seed: String? = null,
    brand: String? = null,
    tintColor: Color? = null,
    icon: ImageVector? = null,
    modifier: Modifier = Modifier,
    fillsWidth: Boolean = false,
    isDisabled: Boolean = false,
    leading: ImasChipLeading? = null
) {
    val haptics = rememberImasHaptics()
    val hinted = seed != null || brand != null || tintColor != null
    val lead = leading ?: if (icon == null && hinted && !ImasChipColors.theme(seed, brand, tintColor).isNeutral) {
        ImasChipLeading.Dot
    } else null
    ImasChip(
        text = label,
        modifier = modifier
            .imasPress(enabled = !isDisabled) {
                haptics.selection()
                onClick()
            }
            .alpha(if (isDisabled) 0.45f else 1f)
            .semantics { this.selected = selected },
        icon = icon,
        style = if (selected) ImasChipStyle.SELECTED else ImasChipStyle.OUTLINED,
        seed = seed,
        brand = brand,
        color = tintColor,
        fillsWidth = fillsWidth,
        leading = lead
    )
}

/**
 * 押すと外れるチップ (iOS `ImasRemovableChip`)。効いている絞り込み・選んだものを見せて、その場で外させる。
 * 色のある絞り込み (seed / brand を渡したもの) は何も渡さなくてもペンライトを出す。
 */
@Composable
fun ImasRemovableChip(
    text: String,
    onRemove: () -> Unit,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null,
    leading: ImasChipLeading? = null
) {
    val t = ImasChipColors.theme(seed, brand, null)
    val shape = RoundedCornerShape(DS.rControl(DS.Size.chip))
    val lead = leading ?: if (seed != null || brand != null) ImasChipLeading.Dot else null
    val xSize = with(LocalDensity.current) { 11.sp.toDp() }
    Row(
        modifier
            .imasPress(onClickLabel = "$text を外す", onClick = onRemove)
            .semantics(mergeDescendants = true) { contentDescription = "$text を外す" }
            .heightIn(min = DS.Size.chip)
            .background(DS.fill, shape)
            .padding(start = if (lead == null) 12.dp else 10.dp, end = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasChipLeadingView(lead, t, t.penlight, DS.ink)
        Text(text, style = ImasTextRole.CHIP.style, color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Icon(Icons.Filled.Close, contentDescription = null, tint = DS.ink2, modifier = Modifier.size(xSize))
    }
}

// MARK: - 並べ方

/** [ImasChipRow] の端の透かしの幅。 */
private val ChipRowFadeWidth = 18.dp

/**
 * チップを 1 段で横に並べ、はみ出したら横にスクロールする (iOS `ImasChipRow`)。2 段以上にはしない。
 * 画面の端から端まで置く (中身の左右は画面の余白 [contentPadding] だけ空く)。
 *
 * @param fades 隠れている側の端をグラデーションで透かして「続きがある」ことを示す
 *   (先に続きがある側だけ小さい矢印も重ねる。カテゴリの絞り込み列などで使う)。
 */
@Composable
fun ImasChipRow(
    modifier: Modifier = Modifier,
    fades: Boolean = false,
    contentPadding: Dp = DS.Space.screen,
    content: @Composable RowScope.() -> Unit
) {
    val state = rememberScrollState()
    val row: @Composable () -> Unit = {
        Row(
            Modifier
                .horizontalScroll(state)
                .padding(horizontal = contentPadding),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
            verticalAlignment = Alignment.CenterVertically,
            content = content
        )
    }
    if (!fades) {
        Box(modifier.fillMaxWidth()) { row() }
        return
    }
    Box(modifier.fillMaxWidth()) {
        Box(
            Modifier
                .fillMaxWidth()
                .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                .drawWithContent {
                    drawContent()
                    val w = ChipRowFadeWidth.toPx()
                    if (state.canScrollBackward) {
                        drawRect(
                            Brush.horizontalGradient(listOf(Color.Transparent, Color.Black), startX = 0f, endX = w),
                            topLeft = Offset.Zero,
                            size = Size(w, size.height),
                            blendMode = BlendMode.DstIn
                        )
                    }
                    if (state.canScrollForward) {
                        drawRect(
                            Brush.horizontalGradient(
                                listOf(Color.Black, Color.Transparent),
                                startX = size.width - w,
                                endX = size.width
                            ),
                            topLeft = Offset(size.width - w, 0f),
                            size = Size(w, size.height),
                            blendMode = BlendMode.DstIn
                        )
                    }
                }
        ) { row() }
        if (state.canScrollForward) {
            Icon(
                Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = DS.ink3,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .size(16.dp)
                    .clearAndSetSemantics { }
            )
        }
    }
}

/** チップを幅で折り返して並べる (iOS `ImasChipFlow`)。1 つが幅より広いときは幅に収めて省略する。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImasChipFlow(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    FlowRow(
        modifier = modifier,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
        content = { content() }
    )
}

// MARK: - 選択の印

/**
 * ピッカー・複数選択の印 (iOS `ImasSelectionMark`)。複数選択 = ○ と塗りの ✓、1 つ選択 = ✓ だけ。
 * 色は実体の accent (無ければ墨)。読み上げは行が持つ (印は隠す)。
 */
@Composable
fun ImasSelectionMark(
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null,
    color: Color? = null,
    size: Dp = 20.dp,
    isSingle: Boolean = false
) {
    val t = ImasChipColors.theme(seed, brand, color)
    val accent = if (t.isNeutral) DS.sys else t.accent
    // iOS は文字の大きさ (imasScaled) で記号を組むので、文字の設定に合わせて大きくする。
    val glyph = with(LocalDensity.current) { size.value.sp.toDp() }
    Box(
        modifier
            .size(glyph + 4.dp)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center
    ) {
        if (isSingle) {
            Icon(
                Icons.Filled.Check,
                contentDescription = null,
                tint = accent,
                modifier = Modifier.size(glyph * 0.9f).alpha(if (isSelected) 1f else 0f)
            )
        } else {
            Icon(
                if (isSelected) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
                contentDescription = null,
                tint = if (isSelected) accent else DS.ink3,
                modifier = Modifier.size(glyph)
            )
        }
    }
}

// MARK: - 受賞の札

/**
 * 「みんなの投票」終了お題での順位 (iOS `ImasAwardChip`)。優勝 = 墨の塗り + 金の冠、入賞 (2〜3 位) = 線 + 金の記章。
 * チップと同じ寸法で、曲詳細・アイドル詳細の頭に並べる。
 */
@Composable
fun ImasAwardChip(title: String, rank: Int, modifier: Modifier = Modifier) {
    val isWinner = rank == 1
    val rankLabel = if (isWinner) "優勝" else "第${rank}位"
    val shape = RoundedCornerShape(DS.rControl(DS.Size.chip))
    val iconSize = with(LocalDensity.current) { 13.sp.toDp() }
    Row(
        modifier
            .heightIn(min = DS.Size.chip)
            .background(if (isWinner) DS.sys else Color.Transparent, shape)
            .then(if (!isWinner) Modifier.border(1.dp, DS.line, shape) else Modifier)
            .padding(horizontal = 12.dp)
            .semantics(mergeDescendants = true) { contentDescription = "$title で$rankLabel" },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            if (isWinner) Icons.Filled.EmojiEvents else Icons.Filled.WorkspacePremium,
            contentDescription = null,
            tint = DS.favorite,
            modifier = Modifier.size(iconSize)
        )
        Text(
            "$title $rankLabel",
            style = ImasTextRole.CHIP.style,
            color = if (isWinner) DS.onSys else DS.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
    }
}

// MARK: - 内部

/** チップの先頭。 */
@Composable
private fun ImasChipLeadingView(leading: ImasChipLeading?, theme: ImasTheme, penlight: Color, tint: Color) {
    when (leading) {
        null -> Unit
        is ImasChipLeading.Symbol -> {
            val s = with(LocalDensity.current) { 13.sp.toDp() }
            Icon(leading.icon, contentDescription = null, tint = tint, modifier = Modifier.size(s))
        }
        ImasChipLeading.Dot -> ImasPenlight(color = penlight, size = ImasPenlightSize.SMALL)
        is ImasChipLeading.Avatar -> {
            // 写真があれば写真、無ければ判子 (アイコンは消さない)。
            CompositionLocalProvider(LocalImasTheme provides theme) {
                ImasAvatar(
                    label = leading.label,
                    size = 22.dp,
                    imageUrl = leading.imageUrl,
                    entityId = leading.entityId,
                    reservesPickRing = false,
                    modifier = Modifier.offset(x = (-4).dp)
                )
            }
        }
        is ImasChipLeading.Logo -> {
            if (leading.file.exists()) {
                AsyncImage(
                    model = leading.file,
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .offset(x = (-3).dp)
                        .size(20.dp)
                        .clip(CircleShape)
                )
            } else {
                ImasPenlight(color = penlight, size = ImasPenlightSize.SMALL)
            }
        }
    }
}

/** チップの地・文字・線の色。 */
@Immutable
data class ImasChipPalette(val bg: Color, val fg: Color, val stroke: Color?)

/** チップの家族の色の決め方 (iOS `ImasChipColors`)。明示の色 → seed / brand → 環境の実体の色。 */
object ImasChipColors {
    /** 部品の実体の色。 */
    @Composable
    @ReadOnlyComposable
    fun theme(seed: String?, brand: String?, color: Color?): ImasTheme = when {
        color != null -> imasTheme(color)
        seed != null || brand != null -> imasThemeForBrand(seed, brand)
        else -> imasEnvTheme
    }

    /**
     * 墨の塗り (選択) の上のペンライト。塗りは画面と逆の明るさなので、逆の明るさ用の色を引く
     * (ライトの紺は黒い塗りの上で沈む)。
     */
    @Composable
    @ReadOnlyComposable
    fun penlightOnInk(seed: String?, brand: String?, color: Color?, fallback: ImasTheme): Color {
        val inverse = !LocalImasColors.current.dark
        val t = when {
            color != null -> ImasTheme.derive(color, inverse)
            seed != null || brand != null -> ImasTheme.forBrand(seed, brand, inverse)
            else -> return if (fallback.isNeutral) DS.onSys else fallback.penlight
        }
        return if (t.isNeutral) DS.onSys else t.dot
    }

    /** 見え方ごとの地・文字・線。 */
    @Composable
    @ReadOnlyComposable
    fun colors(style: ImasChipStyle): ImasChipPalette = when (style) {
        ImasChipStyle.THEMED -> ImasChipPalette(Color.Transparent, DS.ink, DS.line)
        ImasChipStyle.SELECTED -> ImasChipPalette(DS.sys, DS.onSys, null)
        ImasChipStyle.NEUTRAL -> ImasChipPalette(DS.fill, DS.ink2, null)
        ImasChipStyle.OUTLINED -> ImasChipPalette(Color.Transparent, DS.ink, DS.line)
    }
}
