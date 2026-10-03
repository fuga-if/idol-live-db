package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
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
import androidx.compose.foundation.layout.ExperimentalLayoutApi
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.data.lyrics.CallEmphasis
import com.fugaif.imaslivedb.data.lyrics.CallTiming
import com.fugaif.imaslivedb.data.lyrics.LyricCall
import com.fugaif.imaslivedb.data.lyrics.LyricClap
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasColors
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasTheme
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

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
    seed: String? = null
) {
    val scale by androidx.compose.animation.core.animateFloatAsState(if (isCurrent) 1f else 0.86f, label = "imasPlayerLyricLineScale")
    Row(
        modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(DS.sp2),
        verticalAlignment = Alignment.Top
    ) {
        Text(
            text,
            style = if (isMarker) ImasType.heading(17.sp, FontWeight.Bold) else ImasType.heading(28.sp, FontWeight.Black),
            color = if (isCurrent) DS.ink else DS.ink3,
            modifier = Modifier
                .weight(1f)
                .scale(scale)
        )
        if (isLiked) ImasLyricLikeMark(seed = seed, modifier = Modifier.padding(top = DS.sp1))
    }
}

/**
 * 被せ・追いかけ・コーラス (歌詞の括弧の中) を、メインの行の下に重ねる 2 段目 (iOS `ImasPlayerOverlayLine`)。
 * メインより小さく、左に細い罫を引いて「重なっている層」だと分かるようにする。
 */
@Composable
fun ImasPlayerOverlayLine(text: String, isCurrent: Boolean, seed: String?, modifier: Modifier = Modifier) {
    val theme = imasTheme(seed = seed)
    Row(
        modifier
            .fillMaxWidth()
            .padding(start = DS.sp5),
        horizontalArrangement = Arrangement.spacedBy(DS.sp2)
    ) {
        Box(Modifier.width(2.dp).fillMaxHeight().background(if (isCurrent) theme.accent else DS.sep))
        Text(
            text,
            style = ImasType.heading(19.sp, FontWeight.Bold),
            color = if (isCurrent) DS.ink2 else DS.ink3,
            modifier = Modifier.weight(1f)
        )
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
