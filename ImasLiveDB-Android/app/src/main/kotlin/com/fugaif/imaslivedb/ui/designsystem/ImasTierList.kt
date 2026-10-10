package com.fugaif.imaslivedb.ui.designsystem

import android.content.ClipData
import android.content.ClipDescription
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.focusable
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.draganddrop.dragAndDropSource
import androidx.compose.foundation.draganddrop.dragAndDropTarget
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitLongPressOrCancellation
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.isOutOfBounds
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.draganddrop.DragAndDropEvent
import androidx.compose.ui.draganddrop.DragAndDropTarget
import androidx.compose.ui.draganddrop.DragAndDropTransferData
import androidx.compose.ui.draganddrop.mimeTypes
import androidx.compose.ui.draganddrop.toAndroidDragEvent
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.changedToUp
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.imasPress
import com.fugaif.imaslivedb.ui.theme.imasTheme

// =============================================================================
// ティアー表 (docs/DESIGN_SYSTEM.md §10.6)。iOS `ImasTierList.swift` の移植。
//
// ImasTierHeader   表の名前と振り分けの進み。押すと名前と段の編集を開く (鉛筆の記号つき)。
// ImasTierBoard    段を縦に積む枠。段の間は 2pt の細い隙間、外を角丸で切る。
// ImasTierRow      1 段。左に段の色の札、右に置いたものの面。何かを選んでいるときだけ、札と面が
//                  「ここへ移す」の押し先になる (選んでいないときは押せない)。
// ImasTierLabel    段の色の札。2 文字以下 (S・神) は大きく、長い名前は小さく 2 行まで。
//                  種類: 行の頭 (ROW)・移す先のボタン (BUTTON)・編集の色見本 (SWATCH)。
// ImasTierItems    段の中・未分類の並び。段の中は回り込み (FLOW)、未分類は数千件になりうるので
//                  見えている分だけ描く格子 (GRID) を呼び出し側が選べる。空のときは 1 行の文。
// ImasTierChip     表に置く 1 枚 (ジャケかアイコン + 名前 1 行)。選ぶと色の地と枠で浮く。
//                  長押しから動かすとドラッグ。ドラッグが上に来ている間は左の隙間に墨の縦線 (「この左に入る」)。
// imasTierDropTarget 札を落とせる先 (段の行・段の中の札・未分類) の Modifier。
// ImasTierDragAutoScroll ドラッグを画面の端へ寄せたときの自動スクロール (iOS はスクロール面が自分でする)。
// ImasTierMoveBar  選んでいる間だけ下に出す「〇〇をどこへ？」の帯。段のボタンを 6 列で折り返し、
//                  最後に未分類へ戻すボタン。
//
// 使わない場面: 順位 (→ ImasRankingRow)・段階の記録 (→ ImasLevelCell)。
// 段の色は段ごとのシード (`TierDef.colorSeed`) を色エンジンに通した accent / onAccent。
// =============================================================================

/** 表の名前と振り分けの進み。押すと名前と段の編集を開く。 */
@Composable
fun ImasTierHeader(title: String, subtitle: String, onEdit: () -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(DS.sp1),
        modifier = Modifier
            .fillMaxWidth()
            .imasPress(onClickLabel = "名前と段を編集", onClick = onEdit)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.sp2)) {
            ImasText(title, ImasTextRole.SECTION_TITLE)
            Icon(Icons.Filled.Edit, contentDescription = null, tint = DS.ink3, modifier = Modifier.width(15.dp))
        }
        ImasText(subtitle, ImasTextRole.META)
    }
}

/** 段を縦に積む枠。 */
@Composable
fun ImasTierBoard(content: @Composable ColumnScope.() -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(DS.sp1),
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(DS.rMD)),
        content = content
    )
}

/** 段の色の札の種類。 */
enum class ImasTierLabelStyle {
    /** 行の頭。幅 60・行の高さいっぱい・角なし (枠の角丸で切る)。 */
    ROW,

    /** 移す先のボタン。幅いっぱい・押せる高さ。 */
    BUTTON,

    /** 編集の色見本 (押すと色が変わる)。 */
    SWATCH
}

/** 段の色の札。2 文字以下は大きく、長い名前は小さくして 2 行まで。 */
@Composable
fun ImasTierLabel(label: String, seed: String?, style: ImasTierLabelStyle, modifier: Modifier = Modifier) {
    val theme = imasTheme(seed = seed, brand = null)
    val (large, small) = when (style) {
        ImasTierLabelStyle.ROW -> 24.sp to 14.sp
        ImasTierLabelStyle.BUTTON -> 18.sp to 11.sp
        ImasTierLabelStyle.SWATCH -> 16.sp to 10.sp
    }
    val text = @Composable {
        ImasFitText(
            label,
            style = ImasType.text(if (label.length <= 2) large else small, FontWeight.Black),
            color = theme.onAccent,
            textAlign = TextAlign.Center,
            maxLines = 2,
            minScale = 0.6f
        )
    }
    when (style) {
        ImasTierLabelStyle.ROW -> Box(
            modifier.width(60.dp).fillMaxHeight().background(theme.accent).padding(horizontal = DS.sp2),
            contentAlignment = Alignment.Center
        ) { text() }
        ImasTierLabelStyle.BUTTON -> Box(
            modifier
                .fillMaxWidth()
                .heightIn(min = DS.Size.touch)
                .clip(RoundedCornerShape(DS.rSM))
                .background(theme.accent)
                .padding(horizontal = DS.sp1),
            contentAlignment = Alignment.Center
        ) { text() }
        ImasTierLabelStyle.SWATCH -> Box(
            modifier.width(48.dp).heightIn(min = 34.dp).clip(RoundedCornerShape(DS.rXS)).background(theme.accent),
            contentAlignment = Alignment.Center
        ) { text() }
    }
}

/**
 * 1 段。札と面は [isTarget] のときだけ「ここへ移す」の押し先になる。
 *
 * @param accessibilityLabel 札の読み上げ (「S 3件」など)。
 */
@Composable
fun ImasTierRow(
    label: String,
    seed: String?,
    isTarget: Boolean,
    accessibilityLabel: String,
    onMoveHere: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit
) {
    // 札を行の高さいっぱいに伸ばす (スクロールの中では fillMaxHeight だけでは伸びないので、
    // 行の高さを中身の高さに決めてから札に満たさせる。iOS の fixedSize(vertical:) と同じ)。
    Row(modifier.fillMaxWidth().height(IntrinsicSize.Min), verticalAlignment = Alignment.Top) {
        ImasTierLabel(
            label, seed, ImasTierLabelStyle.ROW,
            modifier = Modifier
                .clickable(enabled = isTarget, onClick = onMoveHere)
                .semantics {
                    contentDescription = accessibilityLabel
                    if (isTarget) stateDescription = "選んだものをここへ移す"
                }
        )
        Box(
            Modifier
                .weight(1f)
                .heightIn(min = 72.dp)
                .background(DS.surface)
                .clickable(enabled = isTarget, onClick = onMoveHere),
            contentAlignment = Alignment.TopStart,
            content = content
        )
    }
}

/** 段の中・未分類の並びの並べ方。 */
enum class ImasTierItemsLayout {
    /** 回り込み。段の中 (数が少ない)。 */
    FLOW,

    /** 見えている分だけ描く格子。未分類など、数千件になりうる並びで使う。 */
    GRID
}

/** 段の中・未分類の並び。空のときは 1 行の文 ([emptyText]、null なら何も出さない)。 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun <T : Any> ImasTierItems(
    ids: List<T>,
    layout: ImasTierItemsLayout = ImasTierItemsLayout.FLOW,
    emptyText: String? = null,
    modifier: Modifier = Modifier,
    cell: @Composable (T) -> Unit
) {
    if (ids.isEmpty()) {
        // 幅いっぱいにする (未分類の空の面を押して「未分類へ戻す」ときの押し先が文字の幅だけにならないように)。
        ImasText(emptyText ?: "", ImasTextRole.META, modifier = modifier.fillMaxWidth().padding(DS.sp4))
        return
    }
    when (layout) {
        ImasTierItemsLayout.FLOW -> FlowRow(
            modifier = modifier.fillMaxWidth().padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) { ids.forEach { cell(it) } }
        // 縦スクロールの画面の中に置くので高さの上限が要る (上限が無いと高さ無限で測られて落ちる)。
        // 上限の中は格子が自分でスクロールし、見えている分だけ描く。
        ImasTierItemsLayout.GRID -> LazyVerticalGrid(
            columns = GridCells.Adaptive(66.dp),
            modifier = modifier.fillMaxWidth().heightIn(max = 420.dp).padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) { items(ids, key = { it }) { cell(it) } }
    }
}

/** [ImasTierChip] の `media` に渡す大きさ (ジャケ・アイコン 52)。 */
val ImasTierChipMediaSize: Dp = 52.dp

/**
 * 表に置く 1 枚。[media] は渡された大きさ ([ImasTierChipMediaSize]) のジャケかアイコン。
 *
 * @param accessibilityTitle 読み上げの名前。項目が読めなかったときの「不明」など、表示と変えたいときだけ渡す。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ImasTierChip(
    title: String,
    seed: String?,
    brand: String?,
    isSelected: Boolean,
    modifier: Modifier = Modifier,
    accessibilityTitle: String? = null,
    onClick: (() -> Unit)? = null,
    onLongClick: (() -> Unit)? = null,
    dragData: String? = null,
    showsInsertMark: Boolean = false,
    media: @Composable (Dp) -> Unit
) {
    val theme = imasTheme(seed, brand)
    val shape = RoundedCornerShape(DS.rSM)
    val scaleValue by animateFloatAsState(if (isSelected) 1.06f else 1f, label = "tierChipScale")
    val markAlpha by animateFloatAsState(if (showsInsertMark) 1f else 0f, label = "tierChipInsertMark")
    val markColor = DS.ink
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(3.dp),
        modifier = modifier
            // 「この左に入る」の印。並びの隙間 (6dp) の真ん中に 3dp の線 (札の外に描くので切り抜きより前)。
            .drawWithContent {
                drawContent()
                if (markAlpha > 0f) {
                    val w = 3.dp.toPx()
                    val inset = DS.sp1.toPx()
                    drawRoundRect(
                        color = markColor, alpha = markAlpha,
                        topLeft = Offset(-4.5.dp.toPx(), inset),
                        size = Size(w, size.height - inset * 2),
                        cornerRadius = CornerRadius(w / 2)
                    )
                }
            }
            .scale(scaleValue)
            .clip(shape)
            .background(if (isSelected) theme.tint else Color.Transparent)
            // 0.dp の枠は 1px の線として描かれるので、選んでいないときは枠ごと付けない。
            .then(if (isSelected) Modifier.border(2.5.dp, theme.accent, shape) else Modifier)
            .then(
                when {
                    dragData != null -> Modifier.tierChipDragGestures(dragData, onClick, onLongClick)
                    onClick != null -> Modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick)
                    else -> Modifier
                }
            )
            .padding(3.dp)
            .semantics {
                contentDescription = accessibilityTitle ?: title
                selected = isSelected
            }
    ) {
        media(ImasTierChipMediaSize)
        Text(
            title, style = ImasType.text(10.sp), color = DS.ink2, maxLines = 1,
            overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 60.dp)
        )
    }
}

/** ドラッグで運ぶ札の印 (他のアプリから運ばれた文字と見分ける)。 */
private const val TIER_DRAG_LABEL = "imas_tier_item"

/**
 * 札のタップ・長押し・ドラッグ。タップ = [onClick]、長押しのまま動かさずに離す = [onLongClick]、
 * 長押しから動かす = [dragData] を運ぶドラッグ (iOS の長押しメニュー + つかんで運ぶに合わせる)。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Modifier.tierChipDragGestures(
    dragData: String,
    onClick: (() -> Unit)?,
    onLongClick: (() -> Unit)?
): Modifier {
    val haptic = LocalHapticFeedback.current
    // 手の受け口は一度だけ組まれるので、最新の値を読む。
    val data by rememberUpdatedState(dragData)
    val click by rememberUpdatedState(onClick)
    val longClick by rememberUpdatedState(onLongClick)
    return this
        // combinedClickable が付けていた読み上げ (1 つにまとめる・ボタン) とキーボードの決定を自分で付ける。
        .semantics(mergeDescendants = true) {
            role = Role.Button
            onClick?.let { c -> onClick { c(); true } }
            onLongClick?.let { l -> onLongClick { l(); true } }
        }
        .onKeyEvent { e ->
            val enter = e.key == Key.Enter || e.key == Key.NumPadEnter || e.key == Key.DirectionCenter
            if (enter && e.type == KeyEventType.KeyUp) click?.invoke()
            enter
        }
        .focusable()
        .dragAndDropSource {
            awaitEachGesture {
                val down = awaitFirstDown(requireUnconsumed = false)
                val longPress = awaitLongPressOrCancellation(down.id)
                if (longPress == null) {
                    // 長押しになる前に離した = タップ (スクロールで動いたときは何もしない)。
                    val up = currentEvent.changes.firstOrNull { it.id == down.id }
                    if (up != null && up.changedToUp()) {
                        up.consume()
                        click?.invoke()
                    }
                    return@awaitEachGesture
                }
                haptic.performHapticFeedback(HapticFeedbackType.LongPress)
                while (true) {
                    val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id } ?: break
                    if (change.changedToUpIgnoreConsumed()) {
                        change.consume()
                        // 札の上で離したときだけ (通知を引いた等で触れが取り消されたときは開かない)。
                        if (!change.isOutOfBounds(size, extendedTouchPadding)) longClick?.invoke()
                        break
                    }
                    change.consume()
                    if ((change.position - longPress.position).getDistance() > viewConfiguration.touchSlop) {
                        startTransfer(DragAndDropTransferData(ClipData.newPlainText(TIER_DRAG_LABEL, data)))
                        break
                    }
                }
            }
        }
}

/**
 * ドラッグを画面の上端・下端へ寄せたときの自動スクロール (iOS はスクロール面が自分でする)。
 * [rememberImasTierDragAutoScroll] で作り、スクロール面に [imasTierDragAutoScrollArea]、
 * 落とし先に [imasTierDropTarget] の `autoScroll` として渡す。
 */
class ImasTierDragAutoScroll internal constructor(private val edgePx: Float, private val maxStepPx: Float) {
    internal var bounds by mutableStateOf(Rect.Zero)
    internal var step by mutableFloatStateOf(0f)

    /** ドラッグが動いた (y は画面の座標)。端に近いほど速く送る。 */
    internal fun onMoved(y: Float) {
        step = when {
            bounds == Rect.Zero -> 0f
            y < bounds.top + edgePx -> -maxStepPx * ((bounds.top + edgePx - y) / edgePx).coerceIn(0f, 1f)
            y > bounds.bottom - edgePx -> maxStepPx * ((y - (bounds.bottom - edgePx)) / edgePx).coerceIn(0f, 1f)
            else -> 0f
        }
    }

    internal fun stop() { step = 0f }
}

@Composable
fun rememberImasTierDragAutoScroll(scrollState: ScrollState): ImasTierDragAutoScroll {
    val density = LocalDensity.current
    val auto = remember(density) { with(density) { ImasTierDragAutoScroll(72.dp.toPx(), 18.dp.toPx()) } }
    LaunchedEffect(auto, scrollState) {
        while (true) {
            withFrameNanos { }
            val step = auto.step
            if (step != 0f) scrollState.scrollBy(step)
        }
    }
    return auto
}

/** スクロール面に付ける (面の位置を覚え、段の隙間の上でも端への寄せを拾う)。落としても何もしない。 */
@Composable
fun Modifier.imasTierDragAutoScrollArea(auto: ImasTierDragAutoScroll): Modifier =
    onGloballyPositioned { auto.bounds = it.boundsInRoot() }
        .imasTierDropTarget(onDrop = { false }, autoScroll = auto)

/**
 * 札を落とせる先 (段の行・段の中の札・未分類)。[onDrop] には運ばれた札の id が来る (受けたら true)。
 * [onHover] はドラッグが上に来た / 離れたとき (札の「この左に入る」の印に使う)。
 * [autoScroll] を渡すと、上で動いたときに画面の端への寄せを伝える。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun Modifier.imasTierDropTarget(
    onDrop: (String) -> Boolean,
    onHover: ((Boolean) -> Unit)? = null,
    autoScroll: ImasTierDragAutoScroll? = null
): Modifier {
    val drop by rememberUpdatedState(onDrop)
    val hover by rememberUpdatedState(onHover)
    val auto by rememberUpdatedState(autoScroll)
    val target = remember {
        object : DragAndDropTarget {
            override fun onMoved(event: DragAndDropEvent) { auto?.onMoved(event.toAndroidDragEvent().y) }

            override fun onDrop(event: DragAndDropEvent): Boolean {
                hover?.invoke(false)
                auto?.stop()
                val clip = event.toAndroidDragEvent().clipData ?: return false
                if (clip.itemCount == 0 || clip.description?.label != TIER_DRAG_LABEL) return false
                val id = clip.getItemAt(0).text?.toString() ?: return false
                return drop(id)
            }

            override fun onEntered(event: DragAndDropEvent) { hover?.invoke(true) }
            override fun onExited(event: DragAndDropEvent) { hover?.invoke(false) }
            override fun onEnded(event: DragAndDropEvent) {
                hover?.invoke(false)
                auto?.stop()
            }
        }
    }
    return dragAndDropTarget(
        shouldStartDragAndDrop = { it.mimeTypes().contains(ClipDescription.MIMETYPE_TEXT_PLAIN) },
        target = target
    )
}

/** 選んでいる間だけ下に出す「〇〇をどこへ？」の帯。 */
@Composable
fun ImasTierMoveBar(
    title: String,
    tiers: List<ImasTierSpec>,
    onCancel: () -> Unit,
    onMove: (String) -> Unit,
    onUnplace: () -> Unit
) {
    Column(
        verticalArrangement = Arrangement.spacedBy(DS.sp3),
        modifier = Modifier.fillMaxWidth().background(DS.surface).padding(horizontal = DS.sp5, vertical = DS.sp3)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                title, style = ImasType.text(15.sp, FontWeight.SemiBold), color = DS.ink,
                maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
            )
            Spacer(Modifier.width(DS.sp2))
            Text(
                "やめる", style = ImasType.text(15.sp), color = DS.ink2,
                modifier = Modifier.imasPress(onClickLabel = "やめる", onClick = onCancel).padding(DS.sp1)
            )
        }
        // 段は最大 10。6 列で折り返す (1 行に詰めると押せない幅になる)。
        val columns = minOf(6, tiers.size + 1)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
            modifier = Modifier.fillMaxWidth().heightIn(min = DS.Size.touch).height((DS.Size.touch + 6.dp) * (tiers.size / columns + 1))
        ) {
            items(tiers) { tier ->
                Box(modifier = Modifier.imasPress(onClick = { onMove(tier.id) })) {
                    ImasTierLabel(label = tier.label, seed = tier.seed, style = ImasTierLabelStyle.BUTTON)
                }
            }
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = DS.Size.touch)
                        .clip(RoundedCornerShape(DS.rSM))
                        .background(DS.fill)
                        .imasPress(onClickLabel = "未分類へ", onClick = onUnplace),
                    contentAlignment = Alignment.Center
                ) {
                    Icon(Icons.Filled.Inbox, contentDescription = "未分類へ", tint = DS.ink2, modifier = Modifier.width(18.dp))
                }
            }
        }
    }
}

/** [ImasTierMoveBar] に渡す段の軽い写し (id・名前・色の種だけ)。 */
data class ImasTierSpec(val id: String, val label: String, val seed: String?)
