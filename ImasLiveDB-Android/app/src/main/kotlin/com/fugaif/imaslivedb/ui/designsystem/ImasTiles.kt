package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasThemeProvider
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasEnvTheme
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight
import uniffi.imas_core.progressPercent

// =============================================================================
// カード・数・メーター・入口 (docs/DESIGN_SYSTEM.md §6.3〜§6.5・§10.4)。iOS `ImasTiles.swift` の移植。
//
// ImasFeatureCard   ハブの最上段で「いま一番大事なもの」を 1 枚で。題は大きく、操作は下に行で並べる。
// ImasEntryCard     奥の画面への入口を大きく見せる。
// ImasStatTile      数 1 つ (記号 + 細長い太字の数 + 名前)。`ImasStatGrid` が 1 枚の面に並べる。
// ImasStatBar       項目ごとの割合の横棒。
// ImasProgressRing  1 つの割合を大きく。
// ImasShortcutGroup 種類ごとの入口の行のまとまり (あそぶ・みんな・しらべる)。
// ImasCarousel      カードを横に流す。
//
// どれも色の地を敷かない。面は `DS.surface` で、実体の色はペンライトと記号にだけ出す。
// 記号は淡い色の四角に入れない (v1 の「よくある見た目」の元)。
// =============================================================================

// MARK: - 主役のカード

/** 主役のカードの面 (iOS `ImasFeatureSurface`)。 */
enum class ImasFeatureSurface {
    /** 地の上の面。 */
    PANEL,

    /** 実体の色を面いっぱいに塗る (担当)。文字は色の上で読める白か黒。 */
    COLOR
}

/** 主役のカードの右上の数 (「あと 37 日」)。 */
@Immutable
data class ImasFeatureMetric(val value: String, val prefix: String? = null, val unit: String? = null)

/** 主役のカードの下の操作の行 1 つ。 */
@Immutable
data class ImasFeatureAction(val title: String, val icon: ImageVector? = null, val onClick: () -> Unit)

/**
 * ハブの最上段で「いま一番大事なもの」を 1 枚で見せる (iOS `ImasFeatureCard`。担当・次のライブ・開催中のお題)。
 *
 * 構成は [ペンライト + 目印 ……… 右上の数] / [画像] [題 (19 太字) / 副題] / [操作の行 …]。
 * 操作は塗りのボタンを 2 つ並べず、行 (文言 + 矢印) で下に重ねる。行き先が 1 つなら操作の行を置かず、
 * 頭全体を押せるようにする ([onOpen])。
 *
 * @param eyebrowPenlight 目印の前にペンライトを付けるか。実体に紐づかない一般の見出し (「BATTLE MODE」等) は false。
 * @param seed 実体の色 hex。[brand] はブランド ID。どちらも無ければニュートラル (環境の色は引き継がない)。
 * @param media 題の左の画像 (アイコン・ジャケ)。
 */
@Composable
fun ImasFeatureCard(
    title: String,
    modifier: Modifier = Modifier,
    eyebrow: String? = null,
    eyebrowPenlight: Boolean = true,
    subtitle: String? = null,
    seed: String? = null,
    brand: String? = null,
    metric: ImasFeatureMetric? = null,
    surface: ImasFeatureSurface = ImasFeatureSurface.PANEL,
    onOpen: (() -> Unit)? = null,
    primary: ImasFeatureAction? = null,
    secondary: ImasFeatureAction? = null,
    media: (@Composable () -> Unit)? = null
) {
    ImasThemeProvider(seed = seed, brand = brand) {
        val theme = imasEnvTheme
        val onColor = surface == ImasFeatureSurface.COLOR && !theme.isNeutral
        val fill = if (onColor) theme.accent else DS.surface
        val ink = if (onColor) theme.onAccent else DS.ink
        val ink2 = if (onColor) theme.onAccent.copy(alpha = 0.78f) else DS.ink2
        val rule = if (onColor) theme.onAccent.copy(alpha = 0.22f) else DS.sep
        val pressed = if (onColor) theme.onAccent.copy(alpha = 0.1f) else DS.fill
        val shape = RoundedCornerShape(DS.rCard)
        Column(
            modifier
                .fillMaxWidth()
                .clip(shape)
                .background(fill, shape)
        ) {
            val headModifier = if (onOpen != null) Modifier.featurePress(pressed, onOpen) else Modifier
            Column(
                headModifier
                    .fillMaxWidth()
                    .padding(DS.Space.card),
                verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
            ) {
                if (eyebrow != null || metric != null) {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                        if (eyebrow != null) {
                            Row(
                                Modifier
                                    .weight(1f, fill = false)
                                    .alignByBaseline(),
                                horizontalArrangement = Arrangement.spacedBy(7.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                if (eyebrowPenlight) {
                                    ImasPenlight(color = if (onColor) theme.onAccent else theme.penlight, size = ImasPenlightSize.REGULAR)
                                }
                                Text(eyebrow, style = ImasTextRole.EYEBROW.style, color = ink2, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                        Spacer(Modifier.weight(1f))
                        if (metric != null) {
                            Row(
                                Modifier
                                    .alignByBaseline()
                                    .semantics(mergeDescendants = true) { },
                                horizontalArrangement = Arrangement.spacedBy(3.dp)
                            ) {
                                val unitStyle = ImasType.text(13.sp, FontWeight.SemiBold)
                                if (metric.prefix != null) {
                                    Text(metric.prefix, style = unitStyle, color = ink2, modifier = Modifier.alignByBaseline())
                                }
                                if (metric.value.isNotEmpty()) {
                                    Text(metric.value, style = ImasNumeralSize.LARGE.style, color = ink, maxLines = 1, modifier = Modifier.alignByBaseline())
                                }
                                if (metric.unit != null) {
                                    Text(metric.unit, style = unitStyle, color = ink2, modifier = Modifier.alignByBaseline())
                                }
                            }
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.card), verticalAlignment = Alignment.CenterVertically) {
                    media?.invoke()
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        Text(title, style = ImasTextRole.CARD_TITLE.style, color = ink, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        if (subtitle != null) {
                            Text(subtitle, style = ImasType.text(15.sp), color = ink2, maxLines = 2, overflow = TextOverflow.Ellipsis)
                        }
                    }
                    if (onOpen != null) ImasRowChevron(tint = ink2)
                }
            }
            listOfNotNull(primary, secondary).forEach { action ->
                Box(
                    Modifier
                        .padding(start = DS.Space.card)
                        .fillMaxWidth()
                        .height(0.5.dp)
                        .background(rule)
                )
                Row(
                    Modifier
                        .fillMaxWidth()
                        .featurePress(pressed, action.onClick)
                        .heightIn(min = 50.dp)
                        .padding(horizontal = DS.Space.card),
                    horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    if (action.icon != null) {
                        Icon(action.icon, contentDescription = null, tint = ink, modifier = Modifier.size(with(LocalDensity.current) { 17.sp.toDp() }))
                    }
                    Text(
                        action.title,
                        style = ImasType.heading(16.sp, FontWeight.SemiBold),
                        color = ink,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    ImasRowChevron(tint = ink2)
                }
            }
        }
    }
}

/** 主役のカードの中の押せる所。押すと面が少し沈む (縮めない: カードの中の一部なので)。 */
@Composable
private fun Modifier.featurePress(pressedFill: Color, onClick: () -> Unit): Modifier {
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    return this
        .background(if (pressed) pressedFill else Color.Transparent)
        .clickable(interactionSource = source, indication = null, role = Role.Button, onClick = onClick)
}

// MARK: - 入口のカード

/**
 * 奥の画面への入口を大きく見せる (iOS `ImasEntryCard`)。一覧で十分なら [ImasNavRow]。
 *
 * @param isLoading 押してから外へ飛ぶまでの待ち。矢印をくるくるに替える。
 */
@Composable
fun ImasEntryCard(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
    preview: String? = null,
    seed: String? = null,
    brand: String? = null,
    isLoading: Boolean = false,
    onClick: (() -> Unit)? = null
) {
    val shape = RoundedCornerShape(DS.rCard)
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.imasPress(onClick = onClick) else Modifier.semantics(mergeDescendants = true) { })
            .background(DS.surface, shape)
            .padding(DS.Space.card),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasIconTile(icon, size = ImasIconTileSize.S32, tone = ImasIconTileTone.SOLID, seed = seed, brand = brand)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, style = ImasTextRole.CARD_TITLE.style, color = ImasTextRole.CARD_TITLE.color)
            if (preview != null) {
                Text(preview, style = ImasTextRole.NOTE.style, color = ImasTextRole.NOTE.color, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        if (isLoading) {
            CircularProgressIndicator(Modifier.size(16.dp), color = DS.ink3, strokeWidth = 2.dp)
        } else {
            ImasRowChevron()
        }
    }
}

// MARK: - 数

/** [ImasStatGrid] の中にいる (数が自分の面を持たない)。 */
val LocalImasInStatGrid = staticCompositionLocalOf { false }

/**
 * 数 1 つ (iOS `ImasStatTile`)。上に記号 (実体の色、地なし)、その下に細長い太字の数と名前。
 * 奥へ行けるとき ([tappable]) は右上に小さい矢印。[ImasStatGrid] の中では面を持たず、外に単独で置くと自分で面を持つ。
 *
 * 引数の前 3 つ (記号・数・名前) は Android の今の呼び出しの並び。
 *
 * @param seed 記号の色 hex。[brand] はブランド ID。どちらも無ければ環境の実体の色 (無ければ墨)。
 * @param onClick 押したとき (奥の一覧へ)。渡すと [tappable] の矢印も出す。
 */
@Composable
fun ImasStatTile(
    icon: ImageVector?,
    value: String,
    label: String,
    unit: String? = null,
    seed: String? = null,
    brand: String? = null,
    tappable: Boolean = false,
    onClick: (() -> Unit)? = null,
    modifier: Modifier = Modifier
) {
    val t = ImasChipColors.theme(seed, brand, null)
    val inGrid = LocalImasInStatGrid.current
    val showsArrow = tappable || onClick != null
    Column(
        modifier
            .then(if (onClick != null) Modifier.imasPress(onClick = onClick) else Modifier.semantics(mergeDescendants = true) { })
            .then(if (!inGrid) Modifier.background(DS.surface, RoundedCornerShape(DS.rCard)) else Modifier)
            .padding(horizontal = if (inGrid) DS.Space.gapLoose else DS.Space.card, vertical = DS.Space.gapLoose),
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        if (icon != null || showsArrow) {
            Row(Modifier.fillMaxWidth().padding(bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                if (icon != null) {
                    Icon(
                        icon,
                        contentDescription = null,
                        tint = t.penlight,
                        modifier = Modifier.size(with(LocalDensity.current) { 18.sp.toDp() })
                    )
                }
                Spacer(Modifier.weight(1f))
                if (showsArrow) {
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = DS.ink3,
                        modifier = Modifier.size(with(LocalDensity.current) { 13.sp.toDp() })
                    )
                }
            }
        }
        // 金額のように桁が伸びる値でも折り返さない (タイルの高さが揃わなくなる)。
        ImasMetric(value, unit = unit, size = ImasNumeralSize.LARGE)
        ImasFitText(label, style = ImasType.text(12.sp, FontWeight.SemiBold), color = DS.ink2, minScale = 0.8f)
    }
}

/**
 * 数を 1 枚の面に格子で並べる (iOS `ImasStatGrid`。記録・統計)。列は 2〜4。
 * 中の数は面を持たない ([LocalImasInStatGrid])。行の高さはその行でいちばん高い数に揃える。
 */
@Composable
fun ImasStatGrid(modifier: Modifier = Modifier, columns: Int = 2, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalImasInStatGrid provides true) {
        Layout(
            content = content,
            modifier = modifier
                .fillMaxWidth()
                .background(DS.surface, RoundedCornerShape(DS.rCard))
                .padding(DS.Space.gapTight)
        ) { measurables, constraints ->
            val cols = columns.coerceAtLeast(1)
            val width = constraints.maxWidth
            val cellWidth = width / cols
            val placeables = measurables.map { it.measure(Constraints.fixedWidth(cellWidth)) }
            val rows = placeables.chunked(cols)
            val rowHeights = rows.map { row -> row.maxOf { it.height } }
            layout(width, rowHeights.sum()) {
                var y = 0
                rows.forEachIndexed { r, row ->
                    row.forEachIndexed { c, p -> p.placeRelative(c * cellWidth, y) }
                    y += rowHeights[r]
                }
            }
        }
    }
}

// MARK: - 割合の横棒

/**
 * 項目ごとの割合 (iOS `ImasStatBar`。ブランド別の回収率など)。前にペンライト、細い四角の棒、右に細長い数。
 *
 * @param percent 0〜100。
 * @param valueWidth 右端の値の幅。金額のように桁が伸びる値は広げる。
 * @param contentPadding 行の余白。既定は Android の今の呼び出し (画面いっぱいに置く) の左右 16・上下 8。
 *   カードの中では左右 0 を渡す (iOS は上下 8 だけ)。
 */
@Composable
fun ImasStatBar(
    label: String,
    value: String,
    percent: Double,
    seed: String? = null,
    brand: String? = null,
    valueWidth: Dp = 52.dp,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(horizontal = DS.Space.screen, vertical = DS.Space.gap)
) {
    val t = imasThemeForBrand(seed, brand)
    val fraction = (percent / 100.0).coerceIn(0.0, 1.0).toFloat()
    Row(
        modifier
            .fillMaxWidth()
            .padding(contentPadding)
            .semantics(mergeDescendants = true) { },
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier.width(92.dp),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ImasPenlight(color = t.penlight, size = ImasPenlightSize.SMALL)
            Text(label, style = ImasType.text(13.sp), color = DS.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(
            Modifier
                .weight(1f)
                .height(6.dp)
                .background(DS.fill)
        ) {
            Box(
                Modifier
                    .fillMaxHeight()
                    .fillMaxWidth(fraction)
                    .background(t.bar)
            )
        }
        Box(Modifier.width(valueWidth), contentAlignment = Alignment.CenterEnd) {
            ImasFitText(value, style = ImasNumeralSize.SMALL.style, color = DS.ink2, minScale = 0.7f)
        }
    }
}

// MARK: - 割合の輪

/**
 * 1 つの割合を大きく見せる輪 (iOS `ImasProgressRing`。回収率・習熟度)。中央に % を出す。
 *
 * @param fraction 0〜1。
 */
@Composable
fun ImasProgressRing(
    fraction: Double,
    modifier: Modifier = Modifier,
    size: Dp = 92.dp,
    lineWidth: Dp = 8.dp,
    seed: String? = null,
    brand: String? = null
) {
    val t = ImasChipColors.theme(seed, brand, null)
    val clamped = fraction.coerceIn(0.0, 1.0)
    // % は切り捨て (100% は全部終わったときだけ)。規則はコア (`progress_percent`)。
    val pct = progressPercent(clamped).toInt()
    val track = DS.fill
    val bar = if (t.isNeutral) DS.ink else t.bar
    val fontSize = with(LocalDensity.current) { (size * 0.26f).toSp() }
    Box(
        modifier
            .size(size)
            .clearAndSetSemantics { contentDescription = "${pct}パーセント" },
        contentAlignment = Alignment.Center
    ) {
        Canvas(Modifier.size(size)) {
            val w = lineWidth.toPx()
            val inset = w / 2
            val arcSize = Size(this.size.width - w, this.size.height - w)
            drawArc(track, 0f, 360f, useCenter = false, topLeft = Offset(inset, inset), size = arcSize, style = Stroke(w))
            drawArc(
                bar,
                -90f,
                (clamped * 360).toFloat(),
                useCenter = false,
                topLeft = Offset(inset, inset),
                size = arcSize,
                style = Stroke(w, cap = StrokeCap.Butt)
            )
        }
        Text("$pct%", style = ImasType.numeral(fontSize, FontWeight.ExtraBold), color = DS.ink, maxLines = 1)
    }
}

// MARK: - 入口のまとまり

/**
 * 種類ごとの入口を見出し + 行のまとまりで見せる (iOS `ImasShortcutGroup`。あそぶ・みんな・しらべる)。
 * 中身は [ImasShortcutTile] (入口の行) を並べる。行の間の線は行が引き、1 行目の線はここで隠す。
 * 記号の格子 (アイコンを四角に入れて 4 列) にはしない。
 *
 * @param accessory 見出しの右に添えるもの (任意)。
 */
@Composable
fun ImasShortcutGroup(
    title: String,
    modifier: Modifier = Modifier,
    accessory: (@Composable RowScope.() -> Unit)? = null,
    items: @Composable ColumnScope.() -> Unit
) {
    val shape = RoundedCornerShape(DS.rCard)
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.header)) {
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                title,
                style = ImasTextRole.SECTION_TITLE.style,
                color = ImasTextRole.SECTION_TITLE.color,
                modifier = Modifier
                    .weight(1f)
                    .semantics { heading() }
            )
            accessory?.invoke(this)
        }
        Column(
            Modifier
                .fillMaxWidth()
                .background(DS.surface, shape)
                .clip(shape)
                // 各行は上に線を引く。1 行目の線 (面の上端) だけを隠す。
                .drawWithContent { clipRect(top = 1.5f) { this@drawWithContent.drawContent() } },
            content = items
        )
    }
}

/**
 * 入口の行 1 つ (iOS `ImasShortcutTile`。記号 + 名前 + 補足 + 矢印)。記号は実体の色 (無ければ墨)。
 * 押してから外へ飛ぶまでは くるくる ([isLoading])。
 *
 * @param detail 名前の下の補足 (「つづきから Q.02」「開催中 3 件」)。
 */
@Composable
fun ImasShortcutTile(
    icon: ImageVector,
    label: String,
    modifier: Modifier = Modifier,
    detail: String? = null,
    seed: String? = null,
    isLoading: Boolean = false,
    onClick: (() -> Unit)? = null
) {
    Row(
        modifier
            .fillMaxWidth()
            .imasRowTopDivider(DS.Space.rowH + ImasIconTileSize.S28.frame + DS.Space.rowGap, ImasRowPosition.FOLLOWING)
            .then(if (onClick != null) Modifier.imasRowPress(onClick = onClick) else Modifier)
            .heightIn(min = 50.dp)
            .padding(horizontal = DS.Space.rowH, vertical = DS.Space.rowVCompact),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasIconTile(icon, size = ImasIconTileSize.S28, tone = ImasIconTileTone.THEMED, seed = seed)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(label, style = ImasTextRole.ROW_LABEL.style, color = ImasTextRole.ROW_LABEL.color, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (detail != null) {
                Text(detail, style = ImasTextRole.ROW_SUBTITLE.style, color = ImasTextRole.ROW_SUBTITLE.color, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (isLoading) {
            CircularProgressIndicator(Modifier.size(16.dp), color = DS.ink3, strokeWidth = 2.dp)
        } else {
            ImasRowChevron()
        }
    }
}

// MARK: - 横に流す

/**
 * カードを横に流す (iOS `ImasCarousel`)。1 枚なら画面いっぱい、2 枚以上は次の 1 枚が少し見える幅にする
 * (幅 - 48)。払うとカードの頭で止まる。画面の余白の外まで流れる ([ImasPage] の中に置く)。
 */
@Composable
fun <T> ImasCarousel(
    items: List<T>,
    modifier: Modifier = Modifier,
    key: ((T) -> Any)? = null,
    card: @Composable (T) -> Unit
) {
    if (items.size <= 1) {
        Column(modifier.fillMaxWidth()) { items.forEach { card(it) } }
        return
    }
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val cardWidth = maxWidth - 48.dp
        val state = rememberLazyListState()
        LazyRow(
            state = state,
            flingBehavior = rememberSnapFlingBehavior(state),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
            contentPadding = PaddingValues(horizontal = DS.Space.screen),
            modifier = Modifier.imasBleed(DS.Space.screen)
        ) {
            items(items, key = key) { item ->
                Box(Modifier.width(cardWidth)) { card(item) }
            }
        }
    }
}
