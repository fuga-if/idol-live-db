package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animate
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.outlined.Notes
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.ConfirmationNumber
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChangeIgnoreConsumed
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasBackdrop
import com.fugaif.imaslivedb.ui.theme.ImasMotion
import com.fugaif.imaslivedb.ui.theme.ImasType
import com.fugaif.imaslivedb.ui.theme.LocalImasBackdrop
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.roundToInt

// =============================================================================
// 指の操作 (docs/DESIGN_SYSTEM.md §1-6・§8.5)。iOS `ImasGestures.swift` の移植。
//
// ImasSwipe (iOS `.imasSwipe`)    行を引いて操作する。右に引く (先頭側) = 記録を付ける (参加・回収・予定)、
//                                 左に引く (末尾側) = 手元に置く (お気に入り・メモ・予想・削除)。
//                                 色と記号は操作の種類 (`ImasSwipeKind`) が決める。画面で色を書かない。
// Modifier.imasTabSwipe            中身を横に払ってタブを替える (`ImasTabs` と組む)。
//
// 長押しのメニューは `Copyable` (行の長押し) が受け持つ。
// =============================================================================

// MARK: - 行を引く

/** 行を引いたときに出る操作の種類 (iOS `ImasSwipeKind`)。色と記号を決める。 */
enum class ImasSwipeKind {
    /** 参加した (朱。判子を押す)。 */
    ATTEND,

    /** 参加予定にする (墨。チケットを手に入れる)。 */
    PLAN,

    /** お気に入り (金)。 */
    FAVORITE,

    /** メモ (灰)。 */
    MEMO,

    /** 予想に入れる (墨)。 */
    PREDICT,

    /** 取り消す (薄い灰)。 */
    UNDO,

    /** 削除 (朱)。 */
    DELETE;

    /** 操作の地の色。 */
    val tint: Color
        @Composable get() = when (this) {
            ATTEND -> DS.stamp
            PLAN, PREDICT -> DS.sys
            FAVORITE -> DS.favorite
            MEMO -> DS.ink2
            UNDO -> DS.ink3
            DELETE -> DS.danger
        }

    /** 操作の記号。 */
    val icon: ImageVector
        get() = when (this) {
            ATTEND -> Icons.Filled.Verified
            PLAN -> Icons.Filled.ConfirmationNumber
            FAVORITE -> Icons.Filled.Star
            MEMO -> Icons.AutoMirrored.Outlined.Notes
            PREDICT -> Icons.Filled.AutoAwesome
            UNDO -> Icons.AutoMirrored.Filled.Undo
            DELETE -> Icons.Filled.Delete
        }
}

/**
 * 行を引いたときの操作 1 つ (iOS `ImasSwipeAction`)。
 *
 * @param showsIcon 記号を出すか。操作が 3 つ以上並ぶと幅が足りず記号だけが残って読めなくなるので、
 *   選択肢を並べるとき (現地 / 配信 / LV) は文字だけにする。
 */
@Immutable
class ImasSwipeAction(
    val kind: ImasSwipeKind,
    val title: String,
    val id: String = title,
    val showsIcon: Boolean = true,
    val action: () -> Unit
)

/** 操作のボタン 1 つの幅の下限 (iOS の行の操作と同じ程度)。 */
private val SwipeButtonMinWidth = 74.dp

/**
 * 行を引いて操作する (iOS `.imasSwipe(leading:trailing:allowsFullSwipe:)`)。
 *
 * 引くと行の下から操作のボタンが出る。半分より多く引いて離すと開いたまま止まり、ボタンを押すと実行して閉じる。
 * 操作が 1 つだけの側は、引き切る (行の幅の半分を超えて離す) とその場で実行する ([allowsFullSwipe])。
 * 開いている間に行を押すと閉じる。読み上げでは行の「操作」から選べる (行の部品が自分の要素に付ける。[LocalImasSwipeActions])。
 *
 * Android では画面の右端から引き始めると OS の「戻る」に取られる。末尾側の操作は行の中ほどから引く
 * (記録を付ける主な操作は先頭側に置く。iOS と同じ割り当て)。
 *
 * @param leading 右に引くと出る (記録を付ける)。1 つだけなら引き切りで実行される。
 * @param trailing 左に引くと出る (手元に置く・削除)。
 * @param background 引いている間の行の地。null なら今の地 (紙面かフォームの面)。
 */
@Composable
fun ImasSwipe(
    modifier: Modifier = Modifier,
    leading: List<ImasSwipeAction> = emptyList(),
    trailing: List<ImasSwipeAction> = emptyList(),
    allowsFullSwipe: Boolean = true,
    background: Color? = null,
    content: @Composable () -> Unit
) {
    if (leading.isEmpty() && trailing.isEmpty()) {
        Box(modifier) { content() }
        return
    }
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val haptics = rememberImasHaptics()
    var offset by remember { mutableFloatStateOf(0f) }
    var rowWidth by remember { mutableIntStateOf(0) }
    var leadingWidth by remember { mutableIntStateOf(0) }
    var trailingWidth by remember { mutableIntStateOf(0) }
    val fullLeading = allowsFullSwipe && leading.size == 1
    val fullTrailing = allowsFullSwipe && trailing.size == 1
    val latestLeading by rememberUpdatedState(leading)
    val latestTrailing by rememberUpdatedState(trailing)
    var pastFull by remember { mutableStateOf(false) }
    val fullThreshold = rowWidth * 0.5f

    val maxOffset = when {
        leading.isEmpty() -> 0f
        fullLeading -> rowWidth.toFloat()
        else -> leadingWidth * 1.15f
    }
    val minOffset = when {
        trailing.isEmpty() -> 0f
        fullTrailing -> -rowWidth.toFloat()
        else -> -trailingWidth * 1.15f
    }

    suspend fun settle(target: Float) {
        animate(initialValue = offset, targetValue = target, animationSpec = ImasMotion.standard()) { v, _ -> offset = v }
    }

    fun close() {
        scope.launch { settle(0f) }
    }

    fun perform(action: ImasSwipeAction) {
        action.action()
        close()
    }

    val dragState = rememberDraggableState { delta ->
        val next = (offset + delta).coerceIn(minOffset, maxOffset)
        offset = next
        val beyond = (fullLeading && next > fullThreshold) || (fullTrailing && next < -fullThreshold)
        if (beyond != pastFull) {
            pastFull = beyond
            if (beyond) haptics.impactMedium()
        }
    }
    val settleVelocity = with(density) { 800.dp.toPx() }
    val paint = background ?: if (LocalImasBackdrop.current == ImasBackdrop.PAPER) DS.paper else DS.surface

    // 読み上げの操作は行の部品 (ImasRow・ImasStubRow) が自分の読み上げの要素に付ける
    // (押せる行は行の要素に読み上げが集まるので、外側の箱に付けても選べない)。
    val spokenActions = remember(leading, trailing) {
        (leading + trailing).map { a -> CustomAccessibilityAction(a.title) { a.action(); true } }
    }
    Box(
        modifier
            .clipToBounds()
            .onSizeChanged { rowWidth = it.width }
    ) {
        // 行の下の操作のボタン。引いた側だけを見せる (行の高さいっぱい)。
        Box(Modifier.matchParentSize()) {
            if (leading.isNotEmpty()) {
                SwipeButtons(
                    actions = leading,
                    revealed = offset.coerceAtLeast(0f),
                    visible = offset > 0f,
                    stretches = fullLeading,
                    modifier = Modifier.align(Alignment.CenterStart),
                    onMeasured = { leadingWidth = it },
                    onTap = ::perform
                )
            }
            if (trailing.isNotEmpty()) {
                SwipeButtons(
                    actions = trailing,
                    revealed = (-offset).coerceAtLeast(0f),
                    visible = offset < 0f,
                    stretches = fullTrailing,
                    modifier = Modifier.align(Alignment.CenterEnd),
                    onMeasured = { trailingWidth = it },
                    onTap = ::perform
                )
            }
        }
        CompositionLocalProvider(LocalImasSwipeActions provides spokenActions) {
        Box(
            Modifier
                .offset { IntOffset(offset.roundToInt(), 0) }
                .then(if (offset != 0f) Modifier.background(paint) else Modifier)
                .draggable(
                    state = dragState,
                    orientation = Orientation.Horizontal,
                    onDragStopped = { velocity ->
                        val v = offset
                        pastFull = false
                        when {
                            v > 0f && fullLeading && v > fullThreshold -> perform(latestLeading.first())
                            v < 0f && fullTrailing && v < -fullThreshold -> perform(latestTrailing.first())
                            v > 0f && velocity > -settleVelocity && (v > leadingWidth / 2f || velocity > settleVelocity) ->
                                settle(leadingWidth.toFloat())
                            v < 0f && velocity < settleVelocity && (v < -trailingWidth / 2f || velocity < -settleVelocity) ->
                                settle(-trailingWidth.toFloat())
                            else -> settle(0f)
                        }
                    }
                )
        ) {
            content()
            if (offset != 0f) {
                // 開いている間に行を押したら閉じる (行の操作は走らせない)。
                Box(
                    Modifier
                        .matchParentSize()
                        .clearAndSetSemantics { }
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { close() }
                )
            }
        }
        }
    }
}

/**
 * [ImasSwipe] の中の行が読み上げの操作として持つもの。行の部品 (ImasRow・ImasStubRow) が自分の要素に付ける。
 * 部品の外で組んだ行を [ImasSwipe] で包むときは、行の要素に `Modifier.imasSwipeActions()` を付ける。
 */
val LocalImasSwipeActions = staticCompositionLocalOf<List<CustomAccessibilityAction>> { emptyList() }

/** [ImasSwipe] の操作を、この要素の読み上げの操作にする (行を引けない人も同じ操作を選べる)。 */
@Composable
fun Modifier.imasSwipeActions(): Modifier {
    val actions = LocalImasSwipeActions.current
    return if (actions.isEmpty()) this else this.semantics { customActions = actions }
}

/** 操作のボタンを並べる。1 つだけの側は引いた幅いっぱいに伸びる (引き切りの手応え)。 */
@Composable
private fun SwipeButtons(
    actions: List<ImasSwipeAction>,
    revealed: Float,
    visible: Boolean,
    stretches: Boolean,
    modifier: Modifier,
    onMeasured: (Int) -> Unit,
    onTap: (ImasSwipeAction) -> Unit
) {
    val density = LocalDensity.current
    // 開いたまま止める幅 (伸ばす前のボタンの幅) を測る。見えない。
    Row(
        modifier
            .fillMaxHeight()
            .graphicsLayer { alpha = 0f }
            .clearAndSetSemantics { }
            .onSizeChanged { onMeasured(it.width) }
    ) {
        actions.forEach { SwipeButton(it, Modifier.fillMaxHeight(), enabled = false) {} }
    }
    if (!visible) return
    Row(modifier.fillMaxHeight()) {
        actions.forEach { action ->
            val stretched = if (stretches) {
                Modifier.width(with(density) { max(revealed, SwipeButtonMinWidth.toPx()).toDp() })
            } else {
                Modifier
            }
            SwipeButton(action, stretched.fillMaxHeight(), enabled = true) { onTap(action) }
        }
    }
}

@Composable
private fun SwipeButton(action: ImasSwipeAction, modifier: Modifier, enabled: Boolean, onClick: () -> Unit) {
    val tint = action.kind.tint
    val fg = imasTheme(tint).onAccent
    Box(
        modifier
            .widthIn(min = SwipeButtonMinWidth)
            .background(tint)
            .clearAndSetSemantics { }
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = DS.Space.gap),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            if (action.showsIcon) {
                Icon(action.kind.icon, contentDescription = null, tint = fg, modifier = Modifier.size(with(LocalDensity.current) { 18.sp.toDp() }))
            }
            Text(action.title, style = ImasType.text(13.sp, FontWeight.SemiBold), color = fg, maxLines = 1)
        }
    }
}

// MARK: - 横に払ってタブを替える

/**
 * 中身を横に払って、`ImasTabs` の選択を隣へ移す (iOS `.imasTabSwipe(selection:options:)`)。
 * 縦のスクロールは邪魔しない: 横の動きが縦の倍以上あり、40dp 以上動いたときだけ替える。
 * 中の部品が指の動きを使った (横に流れるチップの帯・行を引く操作) ときは替えない。
 */
fun <T> Modifier.imasTabSwipe(selection: T, options: List<T>, onSelect: (T) -> Unit): Modifier =
    pointerInput(selection, options) {
        val trigger = 40.dp.toPx()
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Final)
            var dx = 0f
            var dy = 0f
            var usedByChild = false
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Final)
                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                if (change.isConsumed) usedByChild = true
                val delta = change.positionChangeIgnoreConsumed()
                dx += delta.x
                dy += delta.y
                if (!change.pressed) break
            }
            if (usedByChild || abs(dx) <= trigger || abs(dx) <= abs(dy) * 2) return@awaitEachGesture
            val index = options.indexOf(selection)
            if (index < 0) return@awaitEachGesture
            val next = if (dx < 0) index + 1 else index - 1
            if (next in options.indices) onSelect(options[next])
        }
    }
