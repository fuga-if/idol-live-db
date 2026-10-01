package com.fugaif.imaslivedb.ui.designsystem

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.theme.QS
import com.fugaif.imaslivedb.ui.theme.imasPress
import kotlinx.coroutines.withTimeoutOrNull

// =============================================================================
// ステージの操作部品 (docs/DESIGN_SYSTEM.md §12)。iOS `Stage/ImasStagePlaybackControl.swift` の移植。
//
// ImasStageIconTileButton  記号 + 1 行ラベルの操作タイル (もう一度・次の曲)。
// ImasStagePlaybackControl 「押す = 続きから」「長押し = 流し続ける」の 2 段の再生操作。
// ImasStageCircleButton    ステージ中央に置く大きな単発の操作ボタン (直径は呼び出し側。早押しの「!」)。
// =============================================================================

/** 記号 + 1 行ラベルの操作タイル (iOS `ImasStageIconTileButton`)。実線の枠 (再生操作の点線の枠と区別する)。 */
@Composable
fun ImasStageIconTileButton(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier
            .fillMaxWidth()
            .semantics(mergeDescendants = true) { }
            .imasPress(onClick = onClick)
            .heightIn(min = 56.dp)
            .border(1.dp, QS.line, RoundedCornerShape(14.dp)),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)
    ) {
        Icon(icon, contentDescription = null, tint = QS.ink, modifier = Modifier.size(18.dp))
        Text(label, style = QS.text(12, FontWeight.Bold), color = QS.ink)
    }
}

/** 再生操作の形 (iOS `ImasStagePlaybackControl.Style`)。 */
enum class ImasStagePlaybackStyle {
    /** 点線の枠のタイル (未再生) / 塗り (再生中)。操作の列の 1 枠として。 */
    TILE,

    /** 小さい丸 + 横に添え書き。真ん中の帯のような狭い場所用。 */
    CIRCLE
}

/** 長押しとみなすまでの時間 (iOS `minimumDuration: 0.2`)。 */
private const val HoldThresholdMillis = 200L

/**
 * 「押す = 続きから」「長押し = 流し続ける」の 2 段の再生操作 (iOS `ImasStagePlaybackControl`)。
 * 押して 0.2 秒以内に離せば [onTap]、押し続けると [onHoldBegin]、離すと [onHoldEnd]。
 *
 * @param playingLabel 読み上げ: 再生中のラベル。
 * @param pausedLabel 読み上げ: 止まっているときのラベル。押すと何が起きるか (続きから・頭から 等)。
 * @param accessibilityHintText 読み上げで押したときの操作として読む文。
 */
@Composable
fun ImasStagePlaybackControl(
    isPlaying: Boolean,
    onTap: () -> Unit,
    onHoldBegin: () -> Unit,
    onHoldEnd: () -> Unit,
    modifier: Modifier = Modifier,
    style: ImasStagePlaybackStyle = ImasStagePlaybackStyle.TILE,
    playingLabel: String = "再生中",
    pausedLabel: String = "続きから",
    accessibilityHintText: String = "タップで続きを流す。長押しの間は流し続けます"
) {
    var isHolding by remember { mutableStateOf(false) }
    val tap by rememberUpdatedState(onTap)
    val holdBegin by rememberUpdatedState(onHoldBegin)
    val holdEnd by rememberUpdatedState(onHoldEnd)
    val tile = style == ImasStagePlaybackStyle.TILE
    val scale by animateFloatAsState(if (isHolding) (if (tile) 0.94f else 0.9f) else 1f, tween(120), label = "playback")
    val spoken = if (isPlaying) playingLabel else pausedLabel
    val gesture = Modifier.pointerInput(Unit) {
        awaitEachGesture {
            awaitFirstDown()
            val up = withTimeoutOrNull(HoldThresholdMillis) { waitForUpOrCancellation() }
            if (up != null) {
                up.consume()
                tap()
                return@awaitEachGesture
            }
            isHolding = true
            holdBegin()
            waitForUpOrCancellation()
            isHolding = false
            holdEnd()
        }
    }
    val a11y = Modifier.clearAndSetSemantics {
        contentDescription = spoken
        role = Role.Button
        onClick(label = accessibilityHintText) { tap(); true }
    }
    if (tile) {
        val line = QS.line
        Column(
            modifier
                .fillMaxWidth()
                .then(a11y)
                .scale(scale)
                .then(gesture)
                .heightIn(min = 56.dp)
                .background(if (isPlaying) QS.ink else Color.Transparent, RoundedCornerShape(14.dp))
                .drawBehind {
                    val w = 1.5.dp.toPx()
                    drawRoundRect(
                        line,
                        topLeft = Offset(w / 2, w / 2),
                        size = Size(size.width - w, size.height - w),
                        cornerRadius = CornerRadius(14.dp.toPx()),
                        style = Stroke(width = w, pathEffect = PathEffect.dashPathEffect(floatArrayOf(5.dp.toPx(), 4.dp.toPx())))
                    )
                },
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically)
        ) {
            val fg = if (isPlaying) QS.bg else QS.ink
            Icon(if (isPlaying) Icons.Filled.GraphicEq else Icons.Filled.PlayArrow, contentDescription = null, tint = fg, modifier = Modifier.size(18.dp))
            Text(if (isPlaying) "再生中" else "続きから", style = QS.text(12, FontWeight.Bold), color = fg)
        }
    } else {
        Row(
            modifier
                .then(a11y)
                .scale(scale)
                .then(gesture),
            horizontalArrangement = Arrangement.spacedBy(10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                Modifier
                    .size(40.dp)
                    .background(if (isPlaying) QS.ink else QS.raised, CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    if (isPlaying) Icons.Filled.GraphicEq else Icons.Filled.PlayArrow,
                    contentDescription = null,
                    tint = if (isPlaying) QS.bg else QS.ink,
                    modifier = Modifier.size(18.dp)
                )
            }
            Text("長押しでもう少し", style = QS.text(10, FontWeight.SemiBold), color = QS.faint)
        }
    }
}

/**
 * ステージ中央の大きな単発の操作ボタン (iOS `ImasStageCircleButton`。早押しの「!」)。直径は呼び出し側が画面から決める。
 * 文字は円の直径に対する比率で決める (文字の大きさの設定で円からはみ出さないよう、意図的に固定)。
 */
@Composable
fun ImasStageCircleButton(label: String, size: Dp, onClick: () -> Unit, modifier: Modifier = Modifier, isEnabled: Boolean = true) {
    val density = LocalDensity.current
    val glyph = with(density) { maxOf(48.dp, size * 0.45f).toSp() }
    val fill = if (isEnabled) QS.ink else QS.raised
    Box(
        modifier
            .size(size)
            .clearAndSetSemantics {
                contentDescription = label
                role = Role.Button
                if (!isEnabled) disabled()
                if (isEnabled) onClick { onClick(); true }
            }
            .imasPress(enabled = isEnabled, onClick = onClick)
            .then(
                if (isEnabled) {
                    Modifier.imasSoftShadow(CircleShape, fill = fill, color = QS.ink.copy(alpha = 0.25f), blur = 16.dp, offsetY = 6.dp)
                } else {
                    Modifier.background(fill, CircleShape)
                }
            ),
        contentAlignment = Alignment.Center
    ) {
        Text(label, style = QS.text(0, FontWeight.Black).copy(fontSize = glyph), color = if (isEnabled) QS.bg else QS.faint)
    }
}
