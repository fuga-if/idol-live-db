package com.fugaif.imaslivedb.ui.designsystem

import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.drag
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PageSize
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.cardName
import com.fugaif.imaslivedb.ui.theme.imasRowPress
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import org.json.JSONObject

// =============================================================================
// P名刺の写真・書体・四隅 (docs/DESIGN_SYSTEM.md §6.13)。iOS `ImasProducerCard.swift` の移植。
//
// ImasCardPortrait    名刺の写真の証明写真の枠 (3:4)。名刺・名刺入れの行・編集画面で同じ枠。
// ImasPortraitCrop    名刺の写真の切り抜き (拡大と真ん中の点)。
// ImasPortraitCropper 名刺の写真を枠に合わせて指で動かす・広げる。枠の外は暗く沈めず、そのまま切る。
// ImasNameFontPicker  名前の書体の見本の札を横に並べ、引いて真ん中に来た札を選ぶ (押しても選ぶ)。
// ImasCornerAdjuster  写真に写った紙の名刺の四隅を指で直す。丸い取っ手 4 つと四隅を結ぶ墨の線。
// =============================================================================

/** 名刺の写真の証明写真の枠 (3:4)。紙に貼った写真のように、角を小さく丸めて縁を付ける。 */
@Composable
fun ImasCardPortrait(url: String?, modifier: Modifier = Modifier, label: String = "名刺の写真") {
    val shape = RoundedCornerShape(DS.rTag)
    Box(
        modifier
            .aspectRatio(ImasPortraitCrop.ASPECT)
            .imasSurfaceEdge(shape, fill = DS.surface2)
            .clip(shape)
            .semantics { contentDescription = label }
    ) {
        if (url != null) {
            SubcomposeAsyncImage(
                model = url,
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
                loading = { Box(Modifier.fillMaxSize().background(DS.surface2)) },
                error = { Box(Modifier.fillMaxSize().background(DS.surface2)) }
            )
        }
    }
}

/** 編集画面の小さな名刺の写真 (iOS の @ScaledMetric(relativeTo: .body) 60 の枠)。 */
@Composable
fun ImasCardPortraitThumbnail(url: String?, modifier: Modifier = Modifier) {
    val width = with(LocalDensity.current) { 60.sp.toDp() }
    ImasCardPortrait(url = url, modifier = modifier.width(width))
}

/** 切り抜く四角 (元の写真の px)。 */
@Immutable
data class ImasCropRect(val left: Float, val top: Float, val width: Float, val height: Float) {
    val centerX: Float get() = left + width / 2f
    val centerY: Float get() = top + height / 2f
}

/**
 * 名刺の写真の切り抜き (iOS `ImasPortraitCrop`)。[zoom] は枠いっぱいに収めた大きさからの拡大 (1 以上)、
 * [centerX] / [centerY] は元の写真の中で枠の真ん中に来る点 (0〜1、左上が原点)。
 */
@Immutable
data class ImasPortraitCrop(val zoom: Float = 1f, val centerX: Float = 0.5f, val centerY: Float = 0.5f) {
    /** 元の写真 (px) の中で切り抜く四角。 */
    fun rect(width: Float, height: Float): ImasCropRect {
        if (width <= 0f || height <= 0f) return ImasCropRect(0f, 0f, 0f, 0f)
        val baseW = min(width, height * ASPECT)
        val w = baseW / zoom.coerceIn(1f, MAX_ZOOM)
        val h = w / ASPECT
        val cx = (centerX * width).coerceIn(w / 2f, width - w / 2f)
        val cy = (centerY * height).coerceIn(h / 2f, height - h / 2f)
        return ImasCropRect(cx - w / 2f, cy - h / 2f, w, h)
    }

    /** 枠からはみ出さないように直した切り抜き。 */
    fun clamped(width: Float, height: Float): ImasPortraitCrop {
        if (width <= 0f || height <= 0f) return this
        val r = rect(width, height)
        return ImasPortraitCrop(zoom.coerceIn(1f, MAX_ZOOM), r.centerX / width, r.centerY / height)
    }

    /** 切り抜いた写真 (900×1200px)。 */
    fun render(image: Bitmap): Bitmap? = runCatching {
        val r = rect(image.width.toFloat(), image.height.toFloat())
        if (r.width <= 0f) return null
        val out = Bitmap.createBitmap(OUTPUT_WIDTH, OUTPUT_HEIGHT, Bitmap.Config.ARGB_8888)
        val src = Rect(r.left.roundToInt(), r.top.roundToInt(), (r.left + r.width).roundToInt(), (r.top + r.height).roundToInt())
        AndroidCanvas(out).apply {
            drawColor(android.graphics.Color.WHITE)
            drawBitmap(image, src, RectF(0f, 0f, OUTPUT_WIDTH.toFloat(), OUTPUT_HEIGHT.toFloat()), Paint(Paint.FILTER_BITMAP_FLAG))
        }
        out
    }.getOrNull()

    fun toJson(): String = JSONObject().put("zoom", zoom.toDouble()).put("x", centerX.toDouble()).put("y", centerY.toDouble()).toString()

    companion object {
        /** 枠の縦横比 (横 / 縦)。証明写真の 3:4。 */
        const val ASPECT = 3f / 4f
        const val MAX_ZOOM = 5f
        /** 書き出す大きさ (px)。 */
        const val OUTPUT_WIDTH = 900
        const val OUTPUT_HEIGHT = 1200

        fun fromJson(json: String): ImasPortraitCrop? = runCatching {
            val o = JSONObject(json)
            ImasPortraitCrop(o.getDouble("zoom").toFloat(), o.getDouble("x").toFloat(), o.getDouble("y").toFloat())
        }.getOrNull()
    }
}

/** 名刺の写真を枠に合わせる (iOS `ImasPortraitCropper`)。引いて動かし、つまんで広げる。枠の外は暗く沈めず、そのまま切る。 */
@Composable
fun ImasPortraitCropper(
    image: Bitmap,
    crop: ImasPortraitCrop,
    onCropChange: (ImasPortraitCrop) -> Unit,
    modifier: Modifier = Modifier
) {
    val bitmap = remember(image) { image.asImageBitmap() }
    val pxW = image.width.toFloat()
    val pxH = image.height.toFloat()
    val current by rememberUpdatedState(crop)
    val change by rememberUpdatedState(onCropChange)
    val shape = RoundedCornerShape(DS.rInner)
    // iOS の @ScaledMetric(relativeTo: .body) 260。
    val maxWidth = with(LocalDensity.current) { 260.sp.toDp() }
    Box(modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Canvas(
            Modifier
                .widthIn(max = maxWidth)
                .fillMaxWidth()
                .aspectRatio(ImasPortraitCrop.ASPECT)
                .imasSurfaceEdge(shape)
                .clip(shape)
                .semantics {
                    contentDescription = "名刺の写真の位置。引いて動かし、2 本の指で広げます"
                    customActions = listOf(
                        CustomAccessibilityAction("広げる") { change(current.copy(zoom = current.zoom + 0.25f).clamped(pxW, pxH)); true },
                        CustomAccessibilityAction("縮める") { change(current.copy(zoom = current.zoom - 0.25f).clamped(pxW, pxH)); true }
                    )
                }
                .pointerInput(image) {
                    detectTransformGestures { _, pan, zoom, _ ->
                        val start = current
                        val zoomed = start.copy(zoom = start.zoom * zoom).clamped(pxW, pxH)
                        val r = zoomed.rect(pxW, pxH)
                        val scale = if (r.width > 0f) size.width / r.width else 1f
                        val next = zoomed.copy(
                            centerX = (r.centerX - pan.x / scale) / pxW,
                            centerY = (r.centerY - pan.y / scale) / pxH
                        )
                        change(next.clamped(pxW, pxH))
                    }
                }
        ) {
            val r = crop.rect(pxW, pxH)
            if (r.width <= 0f) return@Canvas
            val s = size.width / r.width
            drawImage(
                bitmap,
                dstOffset = IntOffset((-r.left * s).roundToInt(), (-r.top * s).roundToInt()),
                dstSize = androidx.compose.ui.unit.IntSize((pxW * s).roundToInt(), (pxH * s).roundToInt())
            )
        }
    }
}

/** 名前の書体の見本の札 1 枚 (iOS `ImasNameFontPicker.Option`)。 */
@Immutable
data class ImasNameFontOption(
    /** 保存のキー (`gothic`)。 */
    val id: String,
    /** 書体の名前 (「明朝」)。 */
    val label: String,
    /** 書体。null は見出しの書体。 */
    val family: FontFamily?
)

/**
 * 名前の書体の見本を横に並べる (iOS `ImasNameFontPicker`)。引くと真ん中に来た書体を選び、押してもその書体を選ぶ。
 * 見本は紙の札 (地は紙のまま)。選んだ札は墨の太い縁と ✓。
 */
@Composable
fun ImasNameFontPicker(
    options: List<ImasNameFontOption>,
    selection: String,
    onSelect: (String) -> Unit,
    sample: String,
    modifier: Modifier = Modifier
) {
    if (options.isEmpty()) return
    val density = LocalDensity.current
    // iOS の @ScaledMetric(relativeTo: .body) 176 × 92。
    val tileWidth = with(density) { 176.sp.toDp() }
    val tileHeight = with(density) { 92.sp.toDp() }
    val selectedIndex = options.indexOfFirst { it.id == selection }.coerceAtLeast(0)
    val pager = rememberPagerState(initialPage = selectedIndex) { options.size }
    val scope = rememberCoroutineScope()
    val haptics = rememberImasHaptics()
    val select by rememberUpdatedState(onSelect)
    val currentSelection by rememberUpdatedState(selection)

    // 引いて止まった札を選ぶ。
    LaunchedEffect(pager) {
        snapshotFlow { pager.settledPage }.distinctUntilChanged().collect { page ->
            val id = options.getOrNull(page)?.id ?: return@collect
            if (id != currentSelection) {
                haptics.selection()
                select(id)
            }
        }
    }
    // 外から選び直したら (札を押した等) その札を真ん中へ。
    LaunchedEffect(selectedIndex) {
        if (pager.currentPage != selectedIndex) pager.animateScrollToPage(selectedIndex)
    }

    // 横に引くのはここで受けて札を送る (Pager の既定の引きは使わない)。既定の引きは指を離した勢いを
    // 外の入れ子のスクロールへ渡し、シート (ModalBottomSheet) がそれを受けて閉じてしまう。
    val swipe = Modifier.pointerInput(pager) {
        val tracker = VelocityTracker()
        var startPage = 0
        detectHorizontalDragGestures(
            onDragStart = {
                tracker.resetTracking()
                startPage = pager.currentPage
            },
            onHorizontalDrag = { change, dx ->
                change.consume()
                tracker.addPosition(change.uptimeMillis, change.position)
                pager.dispatchRawDelta(-dx)
            },
            onDragEnd = {
                val v = tracker.calculateVelocity().x
                val flingAt = 400.dp.toPx()
                val target = when {
                    v < -flingAt -> maxOf(startPage + 1, pager.currentPage)
                    v > flingAt -> minOf(startPage - 1, pager.currentPage)
                    else -> pager.currentPage
                }.coerceIn(0, options.size - 1)
                scope.launch { pager.animateScrollToPage(target) }
            },
            onDragCancel = { scope.launch { pager.animateScrollToPage(pager.currentPage) } }
        )
    }
    BoxWithConstraints(modifier.fillMaxWidth().then(swipe).semantics { contentDescription = "名前の書体" }) {
        val inset = ((maxWidth - tileWidth) / 2).coerceAtLeast(0.dp)
        HorizontalPager(
            state = pager,
            pageSize = PageSize.Fixed(tileWidth),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = inset),
            pageSpacing = DS.Space.gap,
            userScrollEnabled = false,
            modifier = Modifier.fillMaxWidth().height(tileHeight)
        ) { page ->
            val option = options[page]
            val on = option.id == selection
            val shape = RoundedCornerShape(DS.rInner)
            Column(
                Modifier
                    .fillMaxSize()
                    .background(DS.surface, shape)
                    .border(if (on) 2.dp else 1.dp, if (on) DS.ink else DS.line, shape)
                    .clip(shape)
                    .imasRowPress(onClick = {
                        if (option.id != selection) {
                            haptics.selection()
                            select(option.id)
                        }
                        scope.launch { pager.animateScrollToPage(page) }
                    })
                    .padding(DS.Space.card)
                    .clearAndSetSemantics {
                        contentDescription = option.label
                        selected = on
                    }
            ) {
                ImasFitText(
                    sample.ifEmpty { "ふがP" },
                    style = ImasType.cardName(option.family, 24.sp),
                    color = DS.ink,
                    maxLines = 1,
                    minScale = 0.5f,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(Modifier.weight(1f))
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                    Text(option.label, style = ImasTextRole.ROW_LABEL.style, color = if (on) DS.ink else DS.ink2, modifier = Modifier.weight(1f))
                    ImasSelectionMark(isSelected = on, isSingle = true)
                }
            }
        }
    }
}

/**
 * 写真に写った紙の名刺の四隅を指で直す (iOS `ImasCornerAdjuster`)。写真は枠に収めて出し、四隅に丸い取っ手、
 * 四隅を結ぶ線を重ねる。[corners] は左上・右上・右下・左下の順、写真の中の 0〜1 (左上が原点)。
 */
@Composable
fun ImasCornerAdjuster(
    image: Bitmap,
    corners: List<Offset>,
    onCornersChange: (List<Offset>) -> Unit,
    modifier: Modifier = Modifier
) {
    val bitmap = remember(image) { image.asImageBitmap() }
    val aspect = max(image.width, 1).toFloat() / max(image.height, 1).toFloat()
    val current by rememberUpdatedState(corners)
    val change by rememberUpdatedState(onCornersChange)
    val density = LocalDensity.current
    // iOS の @ScaledMetric(relativeTo: .body) 28。
    val handle = with(density) { 28.sp.toDp() }
    val handlePx = with(density) { handle.toPx() }
    val stroke = with(density) { 2.dp.toPx() }
    val line = DS.sys
    BoxWithConstraints(modifier.fillMaxWidth().aspectRatio(aspect)) {
        val wPx = with(density) { maxWidth.toPx() }
        val hPx = with(density) { maxHeight.toPx() }
        Image(bitmap, contentDescription = null, contentScale = ContentScale.FillBounds, modifier = Modifier.fillMaxSize())
        if (corners.size == 4) {
            Canvas(Modifier.fillMaxSize()) {
                val path = Path().apply {
                    corners.forEachIndexed { i, p ->
                        if (i == 0) moveTo(p.x * size.width, p.y * size.height) else lineTo(p.x * size.width, p.y * size.height)
                    }
                    close()
                }
                drawPath(path, line, style = Stroke(width = stroke, join = StrokeJoin.Round))
            }
            corners.forEachIndexed { index, p ->
                fun move(dx: Float, dy: Float) {
                    val list = current.toMutableList()
                    val q = list[index]
                    list[index] = Offset((q.x + dx).coerceIn(0f, 1f), (q.y + dy).coerceIn(0f, 1f))
                    change(list)
                }
                // 読み上げでは、角を写真の真ん中へ寄せる・外へ広げるで直す。
                fun nudge(inward: Boolean) {
                    val q = current[index]
                    val step = if (inward) 0.02f else -0.02f
                    move(if (q.x < 0.5f) step else -step, if (q.y < 0.5f) step else -step)
                }
                Box(
                    Modifier
                        .offset { IntOffset((p.x * wPx - handlePx / 2).roundToInt(), (p.y * hPx - handlePx / 2).roundToInt()) }
                        .size(handle)
                        .background(DS.surface, CircleShape)
                        .border(2.dp, line, CircleShape)
                        .pointerInput(index) {
                            // 触れたところから動かす (遊びを取らない。iOS の DragGesture(minimumDistance: 0))。
                            awaitEachGesture {
                                val down = awaitFirstDown()
                                down.consume()
                                drag(down.id) { change ->
                                    val d = change.positionChange()
                                    change.consume()
                                    if (wPx > 0f && hPx > 0f) move(d.x / wPx, d.y / hPx)
                                }
                            }
                        }
                        .semantics {
                            contentDescription = "${CORNER_NAMES[index]}の角"
                            customActions = listOf(
                                CustomAccessibilityAction("内側へ寄せる") { nudge(true); true },
                                CustomAccessibilityAction("外へ広げる") { nudge(false); true }
                            )
                        }
                )
            }
        }
    }
}

private val CORNER_NAMES = listOf("左上", "右上", "右下", "左下")
