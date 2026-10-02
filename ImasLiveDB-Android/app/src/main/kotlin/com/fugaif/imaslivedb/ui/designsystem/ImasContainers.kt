package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.key
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasBackdrop
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasBackdrop
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.imasThemeForBrand
import com.fugaif.imaslivedb.ui.theme.penlight

// =============================================================================
// 区画と面 (docs/DESIGN_SYSTEM.md §3・§4・§6.1・§6.2)。iOS `ImasContainers.swift` の移植。
//
// ImasSectionHeader  見出し。大 (詳細・ハブ) と小 (一覧・設定・フォーム・カードの中)。
// ImasSection        見出し + 中身 + 補足文。縦に並べる単位。
// ImasPage           区画を縦に並べる画面の本体 (地・左右の余白・区画どうしの間隔・本文幅)。
// ImasLazyPage       ImasPage の LazyColumn 版 (Android だけ。長い一覧を区画で組むとき)。
// ImasCard           行でない中身を 1 枚の面にまとめる。
// ImasCardList       行を並べる。紙面にそのまま並べる (PLAIN)、面に入れる (PANEL)、紙に入れて切り取り線 (SHEET)。
// ImasNote           補足文。囲まない。
// ImasRowDivider     行の間の線。行の部品が使う (画面では書かない)。
// ImasDateHeader     年・月の区切り (細長い大きな数字 + 印字)。
// imasSurfaceEdge    面の縁。ライトは紙が浮く薄い影、ダークは細い線。
// =============================================================================

// MARK: - 見出し

/** 見出しの大きさ (iOS `ImasSectionHeader.Style`)。1 画面の区画は大か小のどちらかに揃える。 */
enum class ImasSectionHeaderStyle {
    /** 20 太字・墨。詳細とハブの区画。 */
    LARGE,

    /** 13 中太・灰。一覧・設定・フォームの区画と、カードの中の小分け。 */
    SMALL
}

/**
 * 区画の見出し (iOS `ImasSectionHeader`)。
 *
 * 引数の前半 (title / count / tight / onSeeAll / modifier / seeAllTitle) は Android の今の呼び出しの形のまま。
 * `tight = true` は小 ([ImasSectionHeaderStyle.SMALL])。
 *
 * [contentPadding] の既定 (左右 16・上下 8) は今の呼び出し (画面の端に置く見出し) の余白。
 * 区画 ([ImasSection]) の中では区画が余白を決めるので 0 を渡す。
 *
 * @param imprint 見出しの横の英字の印字 (「PLAY」「42 SONGS」)。大きい見出しにだけ付ける。
 * @param seed 見出しの前のペンライトの色 hex (ブランドごと・アイドルごとの区切り)。[brand] はブランド ID。
 * @param actionTitle 見出しの右の、その場で何かを始める操作 (「＋ タグ」「▶ 動画」)。[onSeeAll] と同時には出さない。
 * @param titleLineLimit 見出しの行数。利用者が書いた題 (お題のタイトルなど) を見出しに流用するときは切らないよう増やす。
 */
@Composable
fun ImasSectionHeader(
    title: String,
    count: String? = null,
    tight: Boolean = false,
    onSeeAll: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
    seeAllTitle: String = "すべて見る",
    style: ImasSectionHeaderStyle = if (tight) ImasSectionHeaderStyle.SMALL else ImasSectionHeaderStyle.LARGE,
    imprint: String? = null,
    seed: String? = null,
    brand: String? = null,
    actionTitle: String? = null,
    actionIcon: ImageVector? = null,
    onAction: (() -> Unit)? = null,
    contentPadding: PaddingValues = PaddingValues(horizontal = DS.Space.screen, vertical = DS.Space.gap),
    titleLineLimit: Int = 2
) {
    val large = style == ImasSectionHeaderStyle.LARGE
    Row(
        modifier
            .fillMaxWidth()
            .padding(contentPadding),
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            Modifier
                .weight(1f)
                .semantics(mergeDescendants = true) { heading() },
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)
        ) {
            val role = if (large) ImasTextRole.SECTION_TITLE else ImasTextRole.SECTION_LABEL
            Text(
                title,
                style = role.style,
                color = role.color,
                maxLines = titleLineLimit,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .alignByBaseline()
                    .weight(1f, fill = false)
            )
            if (count != null) {
                Text(
                    count,
                    style = if (large) ImasNumeralSize.SMALL.style else ImasType.text(12.sp),
                    color = DS.ink3,
                    maxLines = 1,
                    modifier = Modifier.alignByBaseline()
                )
            }
            if (imprint != null && large) {
                Text(
                    imprint,
                    style = ImasTextRole.IMPRINT.style,
                    color = DS.ink3,
                    maxLines = 1,
                    modifier = Modifier.alignByBaseline()
                )
            }
        }
        if (onSeeAll != null) {
            Row(
                Modifier.clickable(onClick = onSeeAll),
                horizontalArrangement = Arrangement.spacedBy(2.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(seeAllTitle, style = ImasType.text(15.sp), color = DS.ink2, maxLines = 1)
                Icon(
                    Icons.AutoMirrored.Filled.KeyboardArrowRight,
                    contentDescription = null,
                    tint = DS.ink2,
                    modifier = Modifier.size(with(LocalDensity.current) { 15.sp.toDp() })
                )
            }
        } else if (actionTitle != null && onAction != null) {
            val t = ImasChipColors.theme(seed, brand, null)
            val tint = if (t.isNeutral) DS.ink else t.accent
            Row(
                Modifier.clickable(onClick = onAction),
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
                verticalAlignment = Alignment.CenterVertically
            ) {
                if (actionIcon != null) {
                    Icon(
                        actionIcon,
                        contentDescription = null,
                        tint = tint,
                        modifier = Modifier.size(with(LocalDensity.current) { 15.sp.toDp() })
                    )
                }
                Text(actionTitle, style = ImasType.text(14.sp, FontWeight.SemiBold), color = tint, maxLines = 1)
            }
        }
    }
}

// MARK: - 区画

/**
 * 見出し + 中身 + 補足文 (iOS `ImasSection`)。区画どうしの間隔は並べる側 ([ImasPage]) が持つ。
 * 小さい見出しと補足文は、面の中の行の文字に揃えて左右に行の余白を空ける。
 *
 * @param actionTitle 見出しの右の、その場で何かを始める操作 ([seeAll] と同時には出さない)。
 * @param seeAllTitle [seeAll] の文言。既定は「すべて見る」(「ほかのお題」などその場に合わせた言い方を渡せる)。
 */
@Composable
fun ImasSection(
    title: String? = null,
    modifier: Modifier = Modifier,
    count: String? = null,
    imprint: String? = null,
    style: ImasSectionHeaderStyle = ImasSectionHeaderStyle.LARGE,
    footer: String? = null,
    seeAll: (() -> Unit)? = null,
    seeAllTitle: String = "すべて見る",
    actionTitle: String? = null,
    actionIcon: ImageVector? = null,
    onAction: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit
) {
    Column(modifier.fillMaxWidth()) {
        if (title != null) {
            val side = if (style == ImasSectionHeaderStyle.SMALL) DS.Space.rowH else 0.dp
            ImasSectionHeader(
                title = title,
                count = count,
                onSeeAll = seeAll,
                seeAllTitle = seeAllTitle,
                style = style,
                imprint = imprint,
                actionTitle = actionTitle,
                actionIcon = actionIcon,
                onAction = onAction,
                contentPadding = PaddingValues(start = side, end = side, bottom = DS.Space.header)
            )
        }
        content()
        if (footer != null) {
            ImasNote(footer, Modifier.padding(start = DS.Space.rowH, end = DS.Space.rowH, top = DS.Space.note))
        }
    }
}

/**
 * 区画を縦に並べる画面の本体 (iOS `ImasPage`。詳細・ハブ・ダッシュボード)。
 * 地・左右の余白・区画どうしの間隔・広い画面での本文幅を持つ。中の部品には「紙面の上」を伝える。
 *
 * 中身は縦に全部組む (スクロールする Column)。数百件の一覧を区画で組むなら [ImasLazyPage]。
 */
@Composable
fun ImasPage(
    modifier: Modifier = Modifier,
    scrollState: ScrollState = rememberScrollState(),
    content: @Composable ColumnScope.() -> Unit
) {
    CompositionLocalProvider(LocalImasBackdrop provides ImasBackdrop.PAPER) {
        Box(modifier.fillMaxSize().background(DS.paper)) {
            ReadableWidth { readable ->
                Column(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(scrollState)
                        .padding(readable)
                        .padding(horizontal = DS.Space.screen)
                        .padding(top = DS.Space.gapLoose, bottom = DS.Space.section),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.section),
                    content = content
                )
            }
        }
    }
}

/**
 * [ImasPage] の LazyColumn 版 (Android だけ)。見た目は同じ (地・左右の余白・区画どうしの間隔・本文幅)。
 * iOS の `ImasPage` は中で LazyVStack を使っているので、長い一覧を区画で組む画面はこちらで同じになる。
 */
@Composable
fun ImasLazyPage(
    modifier: Modifier = Modifier,
    state: LazyListState = rememberLazyListState(),
    content: LazyListScope.() -> Unit
) {
    CompositionLocalProvider(LocalImasBackdrop provides ImasBackdrop.PAPER) {
        Box(modifier.fillMaxSize().background(DS.paper)) {
            ReadableWidth { readable ->
                LazyColumn(
                    modifier = Modifier.fillMaxSize().padding(readable),
                    state = state,
                    contentPadding = PaddingValues(
                        start = DS.Space.screen,
                        end = DS.Space.screen,
                        top = DS.Space.gapLoose,
                        bottom = DS.Space.section
                    ),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.section),
                    content = content
                )
            }
        }
    }
}

// MARK: - 面

/** 面の種類 (iOS `ImasCard.Style`)。 */
enum class ImasCardStyle {
    /** 地の上の面。 */
    STANDARD,

    /** 旧名。色の地は敷かなくなったので [STANDARD] と同じ。 */
    TINTED,

    /** カードの中の囲み (面の中の一段濃い窓)。 */
    INSET
}

/**
 * 行でない中身を 1 枚の面にまとめる (iOS `ImasCard`。説明・グラフ・プレビュー)。
 * 色の地を敷かない・影を付けない (面の縁は [imasSurfaceEdge] が持つ)・カードの中にカードを入れない。
 */
@Composable
fun ImasCard(
    modifier: Modifier = Modifier,
    style: ImasCardStyle = ImasCardStyle.STANDARD,
    padding: Dp = DS.Space.card,
    content: @Composable ColumnScope.() -> Unit
) {
    if (style == ImasCardStyle.INSET) {
        Column(
            modifier
                .fillMaxWidth()
                .background(DS.surface2, RoundedCornerShape(DS.rInner))
                .padding(padding),
            content = content
        )
    } else {
        val shape = RoundedCornerShape(DS.rCard)
        Column(
            modifier
                .fillMaxWidth()
                .imasSurface(shape)
                .padding(padding),
            content = content
        )
    }
}

/** 行の並べ方 (iOS `ImasCardList.Style`)。 */
enum class ImasCardListStyle {
    /** 面に入れる。入口・設定・カードの中の短い一覧。 */
    PANEL,

    /** 紙に入れ、行の間を切り取り線で区切る (セトリ・申込書のような「刷られた紙」)。 */
    SHEET,

    /**
     * 紙面にそのまま並べる。行は画面の端から端まで、線は本文の頭から右の端まで。
     * 曲・ライブ・アイドルなど「もの」の一覧 ([ImasPage] の中でだけ使う)。
     */
    PLAIN
}

/**
 * 行を並べる (iOS `ImasCardList`)。中の行は左揃え・幅いっぱい。区切り線は行の部品が持つ。
 * 2 行目以降に線を引かせるには行に位置を伝える ([LocalImasRowPosition])。
 * 並びのデータから組むなら、位置を自動で伝える items 版を使う。
 */
@Composable
fun ImasCardList(
    modifier: Modifier = Modifier,
    style: ImasCardListStyle = ImasCardListStyle.PANEL,
    content: @Composable ColumnScope.() -> Unit
) {
    when (style) {
        ImasCardListStyle.PANEL, ImasCardListStyle.SHEET -> {
            val shape = RoundedCornerShape(DS.rCard)
            CompositionLocalProvider(
                LocalImasDividerStyle provides
                    if (style == ImasCardListStyle.SHEET) ImasDividerStyle.PERFORATED else ImasDividerStyle.HAIRLINE
            ) {
                Column(
                    modifier
                        .fillMaxWidth()
                        .imasSurface(shape)
                        .clip(shape),
                    content = content
                )
            }
        }
        ImasCardListStyle.PLAIN -> Column(
            modifier
                .fillMaxWidth()
                .imasBleed(DS.Space.screen),
            content = content
        )
    }
}

/**
 * 行を並べ、2 行目以降の上に区切り線を引く (iOS `ImasCardList(items) { row }`)。
 * 線は行が本文の頭から引く。
 *
 * @param key 並びの中で行を見分ける鍵 (並べ替えで行の状態を取り違えないため)。
 */
@Composable
fun <T> ImasCardList(
    items: List<T>,
    modifier: Modifier = Modifier,
    style: ImasCardListStyle = ImasCardListStyle.PANEL,
    key: ((T) -> Any)? = null,
    row: @Composable (T) -> Unit
) {
    ImasCardList(modifier, style) {
        items.forEachIndexed { index, item ->
            key(key?.invoke(item) ?: index) {
                CompositionLocalProvider(
                    LocalImasRowPosition provides if (index == 0) ImasRowPosition.FIRST else ImasRowPosition.FOLLOWING
                ) { row(item) }
            }
        }
    }
}

// MARK: - 補足文

/**
 * 区画の下の補足文 (iOS `ImasNote`)。灰色の小さい文で、囲まない。
 * 読まないと困ること (始められない・失敗した) は `ImasNotice` にする。
 *
 * @param color 既定は灰色。欄の値が足りない等、その場の文言だけ朱にしたい時に渡す
 *   (「1つ以上選択してください」等。banner にするほどではない軽い検証の注意)。
 */
@Composable
fun ImasNote(text: String, modifier: Modifier = Modifier, icon: ImageVector? = null, color: Color = ImasTextRole.NOTE.color) {
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        if (icon != null) {
            Icon(
                icon,
                contentDescription = null,
                tint = color,
                modifier = Modifier
                    .padding(top = 2.dp)
                    .size(with(LocalDensity.current) { 13.sp.toDp() })
            )
        }
        Text(text, style = ImasTextRole.NOTE.style, color = color)
    }
}

// MARK: - 区切り線

/** 行の区切りの線の種類 (iOS `ImasDividerStyle`)。 */
enum class ImasDividerStyle {
    /** 細い線 (一覧)。 */
    HAIRLINE,

    /** 切り取り線 (セトリの紙・申込書)。 */
    PERFORATED
}

/** 今の区切りの線の種類。`ImasCardList(SHEET)` が切り取り線にする。 */
val LocalImasDividerStyle = staticCompositionLocalOf { ImasDividerStyle.HAIRLINE }

/** 並んだ行の中での位置 (iOS `ImasRowPosition`)。2 行目以降の行が上に区切り線を引く。 */
enum class ImasRowPosition {
    /** 区切り線を行が引かない (List の中・単独の行)。 */
    STANDALONE,

    /** カードの 1 行目。 */
    FIRST,

    /** カードの 2 行目以降。上に区切り線を引く。 */
    FOLLOWING
}

/** 今の行の位置。`ImasCardList(items)` が行ごとに伝える。 */
val LocalImasRowPosition = staticCompositionLocalOf { ImasRowPosition.STANDALONE }

/**
 * 行の間の線 (iOS `ImasRowDivider`)。色は `DS.sep`、左は行の本文の頭に揃える ([inset])。
 * `ImasCardList(SHEET)` の中では切り取り線 (点線) になる。行の部品が使う (画面では書かない)。
 */
@Composable
fun ImasRowDivider(modifier: Modifier = Modifier, inset: Dp = 0.dp) {
    when (LocalImasDividerStyle.current) {
        ImasDividerStyle.HAIRLINE -> {
            val hairline = with(LocalDensity.current) { 1f.toDp() }
            Box(
                modifier
                    .fillMaxWidth()
                    .padding(start = inset)
                    .height(hairline)
                    .background(DS.sep)
            )
        }
        ImasDividerStyle.PERFORATED -> ImasPerforation(modifier.padding(start = inset), color = DS.perforation)
    }
}

/**
 * 行の上端に区切り線を描く (行の部品が使う)。位置が [ImasRowPosition.FOLLOWING] のときだけ。
 * 線は [inset] (行の本文の頭) から右の端まで。
 */
@Composable
internal fun Modifier.imasRowTopDivider(inset: Dp, position: ImasRowPosition = LocalImasRowPosition.current): Modifier {
    if (position != ImasRowPosition.FOLLOWING) return this
    val style = LocalImasDividerStyle.current
    val color = if (style == ImasDividerStyle.HAIRLINE) DS.sep else DS.perforation
    val rtl = androidx.compose.ui.platform.LocalLayoutDirection.current == androidx.compose.ui.unit.LayoutDirection.Rtl
    return drawWithContent {
        drawContent()
        val start = inset.toPx()
        val (x0, x1) = if (rtl) 0f to size.width - start else start to size.width
        when (style) {
            ImasDividerStyle.HAIRLINE -> drawLine(color, Offset(x0, 0.5f), Offset(x1, 0.5f), strokeWidth = 1f)
            ImasDividerStyle.PERFORATED -> {
                val w = 1.dp.toPx()
                drawImasDash(Offset(x0, w / 2), Offset(x1, w / 2), color, w)
            }
        }
    }
}

// MARK: - 年・月の見出し

/**
 * 年・月で区切る見出し (iOS `ImasDateHeader`。ライブ一覧・収支・予定)。細長い大きな数字と、横に英字の印字。
 * 終わった区切りは薄くする。
 *
 * @param big 大きい数字 (「2026」「11」)。
 * @param imprint 横の印字 (「NOV 2026 · 4 公演」)。
 */
@Composable
fun ImasDateHeader(big: String, modifier: Modifier = Modifier, imprint: String? = null, isPast: Boolean = false) {
    Row(
        modifier
            .fillMaxWidth()
            .padding(top = DS.Space.gapLoose, bottom = DS.Space.gapTight)
            .semantics(mergeDescendants = true) { heading() },
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
    ) {
        Text(
            big,
            style = ImasNumeralSize.DATE.style,
            color = if (isPast) DS.ink3 else DS.ink,
            maxLines = 1,
            modifier = Modifier.alignByBaseline()
        )
        if (imprint != null) {
            Text(
                imprint,
                style = ImasTextRole.IMPRINT.style,
                color = DS.ink3,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.alignByBaseline()
            )
        }
        Spacer(Modifier.weight(1f))
    }
}

// MARK: - 面の縁

/**
 * 面の縁 (iOS `.imasSurfaceEdge(cornerRadius:)`)。ライトはロビーの紙が浮くような薄い影、
 * ダークは客席の暗がりで面が溶けないよう細い線 (`DS.sep`)。
 *
 * ライトの影は面の塗りに付けて描くので、面の色を [fill] に渡す (既定は面 `DS.surface`)。
 * 面そのものを塗るなら [imasSurface] を使う (塗りと縁を 1 度に描く)。
 */
@Composable
fun Modifier.imasSurfaceEdge(shape: Shape, fill: Color = DS.surface): Modifier {
    return if (LocalImasColors.current.dark) {
        border(1.dp, DS.sep, shape)
    } else {
        val ink = DS.ink
        this
            .imasSoftShadow(shape, fill = fill, color = ink.copy(alpha = 0.04f), blur = 0.dp, offsetY = 1.dp)
            .imasSoftShadow(shape, fill = fill, color = ink.copy(alpha = 0.06f), blur = 9.dp, offsetY = 6.dp)
    }
}

/**
 * 面を塗り、縁を付ける ([imasSurfaceEdge] + 塗り)。カード・行のまとまり・申込書の紙。
 * [color] の既定は面 (`DS.surface`。どの地でも同じ面)。
 */
@Composable
fun Modifier.imasSurface(shape: Shape, color: Color = DS.surface): Modifier =
    imasSurfaceEdge(shape, fill = color).background(color, shape)
