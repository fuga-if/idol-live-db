package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.unit.toSize
import com.fugaif.imaslivedb.data.lyrics.CallEmphasis
import com.fugaif.imaslivedb.data.lyrics.CallTiming
import com.fugaif.imaslivedb.data.lyrics.LyricCall
import com.fugaif.imaslivedb.data.lyrics.LyricClap
import com.fugaif.imaslivedb.data.lyrics.LyricPartMark
import com.fugaif.imaslivedb.data.lyrics.colorsAt
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasTheme
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import uniffi.imas_core.lyricChunkAt
import uniffi.imas_core.lyricRubySpans

// =============================================================================
// 歌詞の行の印 (docs/DESIGN_SYSTEM.md §9 の延長)。iOS `ImasLyricLine.swift` の移植。
//
// 用途      歌詞タブの 1 行に重ねる印。再生に追従している今の行・タイミング記録で次に
//           タップする行・ここ好き・記録した時刻。コール表の記号 (手拍子・コール行・凡例) も
//           ここに置く (iOS は CallGuideLineViews.swift / CallPalette.swift に分けているが、
//           どちらも歌詞専用の DS 部品で、screen 側の素の dp/sp を避けるためこのファイルへ集約)。
//
// 光らせない・ぼかさない (グラデーション・光は禁止)。色は曲の配色 (担当色 / ブランド色) だけ。
// =============================================================================

/** 行に重ねる状態 (iOS `ImasLyricLineState`)。 */
enum class ImasLyricLineState { NORMAL, CURRENT, CURSOR }

/**
 * 歌詞の行に「今の行」「次に記録する行」の印を重ねる (iOS `.imasLyricLine(_:seed:)`)。
 * SwiftUI の `.padding(負)` で地を余白へはみ出させる作りを、Box の中身をそのまま背景付きで包む形に直した。
 */
@Composable
fun ImasLyricLineRow(
    state: ImasLyricLineState,
    seed: String?,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit
) {
    val theme = imasTheme(seed = seed)
    val dark = LocalImasColors.current.dark
    val fillAlpha = when (state) {
        ImasLyricLineState.NORMAL -> 0f
        ImasLyricLineState.CURRENT -> if (dark) 0.24f else 0.14f
        ImasLyricLineState.CURSOR -> if (dark) 0.14f else 0.08f
    }
    val bg by animateColorAsState(theme.accent.copy(alpha = fillAlpha), label = "imasLyricLineBg")
    Box(modifier.fillMaxWidth().background(bg)) {
        if (state != ImasLyricLineState.NORMAL) {
            Box(
                Modifier
                    .padding(vertical = DS.sp1)
                    .width(3.dp)
                    .fillMaxHeight()
                    .background(theme.accent)
            )
        }
        Box(Modifier.padding(start = if (state != ImasLyricLineState.NORMAL) DS.sp3 else 0.dp)) { content() }
    }
}

/** 行末の「ここ好き」。付いている行にだけ置く。 */
@Composable
fun ImasLyricLikeMark(seed: String?, modifier: Modifier = Modifier) {
    val theme = imasTheme(seed = seed)
    Icon(
        Icons.Filled.Favorite,
        contentDescription = "ここ好き",
        tint = theme.accent,
        modifier = modifier.size(13.dp)
    )
}

/** 記録した時刻 (「1:02.3」)。記録が無い行は「—」。 */
@Composable
fun ImasLyricTimeLabel(ms: Int?, isEmphasized: Boolean = false, modifier: Modifier = Modifier) {
    Text(
        ms?.let { format(it) } ?: "—",
        style = ImasType.mono(12.sp, FontWeight.Medium),
        color = if (isEmphasized) DS.ink else DS.ink3,
        maxLines = 1,
        modifier = modifier.semantics { contentDescription = ms?.let { "${format(it)} から" } ?: "時刻なし" }
    )
}

private fun format(ms: Int): String {
    val tenths = max(0, ms) / 100
    return "%d:%02d.%d".format(tenths / 600, (tenths / 10) % 60, tenths % 10)
}

/** 経過/残りの「1:02」表示 (分:秒)。 */
fun imasLyricClock(ms: Int): String {
    val s = max(0, ms) / 1000
    return "%d:%02d".format(s / 60, s % 60)
}

// MARK: - ここ好きの山つきシークバー

/**
 * 曲の時間軸に「ここ好き」の山を立てたシークバー (iOS `ImasLikeHeatSeekBar`)。
 * 山は細い縦棒の並び。再生済みの側は曲の色、まだの側は墨の薄い色。いちばん好かれている
 * 地点の上に小さなハートを置く。タップ (と [allowsScrub] なら なぞり) で位置を選べる。
 */
@Composable
fun ImasLikeHeatSeekBar(
    levels: List<Float>,
    progress: Double?,
    peak: Double?,
    seed: String?,
    modifier: Modifier = Modifier,
    allowsScrub: Boolean = false,
    onSeek: (Double) -> Unit
) {
    val theme = imasTheme(seed = seed)
    var scrubFraction by remember { mutableStateOf<Double?>(null) }
    val shown = scrubFraction ?: progress
    val height = 36.dp
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .height(height)
            .semantics { contentDescription = "ここ好きの多い場所" }
    ) {
        val widthDp = maxWidth
        val widthPx = with(androidx.compose.ui.platform.LocalDensity.current) { widthDp.toPx() }
        fun fractionOf(x: Float): Double = (x / max(widthPx, 1f)).toDouble().coerceIn(0.0, 1.0)
        Box(
            Modifier
                .fillMaxSize()
                .then(
                    if (allowsScrub) {
                        Modifier.imasSeekBarDrag(
                            onChanged = { x -> scrubFraction = fractionOf(x) },
                            onEnded = { x -> val f = fractionOf(x); scrubFraction = null; onSeek(f) }
                        )
                    } else {
                        Modifier.imasSeekBarTap { x -> onSeek(fractionOf(x)) }
                    }
                )
        ) {
            if (levels.isEmpty()) {
                Box(Modifier.align(Alignment.BottomStart).fillMaxWidth().height(2.dp).background(DS.sep))
            } else {
                Row(
                    Modifier.align(Alignment.BottomStart).fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(1.dp),
                    verticalAlignment = Alignment.Bottom
                ) {
                    levels.forEachIndexed { i, level ->
                        val played = shown?.let { i.toDouble() / levels.size < it } ?: false
                        Box(
                            Modifier
                                .weight(1f)
                                .height((level * (height.value - 10)).dp.coerceAtLeast(2.dp))
                                .background(if (played) theme.accent else DS.ink3.copy(alpha = 0.35f))
                        )
                    }
                }
            }
            shown?.let { p ->
                Box(
                    Modifier
                        .align(Alignment.BottomStart)
                        .offset(x = (widthDp.value * p.toFloat()).dp - 1.dp)
                        .width(2.dp)
                        .height(height - 4.dp)
                        .background(DS.ink)
                )
            }
            peak?.let { p ->
                Icon(
                    Icons.Filled.Favorite,
                    contentDescription = "おすすめ地点",
                    tint = theme.accent,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .offset(x = (widthDp.value * p.toFloat()).dp - 5.dp)
                        .size(10.dp)
                )
            }
        }
    }
}

/** シークバーのタップ検出 (独自実装: [ImasLikeHeatSeekBar] / [ImasTimingTimeline] で使う横位置のみの検出)。 */
@Composable
private fun Modifier.imasSeekBarTap(onTap: (Float) -> Unit): Modifier =
    this.pointerInput(onTap) {
        detectTapGestures(onTap = { onTap(it.x) })
    }

/** なぞり (横位置が動いている間 [onChanged]、離したら最後の位置で [onEnded]) の検出。 */
@Composable
private fun Modifier.imasSeekBarDrag(onChanged: (Float) -> Unit, onEnded: (Float) -> Unit): Modifier {
    var lastX by remember { mutableStateOf(0f) }
    return this
        .pointerInput(Unit) {
            detectDragGestures(
                onDragStart = { lastX = it.x },
                onDrag = { change, _ -> lastX = change.position.x; onChanged(lastX) },
                onDragEnd = { onEnded(lastX) },
                onDragCancel = { onEnded(lastX) }
            )
        }
        .pointerInput(Unit) {
            detectTapGestures(onTap = { onEnded(it.x) })
        }
}

// MARK: - 歌詞プレイヤーの 1 行

/**
 * 行の中のコールの掛かる語 (`text` のコードポイント位置)。いつも曲の色の下線で印を付け、
 * いま叫ぶところは字ごと曲の色で点ける (今の行になる前から、どこがコールか見える)。
 * iOS `ImasPlayerLyricLine.Echo` の移植。
 */
data class ImasEcho(val start: Int, val end: Int)

/** [start] (コードポイント位置) に掛かるコールを探す (重なりは先勝ち)。 */
private fun echoAt(start: Int, echoes: List<ImasEcho>): ImasEcho? =
    echoes.firstOrNull { start >= it.start && start < it.end }

/**
 * 歌詞プレイヤーの 1 行 (iOS `ImasPlayerLyricLine`)。今の行は大きく墨、それ以外は小さく薄く。
 * 大きさは縮尺 (scale) で変える — 文字サイズで変えると行の折り返しが変わってしまうため。
 */
@Composable
fun ImasPlayerLyricLine(
    text: String,
    isCurrent: Boolean,
    modifier: Modifier = Modifier,
    isMarker: Boolean = false,
    isLiked: Boolean = false,
    // 歌詞と同じ文字を一緒に叫ぶところ (同時コール)。
    echoes: List<ImasEcho> = emptyList(),
    /** 歌う人の担当色 (字をその色で塗る)。あれば振り仮名と同じ組み方 (FlowRow) で描く。 */
    parts: List<LyricPartMark> = emptyList(),
    seed: String? = null
) {
    val scale by androidx.compose.animation.core.animateFloatAsState(if (isCurrent) 1f else 0.86f, label = "imasPlayerLyricLineScale")
    val theme = imasTheme(seed = seed)
    val style = if (isMarker) ImasType.heading(17.sp, FontWeight.Bold) else ImasType.heading(28.sp, FontWeight.Black)
    val color = if (isCurrent) DS.ink else DS.ink3
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(DS.sp2),
        verticalAlignment = Alignment.Top
    ) {
        // 括弧で書いた脇の字 (被せ・歌わない字) は一段小さく薄く出す。
        val asideStyle = ImasLyricAside.forPlayer(isMarker, color)
        if (ImasRubyText.hasRuby(text) || parts.isNotEmpty()) {
            // 振り仮名・歌う人の色の塗り分けは Text では組めないので FlowRow で自前に組む。
            ImasRubyFlowText(
                text = text,
                style = style,
                color = color,
                modifier = Modifier
                    .weight(1f)
                    .scale(scale),
                asideStyle = asideStyle,
                accent = theme.accent,
                echoAt = { start -> echoAt(start, echoes) },
                partsAt = { start -> parts.colorsAt(start) },
                // 今の行でないときは、歌う人の色も地の字と同じく控えめにする。
                partsAlpha = if (isCurrent) 1f else 0.45f
            )
        } else {
            ImasEchoText(
                text = text,
                annotated = echoMarked(ImasRubyText.asideAttributed(text, asideStyle = asideStyle), text, echoes, theme.accent),
                echoes = echoes,
                accent = theme.accent,
                style = style,
                color = color,
                modifier = Modifier
                    .weight(1f)
                    .scale(scale)
            )
        }
        if (isLiked) ImasLyricLikeMark(seed = seed, modifier = Modifier.padding(top = DS.sp1))
    }
}

/**
 * コールの掛かる語に曲の色の下線を引き、いま叫ぶところは字も曲の色にする ([echoMarked] で
 * 文字色だけ先に重ねる)。下線は文字色と別の色で引けるよう [TextLayoutResult] から範囲の矩形を
 * 取り、文字の地に重ねて描く (Compose の `TextDecoration` は文字色と同じ色でしか引けない)。
 */
@Composable
private fun ImasEchoText(
    text: String,
    annotated: androidx.compose.ui.text.AnnotatedString,
    echoes: List<ImasEcho>,
    accent: Color,
    style: androidx.compose.ui.text.TextStyle,
    color: Color,
    modifier: Modifier = Modifier
) {
    if (echoes.isEmpty()) {
        Text(annotated, style = style, color = color, modifier = modifier)
        return
    }
    var layout by remember { mutableStateOf<androidx.compose.ui.text.TextLayoutResult?>(null) }
    val underlineRanges = remember(text, echoes) {
        echoes.map { codePointToCharIndex(text, it.start) until codePointToCharIndex(text, it.end) }
            .filter { !it.isEmpty() }
    }
    Text(
        annotated,
        style = style,
        color = color,
        modifier = modifier.drawBehind {
            val result = layout ?: return@drawBehind
            val strokeWidth = 2.dp.toPx()
            for (range in underlineRanges) {
                drawEchoUnderline(result, range, accent, strokeWidth)
            }
        },
        onTextLayout = { layout = it }
    )
}

/** [range] (UTF-16 文字添字、半開区間) の下に [accent] の下線を引く。折り返しをまたぐ行ごとに分けて引く。 */
private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawEchoUnderline(
    result: androidx.compose.ui.text.TextLayoutResult,
    range: IntRange,
    accent: Color,
    strokeWidth: Float
) {
    val length = result.layoutInput.text.length
    val lineSegments = linkedMapOf<Int, Pair<Float, Float>>()
    for (i in range.first until range.last + 1) {
        if (i < 0 || i >= length) continue
        val box = result.getBoundingBox(i)
        val line = result.getLineForOffset(i)
        val prev = lineSegments[line]
        lineSegments[line] = if (prev == null) box.left to box.right else minOf(prev.first, box.left) to maxOf(prev.second, box.right)
    }
    for ((line, segment) in lineSegments) {
        val y = result.getLineBottom(line) - strokeWidth
        drawLine(color = accent, start = Offset(segment.first, y), end = Offset(segment.second, y), strokeWidth = strokeWidth)
    }
}

/**
 * コールの掛かる語に曲の色の文字色を重ねる (いま叫ぶところだけ)。下線は [ImasEchoText] が別に引く
 * (文字色と違う色で引くため)。iOS `ImasPlayerLyricLine.echoMarked` の移植。
 */
private fun echoMarked(
    base: androidx.compose.ui.text.AnnotatedString,
    text: String,
    echoes: List<ImasEcho>,
    accent: Color
): androidx.compose.ui.text.AnnotatedString {
    // 叫ぶ瞬間に色を変えても間に合わないので、文字色は変えない (下線は ImasEchoText が常に引く)。
    return base
}

/**
 * 被せ・追いかけ・コーラス (歌詞の括弧の中) を、メインの行の下に重ねる 2 段目 (iOS `ImasPlayerOverlayLine`)。
 * メインより小さく、左に細い罫を引いて「重なっている層」だと分かるようにする。
 */
@Composable
fun ImasPlayerOverlayLine(
    text: String,
    isCurrent: Boolean,
    seed: String?,
    modifier: Modifier = Modifier,
    /** 被せの中で、歌詞と同じ文字を一緒に叫ぶところ (同時コール)。メインの行と同じく下線で印を付ける。 */
    echoes: List<ImasEcho> = emptyList()
) {
    val theme = imasTheme(seed = seed)
    Row(
        modifier
            .fillMaxWidth()
            .padding(start = DS.sp5),
        horizontalArrangement = Arrangement.spacedBy(DS.sp2)
    ) {
        Box(Modifier.width(2.dp).fillMaxHeight().background(if (isCurrent) theme.accent else DS.sep))
        ImasEchoText(
            text = text,
            annotated = echoMarked(androidx.compose.ui.text.AnnotatedString(text), text, echoes, theme.accent),
            echoes = echoes,
            accent = theme.accent,
            style = ImasType.heading(19.sp, FontWeight.Bold),
            color = if (isCurrent) DS.ink2 else DS.ink3,
            modifier = Modifier.weight(1f)
        )
    }
}

/**
 * 歌詞プレイヤーで行の直下に出すコール 1 つ (iOS `ImasPlayerCallLine`)。
 * いま出すコールは大きく色で点け、他は控えめに。
 * (下の操作面にコールの段を別に置かず、歌詞の流れの中でコールを読ませる。)
 */
@Composable
fun ImasPlayerCallLine(
    marker: String,
    text: String,
    /** コールの色 (強調度ごと。[CallEmphasis.lyricColor])。 */
    color: Color,
    isActive: Boolean,
    modifier: Modifier = Modifier
) {
    val fontSize by androidx.compose.animation.core.animateFloatAsState(
        if (isActive) 24f else 15f, label = "imasPlayerCallLineSize"
    )
    Row(
        modifier
            .fillMaxWidth()
            .padding(start = DS.sp3)
            .semantics {
                contentDescription = "コール $text"
                selected = isActive
            },
        horizontalArrangement = Arrangement.spacedBy(DS.sp2),
        verticalAlignment = Alignment.Top
    ) {
        Text(
            marker,
            style = ImasType.text(12.sp),
            color = DS.ink3,
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
            modifier = Modifier.width(16.dp)
        )
        Text(
            text,
            style = ImasType.heading(fontSize.sp, if (isActive) FontWeight.Black else FontWeight.Bold),
            color = if (isActive) color else color.copy(alpha = 0.55f),
            modifier = Modifier.weight(1f)
        )
    }
}

// MARK: - パート分け (誰が歌うか)

/**
 * 歌唱者の担当色を並べた縞 (iOS `ImasPartStripe`)。4dp 幅、並び順に上から積む。
 * 行頭 (クラップ記号の横) に置き、誰が歌う行かを色だけでも伝える。
 */
@Composable
fun ImasPartStripe(colors: List<String>, modifier: Modifier = Modifier) {
    Column(modifier.width(4.dp).fillMaxHeight()) {
        colors.forEach { hex ->
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .background(imasTheme(seed = hex).accent)
            )
        }
    }
}

/** 1 字を塗り分ける色の上限 (全体曲で全員の色を重ねると縞が細すぎて読めないので、超えた分は省く。iOS と同じ)。 */
private const val PART_COLORS_MAX = 4

/**
 * 何人かで歌う字を、字の中で上から歌う人の順に塗り分ける縞 (ハードな色の境目、ぼかさない・光らせない)。
 * [Brush.verticalGradient] に同じ色を 2 度ずつ (帯の上端・下端) 置くことで、滑らかな階調を作らず
 * くっきりした帯にする。
 */
private fun imasPartStripeBrush(colors: List<Color>): Brush {
    val n = colors.size
    val stops = mutableListOf<Pair<Float, Color>>()
    colors.forEachIndexed { i, c ->
        stops += (i.toFloat() / n) to c
        stops += ((i + 1).toFloat() / n) to c
    }
    return Brush.verticalGradient(colorStops = stops.toTypedArray())
}

/** 行の下に添える歌唱者の名前 (「春香・千早」。iOS `ImasPartNames`)。帯の色だけに頼らず言葉でも出す。 */
@Composable
fun ImasPartNames(names: List<String>, modifier: Modifier = Modifier) = ImasPartNames(groups = listOf(names), modifier = modifier)

/**
 * 行のひと続きごとの名前 (行の途中で歌う人が変わるところで分け、「→」でつなぐ)。
 * 1 つだけなら「春香・千早」のまま。
 */
@JvmName("ImasPartNamesGrouped")
@Composable
fun ImasPartNames(groups: List<List<String>>, modifier: Modifier = Modifier) {
    val shown = groups.filter { it.isNotEmpty() }
    if (shown.isEmpty()) return
    val text = shown.joinToString(" → ") { it.joinToString("・") }
    val description = "歌唱 " + shown.joinToString("、つづいて ") { it.joinToString("、") }
    Text(
        text,
        style = ImasType.text(12.sp),
        color = DS.ink2,
        maxLines = 2,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier.semantics { contentDescription = description }
    )
}

/** [ImasPartsSelectableLine] に敷く、すでに塗ってあるひと続き ([start]..[end])。 */
data class ImasPartsHighlight(val start: Int, val end: Int, val color: Color)

/**
 * 行を字 (コードポイント) ごとに並べ、タップ・長押しなぞりで範囲を選ぶ
 * (タイミング編集のパートの段。iOS `CallGuideSelectableLine` の移植、選べる単位はここでは
 * コードポイント)。
 *
 * - タップ … 触れた字を含む語をまとめて選ぶ (切れ目はコアの `lyricChunkAt` が決める)
 * - 長押しからなぞる … 語をまたいだ範囲を選ぶ
 *
 * 選んだ範囲は [onSelect] (開始, 終了 [終了は含まない]) で返すだけで、実際に塗る/外すかは
 * 呼び出し側 (筆の人がすでに全部入っていれば外す) が決める。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImasPartsSelectableLine(
    text: String,
    highlights: List<ImasPartsHighlight>,
    onSelect: (Int, Int) -> Unit,
    modifier: Modifier = Modifier
) {
    val bounds = remember(text) { codePointBounds(text) }
    val count = bounds.size - 1
    var containerCoords by remember { mutableStateOf<LayoutCoordinates?>(null) }
    val cellRects = remember(text) { mutableMapOf<Int, Rect>() }
    var dragRange by remember { mutableStateOf<IntRange?>(null) }
    val dragColor = imasTheme(seed = null).accent

    fun cellAt(point: Offset): Int? {
        if (cellRects.isEmpty()) return null
        cellRects.entries.firstOrNull { it.value.contains(point) }?.let { return it.key }
        return cellRects.entries.minByOrNull { (_, r) ->
            val dx = max(max(r.left - point.x, 0f), point.x - r.right)
            val dy = max(max(r.top - point.y, 0f), point.y - r.bottom)
            dx * dx + dy * dy
        }?.key
    }

    fun commit(range: IntRange) {
        val start = range.first.coerceIn(0, count)
        val end = (range.last + 1).coerceIn(0, count)
        if (start < end) onSelect(start, end)
    }

    Box(
        modifier
            .onGloballyPositioned { containerCoords = it }
            .pointerInput(text) {
                detectTapGestures(onTap = { point ->
                    val index = cellAt(point) ?: return@detectTapGestures
                    val chunk = lyricChunkAt(text, index.toUInt())
                    if (chunk != null) onSelect(chunk.start.toInt(), chunk.end.toInt()) else commit(index..index)
                })
            }
            .pointerInput(text) {
                var origin: Int? = null
                detectDragGesturesAfterLongPress(
                    onDragStart = { point -> origin = cellAt(point); dragRange = origin?.let { it..it } },
                    onDrag = { change, _ ->
                        val index = cellAt(change.position) ?: return@detectDragGesturesAfterLongPress
                        val o = origin ?: index
                        origin = o
                        dragRange = min(o, index)..max(o, index)
                    },
                    onDragEnd = { dragRange?.let { commit(it) }; dragRange = null; origin = null },
                    onDragCancel = { dragRange = null; origin = null }
                )
            }
    ) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(0.dp)) {
            for (cp in 0 until count) {
                val cellText = text.substring(bounds[cp], bounds[cp + 1])
                val background = when {
                    dragRange?.contains(cp) == true -> dragColor.copy(alpha = 0.45f)
                    else -> highlights.lastOrNull { cp >= it.start && cp < it.end }?.color?.copy(alpha = 0.3f)
                        ?: Color.Transparent
                }
                Text(
                    cellText,
                    style = ImasType.text(17.sp),
                    color = DS.ink,
                    modifier = Modifier
                        .background(background)
                        .onGloballyPositioned { coords ->
                            val parent = containerCoords ?: return@onGloballyPositioned
                            val pos = parent.localPositionOf(coords, Offset.Zero)
                            cellRects[cp] = Rect(pos, coords.size.toSize())
                        }
                )
            }
        }
    }
}

// MARK: - 手拍子記号 (コール表)

/** 行頭の手拍子記号 (iOS `CallGuideClapGlyph`)。指定の無い行でも幅を確保する。 */
@Composable
fun ImasClapGlyph(clap: LyricClap?, modifier: Modifier = Modifier, isPlaceholderVisible: Boolean = false) {
    Box(modifier.width(18.dp), contentAlignment = Alignment.CenterStart) {
        when {
            clap != null -> Text(
                clap.symbol,
                style = ImasType.text(12.sp),
                color = DS.ink2,
                modifier = Modifier.semantics { contentDescription = clap.label }
            )
            isPlaceholderVisible -> Icon(
                Icons.Filled.Add,
                contentDescription = "手拍子を指定",
                tint = DS.ink3,
                modifier = Modifier.size(12.dp)
            )
        }
    }
}

// MARK: - コールの強調度の配色

/**
 * 強調度の色 (iOS `CallEmphasis.color(accent:)`)。凡例・コール文言・アンカーのハイライトで同じ色を使う。
 * `normal` は曲の配色 (担当色/ブランド色) を使う。無ければ本文色 (ink) へ落ちる。
 */
@Composable
fun CallEmphasis.lyricColor(accent: Color?): Color = when (this) {
    CallEmphasis.NORMAL -> accent ?: DS.ink
    CallEmphasis.OPTIONAL -> DS.success
    CallEmphasis.PERFORMER_REQUEST -> DS.danger
}

/** 同一行に複数のアンカーがあるときの対応付け記号 (①②③…)。10 件超は素の数字。 */
fun imasAnchorMarker(index: Int): String {
    val circled = listOf("①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧", "⑨", "⑩")
    return if (index < circled.size) circled[index] else "(${index + 1})"
}

// MARK: - コール行

/**
 * 歌詞行の直下に並ぶコール群 (iOS `CallGuideCallRows`)。配列順をそのまま保つ (並べ替えない)。
 * 行内にアンカーが 2 つ以上あるときだけ ①②③ を振る。
 */
@Composable
fun ImasCallRows(
    calls: List<LyricCall>,
    anchorIndexes: Map<String, Int>?,
    modifier: Modifier = Modifier,
    onTap: ((LyricCall) -> Unit)? = null
) {
    val isMixed = calls.any { it.hasAnchor } && calls.any { !it.hasAnchor }
    val theme = imasTheme(seed = null)
    Column(modifier.padding(start = DS.sp5, top = DS.sp1), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        calls.forEach { call ->
            val marker = when {
                !call.hasAnchor -> "»"
                anchorIndexes?.get(call.id) == null -> "↳"
                else -> imasAnchorMarker(anchorIndexes[call.id]!!)
            }
            Row(
                Modifier
                    .fillMaxWidth()
                    .then(if (onTap != null) Modifier.imasPress(onClick = { onTap(call) }) else Modifier),
                horizontalArrangement = Arrangement.spacedBy(5.dp),
                verticalAlignment = Alignment.Top
            ) {
                Text(marker, style = ImasType.text(11.sp), color = DS.ink3, modifier = Modifier.widthIn(min = 16.dp))
                Text(
                    call.text,
                    style = ImasType.text(13.sp, FontWeight.SemiBold),
                    color = call.emphasis.lyricColor(theme.accent),
                    modifier = Modifier.weight(1f)
                )
                if (call.isOverlapping) {
                    ImasBadge(text = "同時", kind = ImasBadgeKind.NEUTRAL)
                } else if (isMixed && !call.hasAnchor) {
                    ImasBadge(text = "行末", kind = ImasBadgeKind.NEUTRAL)
                }
                if (call.stale) {
                    ImasBadge(text = "ズレ", kind = ImasBadgeKind.ATTENTION)
                }
            }
        }
    }
}

// MARK: - 凡例

/**
 * コール表の凡例 (iOS `CallGuideLegend`)。その曲で実際に使われているものだけを出す。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImasCallLegend(
    emphases: List<CallEmphasis>,
    claps: List<LyricClap>,
    showsOverTiming: Boolean,
    modifier: Modifier = Modifier
) {
    val theme = imasTheme(seed = null)
    if (emphases.isEmpty() && claps.isEmpty() && !showsOverTiming) return
    androidx.compose.foundation.layout.FlowRow(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(DS.sp2),
        verticalArrangement = Arrangement.spacedBy(DS.sp2)
    ) {
        emphases.forEach { emphasis ->
            ImasChip(text = emphasis.label, style = ImasChipStyle.NEUTRAL, leading = ImasChipLeading.Swatch(emphasis.lyricColor(theme.accent)))
        }
        claps.forEach { clap ->
            ImasChip(text = "${clap.symbol} ${clap.label}", style = ImasChipStyle.NEUTRAL)
        }
        if (showsOverTiming) {
            ImasChip(text = "${CallTiming.OVER.label} 歌に被せる", style = ImasChipStyle.NEUTRAL)
        }
    }
}

// MARK: - タイミング編集のタイムライン

/** 横長のタイムライン (iOS `ImasTimingTimeline`) の帯 1 件。 */
data class ImasTimingBlock(val id: String, val startMs: Int, val endMs: Int, val label: String)

/**
 * 横長のタイムライン (動画編集アプリの並び)。再生位置は真ん中に固定し、帯の方が流れる (iOS 版と同じ)。
 *
 * - 地を横になぞる … 再生位置を動かす ([onScrub] が動いている間、[onScrubEnd] が離したとき)
 * - 帯をタップ … その行を選ぶ
 */
@Composable
fun ImasTimingTimeline(
    blocks: List<ImasTimingBlock>,
    subLanes: List<List<ImasTimingBlock>>,
    playheadMs: Int,
    selectedId: String?,
    seed: String?,
    modifier: Modifier = Modifier,
    pointsPerSecond: Dp = 70.dp,
    onScrub: (Int) -> Unit,
    onScrubEnd: (Int) -> Unit,
    onSelect: (String) -> Unit,
    onMoveStart: (String, Int) -> Unit
) {
    val theme = imasTheme(seed = seed)
    val visibleSubLanes = subLanes.filter { it.isNotEmpty() }
    val rulerHeight = 20.dp
    val blockHeight = 48.dp
    val callHeight = 34.dp
    val totalHeight = rulerHeight + blockHeight + 8.dp + (callHeight + 4.dp) * visibleSubLanes.size

    BoxWithConstraints(modifier.fillMaxWidth().height(totalHeight)) {
        val density = androidx.compose.ui.platform.LocalDensity.current
        val widthDp = maxWidth
        val widthPx = with(density) { widthDp.toPx() }
        val ppsPx = with(density) { pointsPerSecond.toPx() }
        fun xOf(ms: Int): Float = widthPx / 2f + (ms - playheadMs) / 1000f * ppsPx
        var scrubFrom by remember { mutableStateOf<Int?>(null) }

        Box(
            Modifier
                .fillMaxSize()
                .imasDragDelta(
                    onChanged = { dx ->
                        val from = scrubFrom ?: playheadMs
                        if (scrubFrom == null) scrubFrom = from
                        onScrub(max(0, from - (dx / ppsPx * 1000).roundToInt()))
                    },
                    onEnded = { dx ->
                        val from = scrubFrom ?: playheadMs
                        scrubFrom = null
                        onScrubEnd(max(0, from - (dx / ppsPx * 1000).roundToInt()))
                    }
                )
        ) {
            // 目盛り (5 秒ごとに時刻)。
            val visibleSeconds = (widthPx / ppsPx).roundToInt() + 2
            val firstSecond = max(0, playheadMs / 1000 - visibleSeconds / 2)
            for (s in firstSecond..(firstSecond + visibleSeconds)) {
                val major = s % 5 == 0
                Column(
                    Modifier.offset { androidx.compose.ui.unit.IntOffset(xOf(s * 1000).roundToInt(), 0) }
                ) {
                    Box(Modifier.width(1.dp).height(if (major) 10.dp else 6.dp).background(if (major) DS.ink2 else DS.sep))
                    if (major) {
                        Text("%d:%02d".format(s / 60, s % 60), style = ImasType.mono(10.sp, FontWeight.Medium), color = DS.ink3)
                    }
                }
            }
            blocks.forEach { b ->
                val left = xOf(b.startMs)
                val w = max(6f, xOf(b.endMs) - left - 2)
                if (left + w > -40 && left < widthPx + 40) {
                    timelineBlock(
                        b, with(density) { w.toDp() }, blockHeight, theme.accent, b.id == selectedId,
                        onSelect = onSelect, onMoveStart = onMoveStart, ppsPx = ppsPx,
                        modifier = Modifier.offset { androidx.compose.ui.unit.IntOffset(left.roundToInt(), with(density) { (rulerHeight + 4.dp).roundToPx() }) }
                    )
                }
            }
            visibleSubLanes.forEachIndexed { lane, laneBlocks ->
                laneBlocks.forEach { b ->
                    val left = xOf(b.startMs)
                    val w = max(6f, xOf(b.endMs) - left - 2)
                    if (left + w > -40 && left < widthPx + 40) {
                        val y = with(density) { (rulerHeight + blockHeight + 8.dp + (callHeight + 4.dp) * lane).roundToPx() }
                        timelineBlock(
                            b, with(density) { w.toDp() }, callHeight, theme.accent, b.id == selectedId,
                            onSelect = onSelect, onMoveStart = onMoveStart, ppsPx = ppsPx,
                            modifier = Modifier.offset { androidx.compose.ui.unit.IntOffset(left.roundToInt(), y) }
                        )
                    }
                }
            }
            // 再生位置 (真ん中に固定)。
            Box(
                Modifier
                    .offset { androidx.compose.ui.unit.IntOffset((widthPx / 2 - 1).roundToInt(), 0) }
                    .width(2.dp)
                    .height(totalHeight)
                    .background(DS.ink)
            )
        }
    }
}

@Composable
private fun timelineBlock(
    b: ImasTimingBlock,
    width: Dp,
    height: Dp,
    accent: Color,
    selected: Boolean,
    onSelect: (String) -> Unit,
    onMoveStart: (String, Int) -> Unit,
    ppsPx: Float,
    modifier: Modifier = Modifier
) {
    val dark = LocalImasColors.current.dark
    Box(
        modifier
            .width(width)
            .height(height)
            .background(if (selected) accent.copy(alpha = if (dark) 0.32f else 0.2f) else DS.fill)
            .imasPress(onClick = { onSelect(b.id) })
            .semantics { contentDescription = b.label }
    ) {
        Text(
            b.label,
            style = ImasType.text(12.sp),
            color = if (selected) DS.ink else DS.ink2,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = DS.sp3, end = DS.sp1).align(Alignment.CenterStart)
        )
        if (selected) {
            var moveFrom by remember { mutableStateOf<Int?>(null) }
            Box(
                Modifier
                    .width(28.dp)
                    .fillMaxHeight()
                    .imasDragDelta(
                        onChanged = { dx ->
                            val from = moveFrom ?: b.startMs
                            if (moveFrom == null) moveFrom = from
                            onMoveStart(b.id, max(0, from + (dx / ppsPx * 1000).roundToInt()))
                        },
                        onEnded = { moveFrom = null }
                    ),
                contentAlignment = Alignment.CenterStart
            ) {
                Box(
                    Modifier
                        .padding(start = 2.dp)
                        .width(6.dp)
                        .height(height - 12.dp)
                        .background(accent)
                        .semantics { contentDescription = "歌い出しのつまみ" }
                )
            }
        }
    }
}

/**
 * 水平方向のドラッグ量 (px、**ジェスチャ開始からの累積**。SwiftUI `DragGesture.translation` と同じ) を渡す。
 * `detectDragGestures` が渡すのは直前との差分だけなので、ここで積み上げて揃える。
 */
@Composable
private fun Modifier.imasDragDelta(onChanged: (Float) -> Unit, onEnded: (Float) -> Unit): Modifier =
    this.pointerInput(Unit) {
        var total = 0f
        detectDragGestures(
            onDragStart = { total = 0f },
            onDrag = { change, dragAmount -> total += dragAmount.x; onChanged(total) },
            onDragEnd = { onEnded(total); total = 0f },
            onDragCancel = { onEnded(total); total = 0f }
        )
    }

// MARK: - 振り仮名 (ルビ)

/**
 * 振り仮名 1 文字 (塊) ぶんの装い。背景 (アンカーの敷き) ・太字・下線はコール表の行だけで使う
 * (歌詞プレイヤーの行は付けない)。[ImasRubyFlowText.highlightAt] が親字の先頭のコードポイント
 * 添字から引く。
 */
data class RubyHighlight(val background: Color? = null, val bold: Boolean = false, val underline: Boolean = false)

/**
 * 括弧で書いた脇の字 (被せ・コーラス・歌わない字) を一段小さく薄くする書式 (iOS の `asideFont`/`asideColor`)。
 * 画面には数字を渡させず、ここに決め打ちで持つ (DS のトークンから引く)。
 */
data class ImasAsideStyle(
    val fontSize: androidx.compose.ui.unit.TextUnit,
    val color: Color,
    val weight: FontWeight? = null
)

/** [ImasAsideStyle] を場面ごとに組み立てる (歌詞タブの閲覧・歌詞プレイヤー)。 */
object ImasLyricAside {
    /** 歌詞タブの閲覧モード (本文 17sp → 13sp、DS.ink2)。太字にはしない。 */
    @Composable
    fun forViewing(): ImasAsideStyle = ImasAsideStyle(fontSize = 13.sp, color = DS.ink2)

    /** 歌詞プレイヤーの行 (見出し 28 heavy / マーカー 17 bold → 20 / 14 の bold、今の色の 0.6 濃度)。 */
    fun forPlayer(isMarker: Boolean, color: Color): ImasAsideStyle =
        ImasAsideStyle(fontSize = (if (isMarker) 14 else 20).sp, color = color.copy(alpha = 0.6f), weight = FontWeight.Bold)
}

/**
 * 歌詞の振り仮名 (`見本字《みほんじ》` / `｜ダミー《だみ》`) を、記号を外して**親字の上**に乗せる。
 * どこが振り仮名かはコア (`lyricRubySpans`) が決める。被せの括弧 (`（）` `()`) はここでは触らない
 * (iOS `ImasRubyText` の移植。Compose の `Text` はルビを組めないので [ImasRubyFlowText] で自前に組む)。
 *
 * ⚠️ 歌詞の本文を扱う。組み立てた文字列を保存・共有しないこと (`data/lyrics/Lyrics.kt` 冒頭)。
 */
object ImasRubyText {
    /** 本文を折り返せる単位に割った 1 つ。素通しは 1 文字、振り仮名は親字ひとまとまり (折り返さない)。 */
    sealed class Atom {
        /** 行の中のコードポイント添字 (ハイライトを引く鍵)。 */
        abstract val start: Int

        /** 括弧で書いた脇の字 (被せ・コーラス・歌わない字) か。[Ruby] は常に false (振り仮名はこの規則の対象外)。 */
        abstract val isAside: Boolean

        data class Plain(val char: String, override val start: Int, override val isAside: Boolean = false) : Atom()
        data class Ruby(val base: String, val reading: String, override val start: Int) : Atom() {
            override val isAside: Boolean get() = false
        }
    }

    fun hasRuby(text: String): Boolean = lyricRubySpans(text).isNotEmpty()

    /** 各コードポイントが括弧で書いた脇の字 (被せ・コーラス・歌わない字) か。括弧も含む。規則はコア。 */
    fun asides(text: String): BooleanArray {
        val count = codePointBounds(text).size - 1
        val out = BooleanArray(count)
        for (span in uniffi.imas_core.lyricAsideSpans(text)) {
            for (k in span.start.toInt() until minOf(span.end.toInt(), count)) out[k] = true
        }
        return out
    }

    /**
     * 本文全体を、脇の字 (括弧) だけ [asideStyle] で小さく薄くした [AnnotatedString]。振り仮名の無い
     * 行の `Text` 用 (iOS `ImasRubyText.asideAttributed` の移植)。
     */
    fun asideAttributed(text: String, asideStyle: ImasAsideStyle): androidx.compose.ui.text.AnnotatedString {
        val bounds = codePointBounds(text)
        val aside = asides(text)
        return androidx.compose.ui.text.buildAnnotatedString {
            var k = 0
            while (k < aside.size) {
                val start = k
                val isAside = aside[k]
                while (k < aside.size && aside[k] == isAside) k++
                val segment = text.substring(bounds[start], bounds[k])
                if (isAside) {
                    withStyle(
                        androidx.compose.ui.text.SpanStyle(
                            fontSize = asideStyle.fontSize, color = asideStyle.color, fontWeight = asideStyle.weight
                        )
                    ) { append(segment) }
                } else {
                    append(segment)
                }
            }
        }
    }

    /**
     * [text] を [Atom] の並びに割る。添字はコードポイント (= コアの Unicode スカラー) 単位で扱い、
     * 文字列に戻すところだけ UTF-16 の添字に直す ([codePointToCharIndex])。
     *
     * 1 つの振り仮名の親字がアンカーの境目をまたぐ (ハイライトが途中で変わる) ような稀な行は、
     * 親字の先頭の扱いに合わせる (iOS 版もこの境目では読みを重複させる側に寄っており、厳密な
     * 一致は求めない)。
     */
    fun atoms(text: String): List<Atom> {
        val bounds = codePointBounds(text)
        val count = bounds.size - 1
        val aside = asides(text)
        val rubyIndex = IntArray(count) { -1 }
        val hidden = BooleanArray(count)
        val isReading = BooleanArray(count)
        val readings = mutableListOf<String>()
        for (span in lyricRubySpans(text)) {
            val open = span.open.toInt()
            val close = span.close.toInt()
            val baseStart = span.baseStart.toInt()
            val baseEnd = span.baseEnd.toInt()
            if (open >= close || close > count || baseStart > baseEnd || baseEnd > open) continue
            val index = readings.size
            readings.add(text.substring(bounds[open + 1], bounds[close - 1]))
            for (k in baseStart until baseEnd) rubyIndex[k] = index
            hidden[open] = true
            hidden[close - 1] = true
            for (k in (open + 1) until (close - 1)) isReading[k] = true
            span.marker?.let { m -> val mi = m.toInt(); if (mi in 0 until count) hidden[mi] = true }
        }
        val out = mutableListOf<Atom>()
        var k = 0
        while (k < count) {
            if (hidden[k] || isReading[k]) {
                k++
                continue
            }
            if (rubyIndex[k] < 0) {
                out.add(Atom.Plain(text.substring(bounds[k], bounds[k + 1]), k, aside[k]))
                k++
            } else {
                val index = rubyIndex[k]
                val start = k
                while (k < count && rubyIndex[k] == index) k++
                out.add(Atom.Ruby(text.substring(bounds[start], bounds[k]), readings[index], start))
            }
        }
        return out
    }
}

/** コードポイントごとの UTF-16 添字の境目 (`bounds[i]..bounds[i+1]` がコードポイント i の範囲)。 */
private fun codePointBounds(text: String): IntArray {
    val count = text.codePointCount(0, text.length)
    val bounds = IntArray(count + 1)
    var charIndex = 0
    for (i in 0 until count) {
        bounds[i] = charIndex
        charIndex += Character.charCount(text.codePointAt(charIndex))
    }
    bounds[count] = charIndex
    return bounds
}

/** コードポイントの添字を Kotlin (UTF-16) の文字添字に直す。 */
internal fun codePointToCharIndex(text: String, codePointIndex: Int): Int {
    if (codePointIndex <= 0) return 0
    var charIndex = 0
    var count = 0
    while (count < codePointIndex && charIndex < text.length) {
        charIndex += Character.charCount(text.codePointAt(charIndex))
        count++
    }
    return charIndex
}

/**
 * 振り仮名のある行を、読みを親字の上に乗せて組む (iOS `ImasRubyLabel` に相当)。
 * 折り返しが利くよう [ImasRubyText.atoms] で割った単位を [FlowRow] に流す — 素通しの文字は
 * 1 文字ずつ、振り仮名は親字ひとまとまり。読みは親字と同じ書体・色で 0.5 倍の大きさにし、
 * 素通しの文字の上には同じ大きさの透明な読みを置いて高さを揃える (ベースラインが揃う)。
 *
 * [highlightAt] はコードポイント添字 (親字・素通しの文字の先頭) からコール表のアンカーの
 * 敷き・下線を引く (歌詞プレイヤーの行では渡さない = 無装飾)。読み自体には敷かない
 * (iOS 版も読みはアンカーの装飾を受けない)。
 *
 * ⚠️ 歌詞の本文を扱う。`SelectionContainer` / コピーの口を足さないこと。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ImasRubyFlowText(
    text: String,
    style: androidx.compose.ui.text.TextStyle,
    color: Color,
    modifier: Modifier = Modifier,
    highlightAt: ((Int) -> RubyHighlight?)? = null,
    /** 括弧で書いた脇の字 (被せ・歌わない字) の素通しの文字だけ、これで一段小さく薄く出す。 */
    asideStyle: ImasAsideStyle? = null,
    /** 同時コールの色 (曲の色)。[echoAt] と一緒に渡すと、掛かる親字に下線を引き、いま叫ぶところは
     *  字も曲の色にする (iOS `ImasPlayerLyricLine` の同時コールの印)。 */
    accent: Color? = null,
    /** 各原子の先頭 (コードポイント位置) に掛かる同時コール。歌詞プレイヤーの行でのみ渡す。 */
    echoAt: ((Int) -> ImasEcho?)? = null,
    /** 各原子の先頭 (コードポイント位置) に掛かる、歌う人の担当色 (hex)。字をその色で塗る
     *  (1 人ならその色、何人か [PART_COLORS_MAX] までなら字の中を縞で塗り分ける)。 */
    partsAt: ((Int) -> List<String>)? = null,
    /** [partsAt] の色の濃さ (今の行でないときは控えめにするため、呼び出し側が渡す)。 */
    partsAlpha: Float = 1f
) {
    val atoms = remember(text) { ImasRubyText.atoms(text) }
    val readingSize = (style.fontSize.value * 0.5f).sp
    androidx.compose.foundation.layout.FlowRow(
        modifier,
        horizontalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        atoms.forEach { atom ->
            val highlight = highlightAt?.invoke(atom.start)
            val echo = echoAt?.invoke(atom.start)
            val baseModifier = if (highlight?.background != null) Modifier.background(highlight.background) else Modifier
            val echoModifier = if (echo != null && accent != null) {
                baseModifier.drawBehind {
                    val strokeWidth = 2.dp.toPx()
                    drawLine(
                        color = accent,
                        start = Offset(0f, size.height - strokeWidth / 2),
                        end = Offset(size.width, size.height - strokeWidth / 2),
                        strokeWidth = strokeWidth
                    )
                }
            } else {
                baseModifier
            }
            val isAside = atom.isAside && asideStyle != null
            val weight = if (isAside) (asideStyle?.weight ?: style.fontWeight) else if (highlight?.bold == true) FontWeight.Bold else style.fontWeight
            val decoration = if (highlight?.underline == true) androidx.compose.ui.text.style.TextDecoration.Underline else null
            val atomFontSize = if (isAside) asideStyle!!.fontSize else style.fontSize
            // 歌う人の色で字を塗る。
            val partColors = if (isAside) emptyList() else
                partsAt?.invoke(atom.start)?.take(PART_COLORS_MAX)?.map { imasTheme(seed = it).accent.copy(alpha = partsAlpha) }
                    ?: emptyList()
            val atomBrush = if (partColors.size > 1) imasPartStripeBrush(partColors) else null
            val atomColor = when {
                isAside -> asideStyle!!.color
                partColors.size == 1 -> partColors[0]
                else -> color
            }
            val atomStyle = style.copy(fontWeight = weight, fontSize = atomFontSize, textDecoration = decoration, brush = atomBrush)
            val resolvedColor = if (atomBrush != null) Color.Unspecified else atomColor
            when (atom) {
                is ImasRubyText.Atom.Plain -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    // 読みと同じ書体・大きさの透明な行 (素通しの文字の上にも同じ高さを確保し、
                    // ルビの親字とベースラインが揃うようにする)。
                    Text("　", fontFamily = style.fontFamily, fontWeight = style.fontWeight, fontSize = readingSize, color = Color.Transparent, maxLines = 1)
                    Text(atom.char, style = atomStyle, color = resolvedColor, modifier = echoModifier)
                }
                is ImasRubyText.Atom.Ruby -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(atom.reading, fontFamily = style.fontFamily, fontWeight = style.fontWeight, fontSize = readingSize, color = color, maxLines = 1)
                    Text(atom.base, style = atomStyle, color = resolvedColor, modifier = echoModifier)
                }
            }
        }
    }
}

/**
 * 読み仮名の付いた歌詞の見本 (投稿画面。iOS `ImasRubyPreview` の移植)。記法 (親字《よみ》) の入った
 * 本文のうち、読み仮名のある行だけを歌詞の画面と同じく親字の上に読みを載せて並べる。記法そのものは
 * 見せない。
 */
@Composable
fun ImasRubyPreview(text: String, modifier: Modifier = Modifier) {
    val lines = remember(text) { text.split("\n").filter(ImasRubyText::hasRuby) }
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        lines.forEach { line ->
            ImasRubyFlowText(
                text = line,
                style = ImasType.text(17.sp, FontWeight.Medium),
                color = DS.ink,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}
