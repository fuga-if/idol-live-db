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
// 構成      [先頭 (記号・アイコン・ロゴ・色見本、任意)] [文言] [× (Removable のみ)]
// 寸法      高さ 32、角丸 8 の四角 (カプセルにしない)、文字 14 中太、左右 12。
// 状態      未選択 (線) / 選択 (墨の塗り) / 押下 / 無効 (薄く)
// 色        地は墨と灰だけ。名前の前に色の点を置かない (幅を取るだけで、名前が何かを言っている)。
//           色そのものが中身のとき (コールの凡例) だけ先頭に色見本 (Swatch)。淡い色の地 (v1) は使わない。
//
// 色の手がかりは Android の決まりで `seed` = 色 hex、`brand` = ブランド ID (色はマスタから引く)。
// =============================================================================

/** チップの先頭に置けるもの (iOS `ImasChipLeading`)。 */
@Immutable
sealed interface ImasChipLeading {
    /** 記号。 */
    data class Symbol(val icon: ImageVector) : ImasChipLeading

    /**
     * 以前のペンライト (色の点)。今は何も描かない (幅を取るだけで、名前が何かを言っている)。
     * 色そのものが中身のときは [Swatch]。
     */
    data object Dot : ImasChipLeading

    /** 色見本。色そのものが中身のとき (コールの凡例: この色 = この強さ) だけ使う。 */
    data class Swatch(val color: Color) : ImasChipLeading

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
    /** 線。実体に属する情報 (ブランド・ユニット・タグ)。 */
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
 * @param count 本文の後に添える件数 (「5」等)。本文だけを省略し、件数は折り返さず必ず最後まで出す
 *   (タグの使用数など、本文が長い時に件数ごと消えないように)。
 * @param onClick 押して行く先 (最近見た・関連)。iOS の `ImasChip` は押せないが、Android の今の呼び出し
 *   (アイドル詳細の属性・年表のブランド) が押して進むので受けておく。新しく押せるチップを作るなら [ImasFilterChip]。
 * @param trailing 末尾に置くもの (チップの文字色 [ImasChipColors.Colors.fg] が渡る)。
 *   選んでいる間だけ解除の口を出すチップ ([ImasFilterChip] の `onClear`) で使う。
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
    count: String? = null,
    trailing: (@Composable (tint: Color) -> Unit)? = null,
    onClick: (() -> Unit)? = null
) {
    val t = ImasChipColors.theme(seed, brand, color)
    val c = ImasChipColors.colors(style)
    val shape = RoundedCornerShape(DS.rControl(DS.Size.chip))
    val lead = (leading ?: icon?.let { ImasChipLeading.Symbol(it) }).drawn()
    Row(
        modifier
            .then(if (onClick != null) Modifier.imasPress(onClick = onClick) else Modifier)
            .heightIn(min = DS.Size.chip)
            .then(if (fillsWidth) Modifier.fillMaxWidth() else Modifier)
            .background(c.bg, shape)
            .then(if (c.stroke != null) Modifier.border(1.dp, c.stroke, shape) else Modifier)
            .padding(start = if (lead == null) 12.dp else 10.dp, end = if (trailing == null) 12.dp else 10.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp, if (fillsWidth) Alignment.CenterHorizontally else Alignment.Start),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasChipLeadingView(lead, t, c.fg)
        Text(
            text,
            // count がある時だけ本文を縮める側に回す (件数は縮めない。無い時は今まで通り)。
            modifier = if (count != null) Modifier.weight(1f, fill = false) else Modifier,
            style = ImasTextRole.CHIP.style,
            color = c.fg,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        if (count != null) {
            Text(count, style = ImasTextRole.CHIP.style, color = c.fg, maxLines = 1)
        }
        trailing?.invoke(c.fg)
    }
}

/**
 * 押して選択を切り替えるチップ (iOS `ImasFilterChip`)。フィルタ・カテゴリ・種別・タグ・歌唱メンバーの予想の「唯一の正」。
 * 見た目は [ImasChip] と同じで、押下と選択状態だけを足す (選択 = 墨の塗り、未選択 = 線)。
 *
 * 引数の名前は Android の今の呼び出しに合わせる (iOS の `text` / `isSelected` / `action` が
 * [label] / [selected] / [onClick])。
 *
 * @param tintColor 実体色そのもの (iOS の `color`)。
 * @param icon 先頭の記号 (iOS の `systemImage`)。
 * @param onClear 渡すと末尾に解除の口 (×) を出す (押すと別の選び方 (ピッカー) を開くチップで、
 *   選んでいる間だけその場で解除したいとき。例: 会場チップ)。選んでいないときは呼び出し側で null を渡す。
 * @param clearContentDescription 解除の口の読み上げ。省略すると「[label] を解除」。
 * @param count 本文の後に添える件数。[label] だけを省略し、件数は必ず最後まで出す (タグの使用数等)。
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
    leading: ImasChipLeading? = null,
    // 見た目の文字 (label) と読み上げの動詞が食い違う時だけ渡す (例: 「Good」始点だが「Good を付ける」と読む)。
    onClickLabel: String? = null,
    // 見た目の文字 (件数だけ等) だけでは本文の読み上げが意味を持たない時に渡す
    // (例: 「5」だけでなく「Good を取り消す、5件」と読ませる)。指定すると行の読み上げをこれで差し替える。
    contentDescription: String? = null,
    onClear: (() -> Unit)? = null,
    clearContentDescription: String? = null,
    count: String? = null
) {
    val haptics = rememberImasHaptics()
    val lead = leading
    // 型を先に決めておかないと (if 式の分岐から推論させると)、Compose コンパイラが
    // このラムダを @Composable と認識できないことがある。
    val clearTrailing: (@Composable (Color) -> Unit)? = if (onClear == null) {
        null
    } else {
        { tint: Color ->
            val xSize = with(LocalDensity.current) { 18.sp.toDp() }
            Icon(
                Icons.Filled.Close,
                contentDescription = clearContentDescription ?: "$label を解除",
                tint = tint,
                modifier = Modifier
                    .size(xSize)
                    .imasPress(onClick = onClear)
            )
        }
    }
    ImasChip(
        text = label,
        modifier = modifier
            .imasPress(enabled = !isDisabled, onClickLabel = onClickLabel) {
                haptics.selection()
                onClick()
            }
            .alpha(if (isDisabled) 0.45f else 1f)
            .then(
                if (contentDescription != null) {
                    Modifier.clearAndSetSemantics {
                        this.contentDescription = contentDescription
                        this.selected = selected
                    }
                } else {
                    Modifier.semantics { this.selected = selected }
                }
            ),
        icon = icon,
        style = if (selected) ImasChipStyle.SELECTED else ImasChipStyle.OUTLINED,
        seed = seed,
        brand = brand,
        color = tintColor,
        fillsWidth = fillsWidth,
        leading = lead,
        count = count,
        trailing = clearTrailing
    )
}

/**
 * 押すと外れるチップ (iOS `ImasRemovableChip`)。効いている絞り込み・選んだものを見せて、その場で外させる。
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
    val lead = leading.drawn()
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
        ImasChipLeadingView(lead, t, DS.ink)
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
        // 題だけ省略する (「優勝」「第N位」の札が長い題と一緒に切れて消えないように)。
        Text(
            title,
            modifier = Modifier.weight(1f, fill = false),
            style = ImasTextRole.CHIP.style,
            color = if (isWinner) DS.onSys else DS.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        Text(
            rankLabel,
            style = ImasTextRole.CHIP.style,
            color = if (isWinner) DS.onSys else DS.ink,
            maxLines = 1
        )
    }
}

// MARK: - 内部

/** 描くものがある先頭だけ ([ImasChipLeading.Dot] は何も描かないので、無いのと同じに扱って左右の余白を揃える)。 */
private fun ImasChipLeading?.drawn(): ImasChipLeading? = takeUnless { it == ImasChipLeading.Dot }

/** チップの先頭。 */
@Composable
private fun ImasChipLeadingView(leading: ImasChipLeading?, theme: ImasTheme, tint: Color) {
    when (leading) {
        // 色の点は出さない (幅を取るだけで、名前が何かを言っている)。
        null, ImasChipLeading.Dot -> Unit
        is ImasChipLeading.Symbol -> {
            val s = with(LocalDensity.current) { 13.sp.toDp() }
            Icon(leading.icon, contentDescription = null, tint = tint, modifier = Modifier.size(s))
        }
        is ImasChipLeading.Swatch -> {
            // 凡例の色。意味は隣の文言が言うので読み上げない (文字の大きさの設定に合わせて大きくする)。
            val d = with(LocalDensity.current) { 8.sp.toDp() }
            Box(Modifier.size(d).background(leading.color, CircleShape))
        }
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
