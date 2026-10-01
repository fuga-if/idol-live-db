package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Inventory2
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.StarBorder
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.outlined.Inventory2
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.components.CopyItem
import com.fugaif.imaslivedb.ui.components.Copyable
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasMotion
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.penlight
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import androidx.compose.ui.text.font.FontWeight

// =============================================================================
// 行 (docs/DESIGN_SYSTEM.md §5)。iOS `ImasRow.swift` の移植。
//
// 用途      一覧・カードの中で、1 つのものを 1 行で見せる。
// 構成      [先頭] [題 (16 太字・2 行まで) / 副題 (13 灰) / 下段 (札・日付)] [末尾]
// 種類      REGULAR (一覧・上下 12) / COMPACT (カードの中の短い一覧・ピッカー・上下 8)
// 状態      通常 / 押下 (面が fill) / 選択 (先頭の選択印) / 薄字 (欠席・未配信) / 無効
// 区切り線  行が持つ。`ImasCardList(items)` の中では 2 行目以降の上に本文の頭から線を引く。
//           画面で Divider を書かない。
//
// 実体ごとの行 (ImasSongRow など) はこの形の中身を実体のデータから決めたもの。
// Compose の行は押せる口を持たないので、押して進む行は `Modifier.imasRowPress` を渡すか、
// 入口の行 ([ImasNavRow] など) の onClick を使う。
// =============================================================================

/** 行の先頭に置けるもの (iOS `ImasRowLeading`)。色の手がかりは seed = 色 hex、brand = ブランド ID。 */
@Immutable
sealed interface ImasRowLeading {
    data object None : ImasRowLeading

    /** ライブ・公演のリードバー (実体の色の細い帯)。 */
    data class Bar(val seed: String? = null, val brand: String? = null, val rainbow: Boolean = false) : ImasRowLeading

    /** アイドルのアイコン (40)。写真があれば写真、無ければ判子。[entityId] で端末に取り込んだ写真を引く。 */
    data class Avatar(
        val label: String,
        val seed: String? = null,
        val brand: String? = null,
        val imageUrl: String? = null,
        val isPick: Boolean = false,
        val entityId: String? = null
    ) : ImasRowLeading

    /** 曲のジャケ (48、COMPACT は 40)。 */
    data class Artwork(
        val title: String,
        val seed: String? = null,
        val brand: String? = null,
        val imageUrl: String? = null,
        val isCollected: Boolean = false
    ) : ImasRowLeading

    /** 記号 (幅 28、地なし)。seed / brand を渡すとその実体の色で点く (予定の種類・ブランド)。 */
    data class Icon(
        val icon: ImageVector,
        val tone: ImasIconTileTone = ImasIconTileTone.THEMED,
        val seed: String? = null,
        val brand: String? = null
    ) : ImasRowLeading

    /** 曲順・番号 (等幅)。 */
    data class Number(val text: String) : ImasRowLeading

    /** 曲順 + ジャケ (セトリ)。 */
    data class NumberedArtwork(
        val number: String,
        val title: String,
        val seed: String? = null,
        val brand: String? = null,
        val imageUrl: String? = null,
        val isCollected: Boolean = false
    ) : ImasRowLeading

    /** 順位。1〜3 位は墨。 */
    data class Rank(val rank: Int) : ImasRowLeading

    /** 選択の印 (ピッカー)。 */
    data class Selection(val isOn: Boolean, val single: Boolean = false) : ImasRowLeading

    /**
     * 部品の外で作った先頭 (ゲーム・特殊な一覧のみ。増やす前に種類を足せないか考える)。
     * [width] は先頭の幅 (区切り線を本文の頭に揃えるため)、[alignment] は行の中の縦の揃え。
     */
    class Custom(
        val width: Dp,
        val alignment: Alignment.Vertical = Alignment.CenterVertically,
        val content: @Composable () -> Unit
    ) : ImasRowLeading
}

/** 行の末尾に置けるもの (iOS `ImasRowTrailing`)。 */
@Immutable
sealed interface ImasRowTrailing {
    data object None : ImasRowTrailing

    /** 別画面へ進む矢印 (カードの中の行のみ。一覧の行には出さない)。 */
    data object Chevron : ImasRowTrailing

    /** 値 (灰)。 */
    data class Value(val text: String) : ImasRowTrailing

    /** 数字 + 単位。並べ替えの根拠・票・回数。 */
    data class Metric(val value: String, val unit: String? = null, val emphasized: Boolean = false) : ImasRowTrailing

    /** 状態の札。 */
    data class Badge(
        val text: String,
        val kind: ImasBadgeKind = ImasBadgeKind.NEUTRAL,
        val icon: ImageVector? = null,
        val seed: String? = null
    ) : ImasRowTrailing

    /** スイッチ。 */
    class Toggle(val isOn: Boolean, val onChange: (Boolean) -> Unit) : ImasRowTrailing

    /** 印 (担当・お気に入り) をその場で付け外しする記号のボタン。 */
    class Mark(val kind: ImasMarkKind, val isOn: Boolean, val onClick: () -> Unit) : ImasRowTrailing

    /** 部品の外で作った末尾 (「予想する」ボタン・印のボタンなど)。 */
    class Custom(val content: @Composable () -> Unit) : ImasRowTrailing
}

/** 行の詰め方 (iOS `ImasRowDensity`)。 */
enum class ImasRowDensity(val verticalPadding: Dp, val artworkSize: Dp, val avatarSize: Dp) {
    /** 一覧 (上下 12)。 */
    REGULAR(DS.Space.rowV, 48.dp, 40.dp),

    /** カードの中の短い一覧・ピッカー (上下 8)。 */
    COMPACT(DS.Space.rowVCompact, 40.dp, 32.dp)
}

/** 行の強さ (iOS `ImasRowEmphasis`)。 */
enum class ImasRowEmphasis {
    NORMAL,

    /** 欠席・未配信・終わったもの。題と副題を薄くする。 */
    DIMMED
}

/** 行頭の色の帯 (iOS `ImasRowLeadBar`。ブランド・実体の色)。先頭 (ジャケなど) の前に立てる。brand はブランド ID。 */
@Immutable
data class ImasRowLeadBar(val seed: String? = null, val brand: String? = null, val rainbow: Boolean = false)

/** 行の頭に置く選択の印 (iOS `ImasRowSelection`。`ImasSelectableRow` が使う)。 */
@Immutable
data class ImasRowSelection(
    val isOn: Boolean,
    val single: Boolean = false,
    val seed: String? = null,
    val brand: String? = null
)

/** 文字の大きさの設定がこれを超えたら、末尾を本文の下の段に回す (iOS の `isAccessibilitySize`)。 */
private const val AccessibilityFontScale = 1.6f

/**
 * 行の共通の形 (iOS `ImasRow`)。
 *
 * @param subtitle 副題 (13 灰・1 行)。
 * @param selection 先頭の前に置く選択の印。先頭 (ジャケ・アイコン) と並べて出せる。
 * @param leadBar 先頭の前に立てる色の帯。
 * @param titleLineLimit 題の行数。
 * @param subtitleLineLimit 副題の行数。既定は 1 行 (値を添えるだけの行)。説明文が長い行は 2。
 * @param attributedTitle 題の代わりに強調付きの文字 (絞り込みで当たった所に色を敷くなど)。
 * @param titleRole 題の書体。もの (曲・アイドル・ライブ) は ROW_TITLE、操作・設定は ROW_LABEL。
 * @param onSelectTitle 題だけを押せるようにする (行の他の場所にも別の押せる物があるとき)。
 * @param titleAccessibilityLabel 題の読み上げを見た目と変えたいとき (「タグ: 〇〇」など前置きを足す)。
 * @param position 並びの中の位置。null なら [LocalImasRowPosition] (`ImasCardList(items)` が伝える)。
 * @param detail 下段 (札・日付・回数)。
 */
@Composable
fun ImasRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leading: ImasRowLeading = ImasRowLeading.None,
    selection: ImasRowSelection? = null,
    leadBar: ImasRowLeadBar? = null,
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    density: ImasRowDensity = ImasRowDensity.REGULAR,
    emphasis: ImasRowEmphasis = ImasRowEmphasis.NORMAL,
    titleLineLimit: Int = 2,
    subtitleLineLimit: Int = 1,
    attributedTitle: AnnotatedString? = null,
    titleRole: ImasTextRole = ImasTextRole.ROW_TITLE,
    onSelectTitle: (() -> Unit)? = null,
    titleAccessibilityLabel: String? = null,
    position: ImasRowPosition? = null,
    detail: (@Composable ColumnScope.() -> Unit)? = null
) {
    val leadingWidth = leadingWidth(leading, density)
    val markWidth = if (selection == null) 0.dp else 24.dp + DS.Space.rowGap
    val barWidth = if (leadBar == null) 0.dp else DS.Size.leadBar + DS.Space.rowGap
    val inset = DS.Space.rowH + markWidth + barWidth + leadingWidth + if (leadingWidth > 0.dp) DS.Space.rowGap else 0.dp
    val accessibilitySize = LocalDensity.current.fontScale >= AccessibilityFontScale
    val alignment = rowAlignment(leading)

    val main: @Composable (Modifier) -> Unit = { mainModifier ->
        Row(
            mainModifier,
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
            verticalAlignment = alignment ?: Alignment.CenterVertically
        ) {
            if (selection != null) {
                ImasSelectionMark(
                    isSelected = selection.isOn,
                    seed = selection.seed,
                    brand = selection.brand,
                    isSingle = selection.single
                )
            }
            if (leadBar != null) {
                ImasLeadBar(
                    seedHex = leadBar.seed,
                    brandId = leadBar.brand,
                    rainbow = leadBar.rainbow,
                    height = leadBarHeight(leading, density)
                )
            }
            // 曲順・順位は数字のベースラインを題の 1 行目に揃える。
            ImasRowLeadingView(leading, density, if (alignment == null) Modifier.alignByBaseline() else Modifier)
            Column(
                Modifier
                    .weight(1f)
                    .then(if (alignment == null) Modifier.alignByBaseline() else Modifier),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
            ) {
                ImasRowTitle(title, attributedTitle, titleRole, emphasis, titleLineLimit, onSelectTitle, titleAccessibilityLabel)
                if (!subtitle.isNullOrEmpty()) {
                    Text(
                        subtitle,
                        style = ImasTextRole.ROW_SUBTITLE.style,
                        color = if (emphasis == ImasRowEmphasis.DIMMED) DS.ink3 else DS.ink2,
                        maxLines = subtitleLineLimit,
                        overflow = TextOverflow.Ellipsis
                    )
                }
                detail?.invoke(this)
            }
            if (!accessibilitySize) ImasRowTrailingView(trailing)
        }
    }

    val outer = modifier
        .fillMaxWidth()
        .imasRowTopDivider(inset, position ?: LocalImasRowPosition.current)
        .heightIn(min = DS.Size.touch)
        .padding(horizontal = DS.Space.rowH, vertical = density.verticalPadding)

    if (accessibilitySize && trailing !is ImasRowTrailing.None) {
        Column(outer, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            main(Modifier.fillMaxWidth())
            ImasRowTrailingView(trailing)
        }
    } else {
        Box(outer, contentAlignment = Alignment.CenterStart) { main(Modifier.fillMaxWidth()) }
    }
}

/** 曲順・順位は題の 1 行目に揃える (null = ベースライン揃え)。曲順 + ジャケは上揃え。ほかは行の中央。 */
private fun rowAlignment(leading: ImasRowLeading): Alignment.Vertical? = when (leading) {
    is ImasRowLeading.Number, is ImasRowLeading.Rank -> null
    is ImasRowLeading.NumberedArtwork -> Alignment.Top
    is ImasRowLeading.Custom -> leading.alignment
    else -> Alignment.CenterVertically
}

/** 先頭の幅 (区切り線を本文の頭に揃えるため)。 */
private fun leadingWidth(leading: ImasRowLeading, density: ImasRowDensity): Dp = when (leading) {
    ImasRowLeading.None -> 0.dp
    is ImasRowLeading.Bar -> DS.Size.leadBar
    is ImasRowLeading.Avatar -> density.avatarSize + ImasAvatarRingPadding * 2
    is ImasRowLeading.Artwork -> density.artworkSize
    is ImasRowLeading.Icon -> ImasIconTileSize.S28.frame
    is ImasRowLeading.Number -> 30.dp
    is ImasRowLeading.NumberedArtwork -> 24.dp + 10.dp + 44.dp
    is ImasRowLeading.Rank -> ImasRankNumberWidth
    is ImasRowLeading.Selection -> 24.dp
    is ImasRowLeading.Custom -> leading.width
}

/** 色の帯の高さ。ジャケと並ぶときはジャケの高さに揃える。 */
private fun leadBarHeight(leading: ImasRowLeading, density: ImasRowDensity): Dp = when (leading) {
    is ImasRowLeading.Artwork -> density.artworkSize
    is ImasRowLeading.NumberedArtwork -> 44.dp
    // 呼び出し側がジャケ等を直書きした先頭 (試聴対応の曲の行など)。幅がその面の一辺 (正方形)。
    is ImasRowLeading.Custom -> leading.width
    else -> 36.dp
}

@Composable
private fun ImasRowTitle(
    title: String,
    attributed: AnnotatedString?,
    role: ImasTextRole,
    emphasis: ImasRowEmphasis,
    maxLines: Int,
    onSelectTitle: (() -> Unit)?,
    accessibilityLabel: String?
) {
    val color = if (emphasis == ImasRowEmphasis.DIMMED) DS.ink3 else DS.ink
    val m = (if (onSelectTitle != null) Modifier.fillMaxWidth().clickable(onClick = onSelectTitle) else Modifier)
        .then(if (accessibilityLabel != null) Modifier.semantics { contentDescription = accessibilityLabel } else Modifier)
    if (attributed != null) {
        Text(attributed, style = role.style, color = color, maxLines = maxLines, overflow = TextOverflow.Ellipsis, modifier = m)
    } else {
        Text(title, style = role.style, color = color, maxLines = maxLines, overflow = TextOverflow.Ellipsis, modifier = m)
    }
}

@Composable
private fun ImasRowLeadingView(leading: ImasRowLeading, density: ImasRowDensity, modifier: Modifier) {
    when (leading) {
        ImasRowLeading.None -> Unit
        is ImasRowLeading.Bar -> ImasLeadBar(seedHex = leading.seed, brandId = leading.brand, height = 36.dp, rainbow = leading.rainbow)
        is ImasRowLeading.Avatar -> ImasAvatar(
            label = leading.label,
            seed = leading.seed,
            brand = leading.brand,
            size = density.avatarSize,
            isPick = leading.isPick,
            imageUrl = leading.imageUrl,
            entityId = leading.entityId
        )
        is ImasRowLeading.Artwork -> ImasArtwork(
            title = leading.title,
            seed = leading.seed,
            brand = leading.brand,
            size = density.artworkSize,
            imageUrl = leading.imageUrl,
            isCollected = leading.isCollected
        )
        is ImasRowLeading.Icon -> ImasIconTile(
            leading.icon,
            size = ImasIconTileSize.S28,
            tone = leading.tone,
            seed = leading.seed,
            brand = leading.brand
        )
        is ImasRowLeading.Number -> Text(
            leading.text,
            style = ImasNumeralSize.SMALL.style,
            color = DS.ink3,
            textAlign = TextAlign.End,
            maxLines = 1,
            modifier = modifier.width(30.dp)
        )
        is ImasRowLeading.NumberedArtwork -> Row(
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.Top
        ) {
            Text(
                leading.number,
                style = ImasType.mono(11.5.sp, FontWeight.Bold),
                color = DS.ink2,
                textAlign = TextAlign.End,
                maxLines = 1,
                modifier = Modifier
                    .width(24.dp)
                    .padding(top = 2.dp)
            )
            ImasArtwork(
                title = leading.title,
                seed = leading.seed,
                brand = leading.brand,
                size = 44.dp,
                imageUrl = leading.imageUrl,
                isCollected = leading.isCollected
            )
        }
        is ImasRowLeading.Rank -> ImasRankNumber(leading.rank, modifier = modifier)
        is ImasRowLeading.Selection -> ImasSelectionMark(isSelected = leading.isOn, isSingle = leading.single)
        is ImasRowLeading.Custom -> Box(Modifier.width(leading.width)) { leading.content() }
    }
}

@Composable
private fun ImasRowTrailingView(trailing: ImasRowTrailing) {
    when (trailing) {
        ImasRowTrailing.None -> Unit
        ImasRowTrailing.Chevron -> ImasRowChevron()
        is ImasRowTrailing.Value -> Text(
            trailing.text,
            style = ImasTextRole.VALUE.style,
            color = DS.ink2,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis
        )
        is ImasRowTrailing.Metric -> ImasMetric(
            trailing.value,
            unit = trailing.unit,
            size = ImasNumeralSize.MEDIUM,
            emphasized = trailing.emphasized
        )
        is ImasRowTrailing.Badge -> ImasBadge(trailing.text, kind = trailing.kind, icon = trailing.icon, seed = trailing.seed)
        is ImasRowTrailing.Toggle -> ImasSwitch(checked = trailing.isOn, onCheckedChange = trailing.onChange)
        is ImasRowTrailing.Mark -> ImasMarkButton(trailing.kind, trailing.isOn, onClick = trailing.onClick)
        is ImasRowTrailing.Custom -> trailing.content()
    }
}

// MARK: - 長押しでコピー

/**
 * 長押しでコピー (+ 押して進む) できる行の包み (iOS の行に `.imasCopyable` を付けた形)。
 * 押している間は面が沈む (波紋は出さない)。コピーする物が無ければ長押しは付けない。
 */
@Composable
internal fun ImasCopyableRow(
    items: List<CopyItem>,
    modifier: Modifier,
    onClick: (() -> Unit)?,
    content: @Composable () -> Unit
) {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    Copyable(
        items = items,
        modifier = modifier.background(if (pressed && onClick != null) DS.fill else Color.Transparent),
        onClick = onClick,
        interactionSource = source,
        indication = null,
        content = content
    )
}

// MARK: - 行の中の小物

/** 一覧行の末尾の「>」(iOS `ImasRowChevron`)。カードの中の行で別画面へ行くときだけ出す。 */
@Composable
fun ImasRowChevron(modifier: Modifier = Modifier, tint: Color = DS.ink3) {
    val s = with(LocalDensity.current) { 16.sp.toDp() }
    Icon(
        Icons.AutoMirrored.Filled.KeyboardArrowRight,
        contentDescription = null,
        tint = tint,
        modifier = modifier
            .size(s)
            .clearAndSetSemantics { }
    )
}

/** 順位の数字の幅。 */
val ImasRankNumberWidth: Dp = 28.dp

/** 順位の数字 (iOS `ImasRankNumber`)。1〜3 位は墨、それ以外は薄灰 (色で順位を飾らない)。 */
@Composable
fun ImasRankNumber(rank: Int, modifier: Modifier = Modifier) {
    Text(
        "$rank",
        style = ImasType.numeral(20.sp, FontWeight.ExtraBold),
        color = if (rank <= 3) DS.ink else DS.ink3,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = modifier
            .width(ImasRankNumberWidth)
            .semantics { contentDescription = "${rank}位" }
    )
}

/**
 * オン・オフのスイッチ (iOS の OS の `Toggle` + `.tint(DS.switchOn)`)。
 * つまみは OS のスイッチと同じ白、ON の地は `DS.switchOn` (ダークでも白に沈まない濃さ)。
 *
 * @param onCheckedChange null なら押せない見た目だけのスイッチ (行全体で切り替えるときに使う)。
 */
@Composable
fun ImasSwitch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier: Modifier = Modifier) {
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        modifier = modifier,
        colors = SwitchDefaults.colors(
            checkedThumbColor = Color.White,
            checkedTrackColor = DS.switchOn,
            checkedBorderColor = DS.switchOn,
            uncheckedThumbColor = Color.White,
            uncheckedTrackColor = DS.fill,
            uncheckedBorderColor = DS.line
        )
    )
}

// MARK: - 項目と値の行

/**
 * 「項目: 値」の行 (iOS `ImasValueRow`。よみ・CV・会場・キャパ・価格)。長押しで値をコピーできる。
 *
 * @param isLink 値が押せる (別画面へ行く・外へ飛ぶ) とき。矢印を出す (値の色は変えない)。行き先は [onClick]。
 * @param expandable 長い値を開閉できるようにする (省略されているときだけ開閉が出る)。
 * @param monospaced 数字を等幅にする。
 */
@Composable
fun ImasValueRow(
    key: String,
    value: String,
    modifier: Modifier = Modifier,
    isLink: Boolean = false,
    expandable: Boolean = false,
    monospaced: Boolean = false,
    copyable: Boolean = true,
    position: ImasRowPosition? = null,
    onClick: (() -> Unit)? = null
) {
    var expanded by rememberSaveable(key, value) { mutableStateOf(false) }
    var truncated by remember(key, value) { mutableStateOf(false) }
    val showsToggle = expandable && (truncated || expanded)
    val valueStyle = if (monospaced) ImasTextRole.VALUE.style.copy(fontFeatureSettings = "tnum") else ImasTextRole.VALUE.style
    val row: @Composable () -> Unit = {
        Row(
            Modifier
                .fillMaxWidth()
                .imasRowTopDivider(DS.Space.rowH, position ?: LocalImasRowPosition.current)
                .heightIn(min = DS.Size.touch)
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowV),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap)
        ) {
            Text(
                key,
                style = ImasTextRole.VALUE.style,
                color = DS.ink2,
                maxLines = 1,
                modifier = Modifier.alignByBaseline()
            )
            Text(
                value,
                style = valueStyle,
                color = DS.ink,
                maxLines = if (expandable && expanded) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.End,
                onTextLayout = { if (expandable && !expanded) truncated = it.hasVisualOverflow },
                modifier = Modifier
                    .weight(1f)
                    .alignByBaseline()
            )
            if (isLink) {
                ImasRowChevron(Modifier.align(Alignment.CenterVertically))
            } else if (showsToggle) {
                val turn by animateFloatAsState(if (expanded) 180f else 0f, ImasMotion.standard(), label = "valueRowToggle")
                Icon(
                    Icons.Filled.KeyboardArrowDown,
                    contentDescription = null,
                    tint = DS.ink3,
                    modifier = Modifier
                        .align(Alignment.CenterVertically)
                        .size(with(LocalDensity.current) { 14.sp.toDp() })
                        .rotate(turn)
                )
            }
        }
    }
    val tap: (() -> Unit)? = when {
        showsToggle -> ({ expanded = !expanded })
        else -> onClick
    }
    // 省略されている値も原文 (value) を渡すので、全文がコピーできる。
    ImasCopyableRow(
        items = if (copyable) listOf(CopyItem("${key}をコピー", value)) else emptyList(),
        modifier = modifier.fillMaxWidth(),
        onClick = tap,
        content = row
    )
}

// MARK: - 入口・設定の行

/**
 * 別の画面へ進む入口の行 (iOS `ImasNavRow`。設定・マイページ・ハブの一覧)。押すと進むので末尾は矢印。
 *
 * @param iconTone 記号の色 (既定は墨)。seed / brand を渡すと記号を実体の色で点ける (混在ブランドの一覧など)。
 * @param value 矢印の前に添える今の値 (「すべて」)。
 * @param isLoading 押してから外へ飛ぶまでの待ち。矢印をくるくるに替える。
 * @param showsChevron 矢印を描くか (既定は出す)。
 * @param onClick 押したとき (iOS は NavigationLink で包む。Compose は行が押せる口を持つ)。
 */
@Composable
fun ImasNavRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    iconTone: ImasIconTileTone = ImasIconTileTone.SOLID,
    seed: String? = null,
    brand: String? = null,
    value: String? = null,
    isLoading: Boolean = false,
    showsChevron: Boolean = true,
    subtitleLineLimit: Int = 1,
    titleLineLimit: Int = 1,
    position: ImasRowPosition? = null,
    onClick: (() -> Unit)? = null
) {
    ImasRow(
        title = title,
        modifier = modifier.then(if (onClick != null) Modifier.imasRowPress(onClick = onClick) else Modifier),
        subtitle = subtitle,
        leading = icon?.let { ImasRowLeading.Icon(it, tone = iconTone, seed = seed, brand = brand) } ?: ImasRowLeading.None,
        trailing = ImasRowTrailing.Custom {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                if (value != null) {
                    Text(
                        value,
                        style = ImasTextRole.VALUE.style,
                        color = DS.ink2,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.widthIn(max = 180.dp)
                    )
                }
                if (isLoading) {
                    CircularProgressIndicator(Modifier.size(16.dp), color = DS.ink3, strokeWidth = 2.dp)
                } else if (showsChevron) {
                    ImasRowChevron()
                }
            }
        },
        density = ImasRowDensity.COMPACT,
        titleLineLimit = titleLineLimit,
        subtitleLineLimit = subtitleLineLimit,
        titleRole = ImasTextRole.ROW_LABEL,
        position = position
    )
}

/**
 * 設定のオンオフ (iOS `ImasToggleRow`)。行のどこを押しても切り替わる (Android の設定の行と同じ)。
 */
@Composable
fun ImasToggleRow(
    title: String,
    isOn: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    position: ImasRowPosition? = null
) {
    val haptics = rememberImasHaptics()
    ImasRow(
        title = title,
        modifier = modifier.toggleable(value = isOn, role = Role.Switch) {
            haptics.selection()
            onCheckedChange(it)
        },
        subtitle = subtitle,
        leading = icon?.let { ImasRowLeading.Icon(it, tone = ImasIconTileTone.NEUTRAL) } ?: ImasRowLeading.None,
        trailing = ImasRowTrailing.Custom { ImasSwitch(checked = isOn, onCheckedChange = null) },
        density = ImasRowDensity.COMPACT,
        titleRole = ImasTextRole.ROW_LABEL,
        position = position
    )
}

/**
 * 選べる行 (iOS `ImasSelectableRow`。ピッカー・複数選択)。行のどこを押しても切り替わる。
 * 複数選択は ○ と ✓、1 つ選択 ([isSingle]) は選んだ行にだけ ✓。先頭 (ジャケ・アイコン) と並べられる。
 */
@Composable
fun ImasSelectableRow(
    title: String,
    isSelected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leading: ImasRowLeading = ImasRowLeading.None,
    trailing: ImasRowTrailing = ImasRowTrailing.None,
    isSingle: Boolean = false,
    seed: String? = null,
    brand: String? = null,
    isDisabled: Boolean = false,
    position: ImasRowPosition? = null
) {
    val haptics = rememberImasHaptics()
    ImasRow(
        title = title,
        modifier = modifier
            .imasRowPress(enabled = !isDisabled) {
                haptics.selection()
                onClick()
            }
            .semantics { selected = isSelected },
        subtitle = subtitle,
        leading = leading,
        selection = ImasRowSelection(isOn = isSelected, single = isSingle, seed = seed, brand = brand),
        trailing = trailing,
        density = ImasRowDensity.COMPACT,
        emphasis = if (isDisabled) ImasRowEmphasis.DIMMED else ImasRowEmphasis.NORMAL,
        position = position
    )
}

/**
 * 値を 1 つ選ぶ設定の行 (iOS `ImasMenuRow`)。押すとその場に選択肢のメニューが出る (画面を移らない)。
 */
@Composable
fun <T> ImasMenuRow(
    title: String,
    options: List<T>,
    selection: T,
    onSelect: (T) -> Unit,
    label: (T) -> String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    position: ImasRowPosition? = null
) {
    var open by remember { mutableStateOf(false) }
    val haptics = rememberImasHaptics()
    Box(modifier) {
        ImasRow(
            title = title,
            modifier = Modifier.imasRowPress { open = true },
            subtitle = subtitle,
            leading = icon?.let { ImasRowLeading.Icon(it, tone = ImasIconTileTone.NEUTRAL) } ?: ImasRowLeading.None,
            trailing = ImasRowTrailing.Custom {
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
                    Text(label(selection), style = ImasTextRole.VALUE.style, color = DS.ink2, maxLines = 1)
                    Icon(
                        Icons.Filled.UnfoldMore,
                        contentDescription = null,
                        tint = DS.ink3,
                        modifier = Modifier.size(with(LocalDensity.current) { 14.sp.toDp() })
                    )
                }
            },
            density = ImasRowDensity.COMPACT,
            titleLineLimit = 1,
            titleRole = ImasTextRole.ROW_LABEL,
            position = position
        )
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, modifier = Modifier.align(Alignment.TopEnd)) {
            options.forEach { option ->
                DropdownMenuItem(
                    text = { Text(label(option), color = DS.ink) },
                    trailingIcon = if (option == selection) {
                        { Icon(Icons.Filled.Check, contentDescription = null, tint = DS.ink) }
                    } else null,
                    onClick = {
                        open = false
                        if (option != selection) {
                            haptics.selection()
                            onSelect(option)
                        }
                    }
                )
            }
        }
    }
}

/**
 * 数を 1 つずつ増減する設定の行 (iOS `ImasStepperRow`。問題数・人数)。
 * iOS の OS の Stepper (− | + の溝) を同じ形で描く。
 */
@Composable
fun ImasStepperRow(
    title: String,
    value: Int,
    onValueChange: (Int) -> Unit,
    range: IntRange,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    icon: ImageVector? = null,
    step: Int = 1,
    unit: String? = null,
    position: ImasRowPosition? = null
) {
    val haptics = rememberImasHaptics()
    fun change(next: Int) {
        val clamped = next.coerceIn(range.first, range.last)
        if (clamped != value) {
            haptics.selection()
            onValueChange(clamped)
        }
    }
    ImasRow(
        title = title,
        modifier = modifier,
        subtitle = subtitle,
        leading = icon?.let { ImasRowLeading.Icon(it, tone = ImasIconTileTone.NEUTRAL) } ?: ImasRowLeading.None,
        trailing = ImasRowTrailing.Custom {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gap), verticalAlignment = Alignment.CenterVertically) {
                ImasMetric("$value", unit = unit, size = ImasNumeralSize.MEDIUM, emphasized = true)
                Row(
                    Modifier.background(DS.fill, RoundedCornerShape(DS.rControl(DS.Size.chip))),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    StepperHalf(Icons.Filled.Remove, "$title を減らす", enabled = value > range.first) { change(value - step) }
                    Box(Modifier.width(1.dp).height(18.dp).background(DS.line))
                    StepperHalf(Icons.Filled.Add, "$title を増やす", enabled = value < range.last) { change(value + step) }
                }
            }
        },
        density = ImasRowDensity.COMPACT,
        titleLineLimit = 1,
        titleRole = ImasTextRole.ROW_LABEL,
        position = position
    )
}

@Composable
private fun StepperHalf(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier
            .size(width = 44.dp, height = DS.Size.chip)
            .clickable(enabled = enabled, role = Role.Button, onClickLabel = label, onClick = onClick)
            .semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        Icon(icon, contentDescription = null, tint = if (enabled) DS.ink else DS.ink3, modifier = Modifier.size(18.dp))
    }
}

/** 行の形のボタンの種類 (iOS `ImasActionRow.Kind`)。 */
enum class ImasActionRowKind {
    /** 「＋ 曲を追加」など。 */
    STANDARD,

    /** 「このライブを削除」など。文字は朱 (`DS.danger`)。 */
    DESTRUCTIVE
}

/** 行の形のボタン (iOS `ImasActionRow`。「＋ 曲を追加」「このライブを削除」)。 */
@Composable
fun ImasActionRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    kind: ImasActionRowKind = ImasActionRowKind.STANDARD,
    position: ImasRowPosition? = null
) {
    val color = if (kind == ImasActionRowKind.DESTRUCTIVE) DS.danger else DS.ink
    Row(
        modifier
            .fillMaxWidth()
            .imasRowTopDivider(DS.Space.rowH, position ?: LocalImasRowPosition.current)
            .imasRowPress(onClick = onClick)
            .heightIn(min = DS.Size.touch)
            .padding(horizontal = DS.Space.rowH),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(with(LocalDensity.current) { 18.sp.toDp() }))
        }
        Text(title, style = ImasTextRole.ROW_LABEL.style, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Spacer(Modifier.weight(1f))
    }
}

// MARK: - 印のボタン

/** 行や頭で付け外しする印の種類 (iOS `ImasMarkKind`)。記号と読み上げを決める。 */
enum class ImasMarkKind {
    /** 担当 (♥)。 */
    PICK,

    /** お気に入り (★)。 */
    FAVORITE,

    /** 所有 (カードゲームの収録カードなど)。 */
    OWNED;

    /** 記号。 */
    fun icon(isOn: Boolean): ImageVector = when (this) {
        PICK -> if (isOn) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder
        FAVORITE -> if (isOn) Icons.Filled.Star else Icons.Filled.StarBorder
        OWNED -> if (isOn) Icons.Filled.Inventory2 else Icons.Outlined.Inventory2
    }

    /** 読み上げ (押したら何が起きるか)。 */
    fun accessibilityLabel(isOn: Boolean): String = when (this) {
        PICK -> if (isOn) "担当から外す" else "担当にする"
        FAVORITE -> if (isOn) "お気に入りから外す" else "お気に入りにする"
        OWNED -> if (isOn) "所有から外す" else "所有を記録"
    }
}

/**
 * 印 (担当・お気に入り) をその場で付け外しする記号のボタン (iOS `ImasMarkButton`)。押せる所は 44。
 * ON は実体の色で点き (無ければ担当は担当の色・所有は墨)、OFF は薄い墨の線の記号。押すと手応えを返す。
 */
@Composable
fun ImasMarkButton(
    kind: ImasMarkKind,
    isOn: Boolean,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null,
    onClick: () -> Unit
) {
    val t = ImasChipColors.theme(seed, brand, null)
    val onColor = when (kind) {
        ImasMarkKind.PICK -> if (t.isNeutral) DS.pick else t.penlight
        ImasMarkKind.FAVORITE -> DS.favorite
        ImasMarkKind.OWNED -> if (t.isNeutral) DS.ink else t.accent
    }
    val haptics = rememberImasHaptics()
    // 付けた瞬間に弾む (iOS `.symbolEffect(.bounce)`)。
    val bounce = remember { Animatable(1f) }
    var first by remember { mutableStateOf(true) }
    LaunchedEffect(isOn) {
        if (first) {
            first = false
        } else {
            bounce.snapTo(1.25f)
            bounce.animateTo(1f, ImasMotion.standard())
        }
    }
    Box(
        modifier
            .size(DS.Size.touch)
            .clickable(role = Role.Button, onClickLabel = kind.accessibilityLabel(isOn)) {
                haptics.impactLight()
                onClick()
            }
            .clearAndSetSemantics { contentDescription = kind.accessibilityLabel(isOn) },
        contentAlignment = Alignment.Center
    ) {
        Icon(
            kind.icon(isOn),
            contentDescription = null,
            tint = if (isOn) onColor else DS.ink3,
            modifier = Modifier
                .size(with(LocalDensity.current) { 20.sp.toDp() })
                .scale(bounce.value)
        )
    }
}
