package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroidSize
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateRotation
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt
import kotlin.math.sin

// =============================================================================
// 名刺の素材 (表に重ねる好きな画像・背景を切り抜いた透過画像) の部品。iOS `ImasStickers.swift` と対。
//
// ImasStickerPlacement     素材を紙に対する割合 (中心・幅・傾き) で置く層。名刺の表 ([ImasMeishiStickerLayer]) と
//                          置く画面 ([ImasStickerEditLayer]) が同じ置き方で描く。
// ImasStickerThumb         素材 1 枚の小さな札 (透過が分かるように市松の地)。
// ImasTransparencyBackdrop 透過の地 (淡い市松)。切り抜きの見本の下に敷く。
// ImasStickerPreview       整える画面の見本 (市松の地に画像 1 枚)。
// ImasStickerEditLayer     名刺の上で素材を指で置く層。引いて動かす・つまんで大きさ・2 本指で傾ける。
//                          置き方は紙に対する割合で受け渡し、範囲に収めるのは呼ぶ側 (コアの `cardStickerClamp`)。
// imasStickerFrame         素材の見本・置く画面の名刺の枠 (内側の角丸で切る)。
// =============================================================================

/**
 * 素材を置く層。親いっぱいに広がり、素材は紙 (この層) の大きさに対する割合で置く。素材の幅 = 層の幅 × `width`、
 * 中心は (x × 幅, y × 高さ)、中心のまわりに傾ける。はみ出した分を切るのは置いた側。
 */
@Composable
fun ImasStickerPlacement(
    stickers: List<ImasMeishiSticker>,
    modifier: Modifier = Modifier,
    item: @Composable (ImasMeishiSticker) -> Unit
) {
    Layout(
        content = {
            stickers.forEach { sticker ->
                key(sticker.id) {
                    Box(Modifier.graphicsLayer { rotationZ = sticker.rotationDegrees }) { item(sticker) }
                }
            }
        },
        modifier = modifier
    ) { measurables, constraints ->
        val w = constraints.maxWidth
        val h = constraints.maxHeight
        val placeables = measurables.mapIndexed { i, m ->
            val side = (w * stickers[i].width).roundToInt().coerceAtLeast(1)
            m.measure(Constraints(minWidth = side, maxWidth = side, minHeight = 0, maxHeight = Constraints.Infinity))
        }
        layout(w, h) {
            placeables.forEachIndexed { i, p ->
                p.place(
                    (w * stickers[i].x - p.width / 2f).roundToInt(),
                    (h * stickers[i].y - p.height / 2f).roundToInt()
                )
            }
        }
    }
}

/** 透過の地 (市松)。透過の画像の下に敷いて、どこが抜けているかを見せる。 */
@Composable
fun ImasTransparencyBackdrop(modifier: Modifier = Modifier, cell: Dp = 8.dp) {
    val light = DS.surface
    val dark = DS.surface2
    Canvas(modifier) {
        drawRect(light)
        val side = cell.toPx()
        val cols = kotlin.math.ceil(size.width / side).toInt()
        val rows = kotlin.math.ceil(size.height / side).toInt()
        for (r in 0 until rows) {
            for (c in 0 until cols) {
                if ((r + c) % 2 == 0) drawRect(dark, topLeft = Offset(c * side, r * side), size = Size(side, side))
            }
        }
    }
}

/** 素材 1 枚の札。選んだ札は墨の縁。 */
@Composable
fun ImasStickerThumb(url: String, modifier: Modifier = Modifier, isSelected: Boolean = false, side: Dp = 56.dp) {
    val shape = RoundedCornerShape(DS.rTag)
    Box(
        modifier
            .size(side)
            .clip(shape)
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) DS.ink else DS.line, shape),
        contentAlignment = Alignment.Center
    ) {
        ImasTransparencyBackdrop(Modifier.size(side), cell = 6.dp)
        ImasMeishiPictureView(
            ImasMeishiPicture.Url(url), Modifier.size(side).padding(DS.Space.gapTight),
            contentScale = ContentScale.Fit, fallback = {}
        )
    }
}

/** 整える画面の見本 (市松の地に画像 1 枚。切り抜きの前後を見比べられる)。 */
@Composable
fun ImasStickerPreview(picture: ImasMeishiPicture, label: String, modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxWidth().imasStickerFrame().semantics { contentDescription = label },
        contentAlignment = Alignment.Center
    ) {
        ImasTransparencyBackdrop(Modifier.matchParentSize())
        ImasMeishiPictureView(
            picture, Modifier.fillMaxWidth().heightIn(max = 320.dp).padding(DS.Space.gap),
            contentScale = ContentScale.Fit, fallback = {}
        )
    }
}

/** 素材の見本・置く画面の名刺の枠 (内側の角丸で切る)。 */
fun Modifier.imasStickerFrame(): Modifier = clip(RoundedCornerShape(DS.rInner))

/**
 * 名刺の上で素材を置く層。親 (名刺の紙を描いている大きさ) いっぱいに広がる。素材を押すと選び、素材を引くと
 * (選んでいなければその素材を選んで) 動かせる。2 本指のつまみ・ひねりは選んでいる素材に効く。何も無いところを
 * 押すと選び終わる。置き直した素材は指を離したときに [onChange] で渡す (範囲に収めるのは呼ぶ側)。
 */
@Composable
fun ImasStickerEditLayer(
    stickers: List<ImasMeishiSticker>,
    selection: String?,
    onSelect: (String?) -> Unit,
    onChange: (ImasMeishiSticker) -> Unit,
    modifier: Modifier = Modifier
) {
    var live by remember { mutableStateOf<ImasMeishiSticker?>(null) }
    var layerSize by remember { mutableStateOf(IntSize.Zero) }
    // 素材ごとの傾ける前の大きさ (押した素材を探すのに使う)。
    val sizes = remember { mutableStateMapOf<String, IntSize>() }
    val shown = stickers.map { base -> live?.takeIf { it.id == base.id } ?: base }
    val shownNow by rememberUpdatedState(shown)
    val selectionNow by rememberUpdatedState(selection)
    val onSelectNow by rememberUpdatedState(onSelect)
    val onChangeNow by rememberUpdatedState(onChange)
    val haptics = rememberImasHaptics()
    val ink = DS.ink
    val slop = LocalViewConfiguration.current.touchSlop
    val dash = remember { PathEffect.dashPathEffect(floatArrayOf(10f, 8f)) }

    fun hit(point: Offset): String? {
        val w = layerSize.width.toFloat()
        val h = layerSize.height.toFloat()
        return shownNow.lastOrNull { s ->
            val box = sizes[s.id] ?: return@lastOrNull false
            val rad = -s.rotationDegrees * PI.toFloat() / 180f
            val dx = point.x - w * s.x
            val dy = point.y - h * s.y
            val lx = dx * cos(rad) - dy * sin(rad)
            val ly = dx * sin(rad) + dy * cos(rad)
            abs(lx) <= box.width / 2f && abs(ly) <= box.height / 2f
        }?.id
    }

    ImasStickerPlacement(
        shown,
        modifier
            .onSizeChanged { layerSize = it }
            .pointerInput(Unit) {
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    val touched = hit(down.position)
                    if (touched != null && touched != selectionNow) {
                        haptics.selection()
                        onSelectNow(touched)
                    }
                    val target = touched ?: selectionNow
                    var pastSlop = false
                    var totalPan = Offset.Zero
                    var totalZoom = 1f
                    var totalTurn = 0f
                    var moved = false
                    var start: ImasMeishiSticker? = null
                    do {
                        val event = awaitPointerEvent(PointerEventPass.Main)
                        val canceled = event.changes.any { it.isConsumed }
                        if (canceled) break
                        val zoom = event.calculateZoom()
                        val turn = event.calculateRotation()
                        val pan = event.calculatePan()
                        var applyPan = pan
                        var applyZoom = zoom
                        var applyTurn = turn
                        if (!pastSlop) {
                            totalPan += pan
                            totalZoom *= zoom
                            totalTurn += turn
                            val spread = event.calculateCentroidSize(useCurrent = false)
                            val zoomMotion = abs(1f - totalZoom) * spread
                            val turnMotion = abs(totalTurn * PI.toFloat() / 180f * spread / 2f)
                            if (zoomMotion > slop || turnMotion > slop || totalPan.getDistance() > slop) {
                                pastSlop = true
                                applyPan = totalPan
                                applyZoom = totalZoom
                                applyTurn = totalTurn
                            }
                        }
                        if (pastSlop && target != null) {
                            val base = start ?: shownNow.firstOrNull { it.id == target }?.also { start = it }
                            val current = live?.takeIf { it.id == target } ?: base
                            if (current != null && layerSize.width > 0 && layerSize.height > 0) {
                                live = current.copy(
                                    // 引いて動かすのは押した素材だけ (つまみ・ひねりは選んでいる素材)。
                                    x = if (touched != null) current.x + applyPan.x / layerSize.width else current.x,
                                    y = if (touched != null) current.y + applyPan.y / layerSize.height else current.y,
                                    width = current.width * applyZoom,
                                    rotationDegrees = current.rotationDegrees + applyTurn
                                )
                                moved = true
                            }
                            event.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    } while (event.changes.any { it.pressed })
                    val result = live
                    live = null
                    if (moved && result != null) onChangeNow(result)
                    else if (touched == null && !pastSlop) onSelectNow(null)
                }
            }
            .semantics { contentDescription = "素材を置く名刺" }
    ) { s ->
        Box(
            Modifier
                .onSizeChanged { sizes[s.id] = it }
                .drawWithContent {
                    drawContent()
                    if (selection == s.id) {
                        drawRect(ink, style = Stroke(width = 1.5.dp.toPx(), pathEffect = dash))
                    }
                }
                .semantics {
                    contentDescription = "素材"
                    role = Role.Button
                    selected = selection == s.id
                    onClick { onSelect(s.id); true }
                }
        ) {
            ImasMeishiPictureView(s.picture, contentScale = ContentScale.FillWidth, fallback = {})
        }
    }
}
