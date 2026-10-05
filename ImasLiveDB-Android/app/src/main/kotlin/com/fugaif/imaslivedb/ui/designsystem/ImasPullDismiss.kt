package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/**
 * 画面を下へスワイプして畳む (歌詞プレイヤー。iOS `PullsDownToDismiss` / `OverscrollDismiss` と対)。
 * 頭と下の操作は [imasPullDownHandle] でつまみ、歌詞の一覧は一番上からさらに引き下げると [imasPullDownScroll] が拾う。
 * 画面ごと [imasPullOffset] で指に付いて下がり、引き切るか勢いよく払うと閉じる。
 */
@Stable
class ImasPullDismissState internal constructor(
    private val scope: CoroutineScope,
    internal val thresholdPx: Float,
    private val onDismiss: () -> Unit,
) {
    internal val offset = Animatable(0f)
    val offsetPx: Float get() = offset.value

    internal fun dragBy(dy: Float) {
        scope.launch { offset.snapTo((offset.value + dy).coerceAtLeast(0f)) }
    }

    internal fun release(velocityY: Float) {
        if (offset.value > thresholdPx || (offset.value > thresholdPx / 4 && velocityY > 2400f)) {
            onDismiss()
        } else {
            scope.launch { offset.animateTo(0f, spring()) }
        }
    }
}

@Composable
fun rememberImasPullDismissState(onDismiss: () -> Unit): ImasPullDismissState {
    val scope = rememberCoroutineScope()
    val threshold = with(LocalDensity.current) { 140.dp.toPx() }
    val latest by rememberUpdatedState(onDismiss)
    return remember { ImasPullDismissState(scope, threshold) { latest() } }
}

/** 画面ごと下へずらす (引いている間)。 */
fun Modifier.imasPullOffset(state: ImasPullDismissState): Modifier =
    offset { IntOffset(0, state.offsetPx.roundToInt()) }

/** 頭・下の操作をつまんで下へ引く。 */
fun Modifier.imasPullDownHandle(state: ImasPullDismissState): Modifier = pointerInput(state) {
    var velocity = 0f
    detectVerticalDragGestures(
        onDragStart = { velocity = 0f },
        onDragEnd = { state.release(velocity) },
        onDragCancel = { state.release(0f) },
    ) { change, dy ->
        if (dy > 0 || state.offsetPx > 0) {
            change.consume()
            velocity = dy * 60f
            state.dragBy(dy)
        }
    }
}

/** 一覧を一番上からさらに引き下げたぶんを拾う (一覧が使い切らなかった下向きのスクロール)。 */
fun Modifier.imasPullDownScroll(state: ImasPullDismissState): Modifier = nestedScroll(
    object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            // 引いている途中で上へ戻したら、先に画面を戻す。
            if (available.y < 0 && state.offsetPx > 0 && source == NestedScrollSource.UserInput) {
                val used = maxOf(available.y, -state.offsetPx)
                state.dragBy(used)
                return Offset(0f, used)
            }
            return Offset.Zero
        }

        override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
            if (available.y > 0 && source == NestedScrollSource.UserInput) {
                state.dragBy(available.y)
                return Offset(0f, available.y)
            }
            return Offset.Zero
        }

        override suspend fun onPreFling(available: Velocity): Velocity {
            if (state.offsetPx > 0) {
                state.release(available.y)
                return available
            }
            return Velocity.Zero
        }
    }
)
