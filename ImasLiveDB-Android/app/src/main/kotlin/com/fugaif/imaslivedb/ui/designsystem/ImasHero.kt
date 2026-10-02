package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.layout.positionInParent
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasMotion
import com.fugaif.imaslivedb.ui.theme.ImasPenlight
import com.fugaif.imaslivedb.ui.theme.ImasPenlightSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.imasEnvTheme
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.penlight
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch

// =============================================================================
// 詳細の頭 (docs/DESIGN_SYSTEM.md §2.2・§8.4)。iOS `ImasHero.swift` の移植。
//
// ImasHero      そのものの顔。アイコン (ジャケ) と、大きく組んだ名前。地は白い紙面。
//               曲は大きいジャケを中央に (CENTERED)、アイドル・ユニット・ライブ・公演は
//               アイコンを左・名前を右に (LEADING)。同じ種類のものはいつも同じ形。
//               COLOR は地を実体の色で塗る (担当の顔など、色そのものを主役にする所)。
// ImasMarkBar   担当・お気に入り・参加・メモ・座席の印を横に並べる。
// ImasMarkTile  印 1 つ。丸いパンチ。ON は実体の色で塗られて点く (押すと判子の手応え)。
// ImasTabs      詳細・一覧の中の表示の切り替え。太い文字 + 実体の色の下線。
// ImasSegmented フォーム・設定の中で値を 1 つ選ぶ。墨で塗った札が動く。
//
// 色は環境の実体の色 (`ImasThemeProvider`) から引く。
// =============================================================================

/** 詳細の頭の地 (iOS `ImasHeroSurface`)。 */
enum class ImasHeroSurface {
    /** 白い紙面 (既定)。色はペンライトとアイコンの輪だけ。 */
    PAPER,

    /** 実体の色で塗る。文字は色の上で読める白か黒。 */
    COLOR
}

/** 詳細の頭の並べ方 (iOS `ImasHero.Layout`)。 */
enum class ImasHeroLayout {
    /** 画像を中央に大きく (曲)。 */
    CENTERED,

    /** アイコンを左、名前を右 (アイドル・ユニット・ライブ・公演)。 */
    LEADING
}

/** 詳細の頭の主操作 1 つ (iOS `ImasHero.Action`。再生・出演ライブ・セトリを見る)。 */
@Immutable
data class ImasHeroAction(
    val title: String,
    val icon: ImageVector? = null,
    val isEnabled: Boolean = true,
    val onClick: () -> Unit
)

/**
 * 詳細の頭 (iOS `ImasHero`)。そのものの顔。色は環境の実体の色 (`ImasThemeProvider`)。
 *
 * @param eyebrow 名前の上の小さい見出し (ブランド・種類)。前にペンライトが付く。
 * @param onEyebrowTap 見出しを押したとき (ブランドで絞った一覧など)。null なら押せない。
 * @param subtitle 名前の下 (CV・歌唱者・日付と会場)。
 * @param primary 主操作 1 つ (再生・出演ライブ・セトリを見る)。印は [ImasMarkBar] に置く。
 * @param facts 名前の下の札の並び (全体曲・合同・受賞)。
 * @param media アイコン (ジャケ)。
 */
@Composable
fun ImasHero(
    title: String,
    modifier: Modifier = Modifier,
    layout: ImasHeroLayout = ImasHeroLayout.LEADING,
    surface: ImasHeroSurface = ImasHeroSurface.PAPER,
    eyebrow: String? = null,
    onEyebrowTap: (() -> Unit)? = null,
    subtitle: String? = null,
    primary: ImasHeroAction? = null,
    facts: (@Composable RowScope.() -> Unit)? = null,
    media: @Composable () -> Unit
) {
    val theme = imasEnvTheme
    val onColor = surface == ImasHeroSurface.COLOR && !theme.isNeutral
    val ink = if (onColor) theme.onAccent else DS.ink
    val ink2 = if (onColor) theme.onAccent.copy(alpha = 0.78f) else DS.ink2
    val centered = layout == ImasHeroLayout.CENTERED
    val align = if (centered) TextAlign.Center else TextAlign.Start

    val texts: @Composable (Modifier) -> Unit = { m ->
        Column(
            m,
            horizontalAlignment = if (centered) Alignment.CenterHorizontally else Alignment.Start,
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            if (eyebrow != null) {
                Row(
                    if (onEyebrowTap != null) Modifier.imasPress(onClick = onEyebrowTap) else Modifier,
                    horizontalArrangement = Arrangement.spacedBy(7.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    ImasPenlight(color = if (onColor) theme.onAccent else theme.penlight, size = ImasPenlightSize.REGULAR)
                    Text(eyebrow, style = ImasType.text(13.sp, FontWeight.Bold), color = ink2, maxLines = 1)
                }
            }
            ImasFitText(
                title,
                style = ImasTextRole.HERO_TITLE.style,
                color = ink,
                maxLines = 3,
                minScale = 0.8f,
                textAlign = align
            )
            if (subtitle != null) {
                Text(subtitle, style = ImasType.text(15.sp), color = ink2, maxLines = 2, textAlign = align)
            }
            if (facts != null) {
                Row(
                    Modifier.padding(top = DS.Space.gapTight),
                    horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
                    verticalAlignment = Alignment.CenterVertically,
                    content = facts
                )
            }
        }
    }

    Column(
        modifier
            .fillMaxWidth()
            .background(if (onColor) theme.accent else DS.paper)
            .padding(horizontal = DS.Space.screen)
            .padding(top = if (onColor) DS.Space.card + 4.dp else DS.Space.gapLoose, bottom = DS.Space.card + 4.dp),
        horizontalAlignment = if (centered) Alignment.CenterHorizontally else Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(DS.Space.card + 4.dp)
    ) {
        if (centered) {
            Column(
                Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(DS.Space.card)
            ) {
                media()
                texts(Modifier)
            }
        } else {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(DS.Space.card),
                verticalAlignment = Alignment.CenterVertically
            ) {
                media()
                texts(Modifier.weight(1f))
            }
        }
        if (primary != null) {
            HeroButton(primary, fill = if (onColor) theme.onAccent else DS.sys, text = if (onColor) theme.accent else DS.onSys)
        }
    }
}

/** 頭の主操作 (幅いっぱい・高さ 50)。色の地の上では白黒を反転する (iOS `HeroButtonStyle`)。 */
@Composable
private fun HeroButton(action: ImasHeroAction, fill: Color, text: Color) {
    val size = ImasButtonSize.LARGE
    val shape = RoundedCornerShape(size.cornerRadius)
    val source = remember { MutableInteractionSource() }
    val pressed by source.collectIsPressedAsState()
    val active = action.isEnabled
    val scale by animateFloatAsState(if (pressed && active) 0.98f else 1f, ImasMotion.standard(), label = "heroScale")
    val dim by animateFloatAsState(if (pressed && active) 0.85f else 1f, ImasMotion.standard(), label = "heroDim")
    Row(
        Modifier
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                alpha = dim * if (active) 1f else 0.45f
            }
            .fillMaxWidth()
            .heightIn(min = size.height)
            .background(fill, shape)
            .clickable(interactionSource = source, indication = null, enabled = active, role = Role.Button, onClick = action.onClick)
            .padding(horizontal = size.horizontalPadding),
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically
    ) {
        if (action.icon != null) {
            Icon(
                action.icon,
                contentDescription = null,
                tint = text,
                modifier = Modifier.size(with(LocalDensity.current) { size.iconSize.toDp() })
            )
        }
        Text(action.title, style = ImasType.heading(size.fontSize, FontWeight.Bold), color = text, maxLines = 1)
    }
}

// MARK: - 印

/** 印の並びの寄せ (iOS `ImasMarkBar(alignment:)`)。 */
enum class ImasMarkBarAlignment { START, CENTER }

/**
 * 印 ([ImasMarkTile]) を横に並べる (iOS `ImasMarkBar`)。既定は左寄せ (曲の詳細は中央寄せ)。
 */
@Composable
fun ImasMarkBar(
    modifier: Modifier = Modifier,
    alignment: ImasMarkBarAlignment = ImasMarkBarAlignment.START,
    content: @Composable RowScope.() -> Unit
) {
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(
            14.dp,
            if (alignment == ImasMarkBarAlignment.CENTER) Alignment.CenterHorizontally else Alignment.Start
        ),
        verticalAlignment = Alignment.Top,
        content = content
    )
}

/**
 * 担当・お気に入り・参加・メモ・座席の印 1 つ (iOS `ImasMarkTile`)。丸いパンチと名前。
 * OFF = 線の丸に墨の記号、ON = 丸が実体の色で塗られて点く (ペンライトが点くように)。
 * [isAction] は印でなく操作 (出演ライブ・試聴) で、墨で塗った丸にする。
 *
 * @param accessibilityText 読み上げ。null なら [label]。
 */
@Composable
fun ImasMarkTile(
    icon: ImageVector,
    label: String,
    isOn: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    isAction: Boolean = false,
    accessibilityText: String? = null
) {
    val theme = imasEnvTheme
    val diameter = with(LocalDensity.current) { 50.sp.toDp() }
    val fill = if (isAction) DS.sys else theme.penlight
    val iconColor by animateColorAsState(
        when {
            isAction -> DS.onSys
            isOn -> if (theme.isNeutral) DS.onSys else theme.onAccent
            else -> DS.ink
        },
        ImasMotion.standard(),
        label = "markIcon"
    )
    val line = DS.line
    val haptics = rememberImasHaptics()
    val scope = rememberCoroutineScope()
    // 記号が弾み、判子の手応えを返すのは「押した瞬間」だけ (iOS `.symbolEffect(.bounce)`・
    // `.sensoryFeedback`)。以前は isOn の変化そのものを見ていたため、読み込みで値が後から
    // 変わっただけでも (触っていなくても) 弾んで鳴っていた。ほかの呼び出しでの見え方・
    // 手応えは変えない (押したときは今までどおり弾んで鳴る)。
    val bounce = remember { Animatable(1f) }
    val tap: () -> Unit = {
        haptics.impactMedium()
        scope.launch {
            bounce.snapTo(1.2f)
            bounce.animateTo(1f, ImasMotion.standard())
        }
        onClick()
    }
    val spoken = accessibilityText ?: label
    Column(
        modifier
            .clearAndSetSemantics {
                contentDescription = spoken
                role = Role.Button
                selected = isOn
                onClick { tap(); true }
            }
            .widthIn(min = diameter)
            .imasPress(onClick = tap),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        Box(
            Modifier
                .size(diameter)
                .then(
                    when {
                        isOn -> Modifier.imasSoftShadow(CircleShape, fill = fill, color = fill.copy(alpha = 0.45f), blur = 7.dp, offsetY = 4.dp)
                        isAction -> Modifier.background(fill, CircleShape)
                        else -> Modifier.border(1.5.dp, line, CircleShape)
                    }
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                icon,
                contentDescription = null,
                tint = iconColor,
                modifier = Modifier
                    .size(with(LocalDensity.current) { 21.sp.toDp() })
                    .scale(bounce.value)
            )
        }
        ImasFitText(
            label,
            style = ImasType.text(11.sp, FontWeight.SemiBold),
            color = if (isOn) DS.ink else DS.ink2,
            minScale = 0.8f
        )
    }
}

// MARK: - 表示の切り替え (タブ)

/**
 * 1 つの画面の中で表示を切り替える (iOS `ImasTabs`。詳細のタブ・今後/開催済み・セットリスト/予想)。
 * 文字を左から並べ、選んだものに下線。下線は実体の色 (無ければ墨。ダークでは光る)。
 * フォームで値を選ぶなら [ImasSegmented]、一覧を絞るなら `ImasFilterChip`。
 *
 * @param seed 下線の色 hex。[brand] はブランド ID。どちらも無ければ環境の実体の色。
 */
@Composable
fun <T> ImasTabs(
    options: List<T>,
    selection: T,
    onSelect: (T) -> Unit,
    label: (T) -> String,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null
) {
    val t = ImasChipColors.theme(seed, brand, null)
    val underline = t.penlight
    val dark = LocalImasColors.current.dark
    val haptics = rememberImasHaptics()
    val index = options.indexOf(selection)
    // 選んだ値が変わったら手応え (スワイプで変わったときも。iOS `.sensoryFeedback(.selection)`)。
    var lastIndex by remember { mutableStateOf(index) }
    LaunchedEffect(index) {
        if (index != lastIndex) {
            lastIndex = index
            haptics.selection()
        }
    }
    // 各タブの左端と幅。下線を選んだタブへ滑らせる (iOS `matchedGeometryEffect`)。
    val positions = remember { mutableStateMapOf<Int, Pair<Float, Float>>() }
    val target = positions[index]
    val x = remember { Animatable(0f) }
    val w = remember { Animatable(0f) }
    var placed by remember { mutableStateOf(false) }
    LaunchedEffect(target) {
        if (target == null) return@LaunchedEffect
        if (!placed) {
            x.snapTo(target.first)
            w.snapTo(target.second)
            placed = true
        } else {
            coroutineScope {
                launch { x.animateTo(target.first, ImasMotion.standard()) }
                launch { w.animateTo(target.second, ImasMotion.standard()) }
            }
        }
    }
    val sep = DS.sep
    Box(
        modifier
            .fillMaxWidth()
            .drawBehind {
                // 下の細い線 (幅いっぱい)。
                drawRect(sep, topLeft = Offset(0f, size.height - 1f), size = Size(size.width, 1f))
            }
    ) {
        Row(
            Modifier
                .horizontalScroll(rememberScrollState())
                .drawWithContent {
                    drawContent()
                    if (target != null && placed && w.value > 0f) {
                        val h = 3.dp.toPx()
                        val top = size.height - h
                        val r = h / 2
                        if (dark) {
                            // ダークでは下線が光る (iOS `.shadow(color: penlight, radius: 5)`)。
                            drawIntoCanvas { canvas ->
                                val paint = Paint().apply { color = underline }
                                paint.asFrameworkPaint().setShadowLayer(5.dp.toPx(), 0f, 0f, underline.toArgb())
                                canvas.drawRoundRect(x.value, top, x.value + w.value, size.height, r, r, paint)
                            }
                        } else {
                            drawRoundRect(underline, Offset(x.value, top), Size(w.value, h), CornerRadius(r, r))
                        }
                    }
                },
            horizontalArrangement = Arrangement.spacedBy(22.dp)
        ) {
            options.forEachIndexed { i, option ->
                val on = i == index
                Text(
                    label(option),
                    style = ImasType.heading(16.sp, FontWeight.ExtraBold),
                    color = if (on) DS.ink else DS.ink3,
                    maxLines = 1,
                    modifier = Modifier
                        .onPlaced { positions[i] = it.positionInParent().x to it.size.width.toFloat() }
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Tab
                        ) { if (!on) onSelect(option) }
                        .semantics { selected = on }
                        .padding(vertical = 12.dp)
                )
            }
        }
    }
}

/** 文言の並びから組むタブ (iOS `ImasTabs(labels:selection:)`)。 */
@Composable
fun ImasTabs(
    labels: List<String>,
    selection: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    seed: String? = null,
    brand: String? = null
) {
    ImasTabs(
        options = labels.indices.toList(),
        selection = selection,
        onSelect = onSelect,
        label = { labels[it] },
        modifier = modifier,
        seed = seed,
        brand = brand
    )
}

// MARK: - 値を 1 つ選ぶ (フォーム)

/**
 * フォーム・設定の中で値を 1 つ選ぶ (iOS `ImasSegmented`。期間・表示の単位・文字の大きさ)。
 * 薄い溝の上を、墨で塗った札が選んだ値へ動く。画面の中身を切り替えるなら [ImasTabs]。
 *
 * 引数の並び (labels・selection・onSelect・modifier) は Android の今の呼び出しの形のまま。
 * [selection] が範囲の外 (-1 など) なら札を出さない。
 *
 * @param captions [labels] と同じ並びの 2 行目 (「1:1」の下に「正方形」のような補足)。
 *   null (既定) なら今まで通り 1 行。シェア画像の比率トグルのように、値と説明を両方
 *   見せたいときだけ渡す (既存の呼び出しはすべてこの引数を省略するので見た目は変わらない)。
 */
@Composable
fun ImasSegmented(
    labels: List<String>,
    selection: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
    captions: List<String>? = null
) {
    val height: Dp = with(LocalDensity.current) { 34.sp.toDp() }
    val haptics = rememberImasHaptics()
    val count = labels.size.coerceAtLeast(1)
    val valid = selection in labels.indices
    var lastSelection by remember { mutableStateOf(selection) }
    LaunchedEffect(selection) {
        if (selection != lastSelection) {
            lastSelection = selection
            haptics.selection()
        }
    }
    val pos by animateFloatAsState(
        selection.coerceIn(0, count - 1).toFloat(),
        ImasMotion.standard(),
        label = "segment"
    )
    val pill = DS.sys
    val pillRadius = DS.rControl(height) - 2.dp
    Row(
        modifier
            .fillMaxWidth()
            .background(DS.fill, RoundedCornerShape(DS.rControl(height + 6.dp)))
            .padding(3.dp)
            .drawBehind {
                if (valid) {
                    val segment = size.width / count
                    drawRoundRect(pill, Offset(segment * pos, 0f), Size(segment, size.height), CornerRadius(pillRadius.toPx()))
                }
            }
    ) {
        labels.forEachIndexed { i, text ->
            val on = i == selection
            Box(
                Modifier
                    .weight(1f)
                    .heightIn(min = height)
                    .clickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        role = Role.Tab
                    ) { if (!on) onSelect(i) }
                    .semantics { selected = on },
                contentAlignment = Alignment.Center
            ) {
                val caption = captions?.getOrNull(i)
                if (caption != null) {
                    Column(
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(1.dp),
                        modifier = Modifier.padding(horizontal = 4.dp, vertical = 4.dp)
                    ) {
                        ImasFitText(
                            text,
                            style = ImasType.text(13.sp, if (on) FontWeight.Bold else FontWeight.SemiBold),
                            color = if (on) DS.onSys else DS.ink2,
                            minScale = 0.8f
                        )
                        ImasFitText(
                            caption,
                            style = ImasType.text(10.sp),
                            color = if (on) DS.onSys.copy(alpha = 0.7f) else DS.ink3,
                            minScale = 0.8f
                        )
                    }
                } else {
                    ImasFitText(
                        text,
                        style = ImasType.text(15.sp, if (on) FontWeight.Bold else FontWeight.SemiBold),
                        color = if (on) DS.onSys else DS.ink2,
                        minScale = 0.8f,
                        modifier = Modifier.padding(horizontal = 4.dp)
                    )
                }
            }
        }
    }
}

/** 値の並びから組む (iOS `ImasSegmented(options:selection:label:)`)。 */
@Composable
fun <T> ImasSegmented(
    options: List<T>,
    selection: T,
    onSelect: (T) -> Unit,
    label: (T) -> String,
    modifier: Modifier = Modifier
) {
    ImasSegmented(
        labels = options.map(label),
        selection = options.indexOf(selection),
        onSelect = { onSelect(options[it]) },
        modifier = modifier
    )
}
