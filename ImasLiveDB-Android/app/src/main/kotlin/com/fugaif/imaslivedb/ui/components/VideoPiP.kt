package com.fugaif.imaslivedb.ui.components

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Close
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasWindowGrip
import com.fugaif.imaslivedb.ui.designsystem.YouTubeInlinePlayer
import com.fugaif.imaslivedb.ui.designsystem.YouTubeUnplayableNotice
import com.fugaif.imaslivedb.ui.designsystem.imasFloatingWindow
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import uniffi.imas_core.YouTubeEmbedPlayer

/**
 * 参考動画の小窓 (アプリの中だけで浮かぶ PiP)。iOS `VideoPiP` の移植。
 *
 * 動画を押すと最初からこの小窓で開く。曲の画面を離れても、他の画面へ移っても再生が続くように、
 * プレーヤーは画面ではなくアプリで 1 つだけ持つ ([VideoPiPHost] を画面の一番上に重ねる)。
 *
 * YouTube の規約で、埋め込みプレーヤーは 200×200 dp 以上・上に何も重ねない。
 * なのでプレーヤーの幅と高さは 200 以上で、閉じる操作はプレーヤーの外 (上のバー) に置く。
 *
 * 大きさは 2 本指でつまんで変える (小窓のどこでも)。バーを 2 回押すと最小 ⇄ 最大。
 * 幅いっぱいより小さいときは、バーをつまんで四隅の近いほうへ寄せられる。
 * 決めた大きさは次に開いたときも使う。
 */
object VideoPiP {
    /** 小窓で流している動画。 */
    data class Item(val videoId: String, val title: String?, val url: String, val player: YouTubeEmbedPlayer)

    /** 小窓の置き場所。バーをつまんでずらすと、近いほうの端 (隅) に寄る。 */
    enum class Dock { TOP, BOTTOM }

    /** 幅いっぱいより小さいときの左右の寄せ先。 */
    enum class Side { START, END }

    var item by mutableStateOf<Item?>(null)
        private set

    /** 押してみて埋め込みを止めていると分かった動画。一覧の行も案内に替える。 */
    var unplayableVideoIds by mutableStateOf(emptySet<String>())
        private set

    var dock by mutableStateOf(Dock.BOTTOM)
    var side by mutableStateOf(Side.END)

    /** 人が決めた小窓の幅 (dp)。null は「入る中でいちばん大きく」(はじめの大きさ)。 */
    var preferredWidthDp by mutableStateOf<Float?>(null)
        private set
    private var loaded = false

    private const val PREFS = "video_pip"
    private const val WIDTH_KEY = "width_dp"

    internal fun load(context: Context) {
        if (loaded) return
        loaded = true
        val w = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getFloat(WIDTH_KEY, 0f)
        preferredWidthDp = w.takeIf { it > 0f }
    }

    /** 幅を決める。最大に近ければ「いちばん大きく」に戻し、画面が変わっても追う。 */
    internal fun setWidth(context: Context, widthDp: Float, range: ClosedFloatingPointRange<Float>) {
        val w = widthDp.coerceIn(range)
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        if (w >= range.endInclusive - 8f) {
            preferredWidthDp = null
            prefs.remove(WIDTH_KEY)
        } else {
            preferredWidthDp = Math.round(w).toFloat()
            prefs.putFloat(WIDTH_KEY, Math.round(w).toFloat())
        }
        prefs.apply()
    }

    val isUnplayable: Boolean get() = item?.let { it.videoId in unplayableVideoIds } ?: false

    fun play(item: Item) {
        this.item = item
    }

    fun close() {
        item = null
    }

    fun markUnplayable(videoId: String) {
        unplayableVideoIds = unplayableVideoIds + videoId
    }
}

private val BarHeight = 44.dp

/** 下に寄せたとき、下のナビゲーションバーに被らない高さ。 */
private val BottomClearance = 80.dp

/** 規約の下限 (プレーヤーの幅・高さとも)。 */
private const val MinPlayerSide = 200f

/** 大きい画面でも小窓らしさを残す上限。 */
private const val MaxWidth = 720f

private val PipSpring = spring<Float>(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow)

/** アプリの画面の一番上に重ねる小窓。流している動画が無ければ何も描かない。 */
@Composable
fun VideoPiPHost() {
    val context = LocalContext.current
    val density = LocalDensity.current
    remember { VideoPiP.load(context); true }
    AnimatedVisibility(
        visible = VideoPiP.item != null,
        enter = fadeIn(),
        exit = fadeOut(),
        modifier = Modifier.fillMaxSize()
    ) {
        // 閉じるアニメーションの間も中身を描けるよう、最後の動画を覚えておく。
        var lastItem by remember { mutableStateOf<VideoPiP.Item?>(null) }
        VideoPiP.item?.let { lastItem = it }
        val item = lastItem ?: return@AnimatedVisibility
        BoxWithConstraints(Modifier.fillMaxSize().systemBarsPadding()) {
            val margin = DS.sp4.value
            val areaW = maxWidth.value
            val areaH = maxHeight.value
            val usableH = areaH - BottomClearance.value - DS.sp3.value * 2
            // 縦が足りない (横向きなど) ときは、高さが入る幅まで。
            val fitW = (usableH - BarHeight.value) * 16f / 9f
            val upper = maxOf(MinPlayerSide, minOf(areaW - margin * 2, MaxWidth, fitW))
            val range = MinPlayerSide..upper

            // 2 本指でつまんでいる間の倍率 (離したら幅に焼き込む)。
            var pinchScale by remember { mutableFloatStateOf(1f) }
            val targetW = ((VideoPiP.preferredWidthDp ?: upper) * pinchScale).coerceIn(range)
            val animW by animateFloatAsState(targetW, if (pinchScale != 1f) snap() else PipSpring, label = "pip_width")
            val widthDp = Math.round(animW).toFloat()
            // 規約の 200 dp を割らない (細くすると上下に黒が入る)。
            val playerH = maxOf(MinPlayerSide, Math.round(widthDp * 9f / 16f).toFloat())
            val height = BarHeight.value + playerH

            val topY = DS.sp3.value
            val bottomY = maxOf(topY, areaH - BottomClearance.value - DS.sp3.value - height)
            val leftX = margin
            val rightX = maxOf(leftX, areaW - margin - widthDp)
            val full = rightX - leftX < 1f

            var drag by remember { mutableStateOf(Offset.Zero) }
            val restY by animateFloatAsState(
                if (VideoPiP.dock == VideoPiP.Dock.TOP) topY else bottomY, PipSpring, label = "pip_dock"
            )
            val restX by animateFloatAsState(
                when {
                    full -> (areaW - widthDp) / 2f
                    VideoPiP.side == VideoPiP.Side.START -> leftX
                    else -> rightX
                },
                if (pinchScale != 1f) snap() else PipSpring, label = "pip_side"
            )
            val dragDp = with(density) { Offset(drag.x.toDp().value, drag.y.toDp().value) }
            val y = (restY + dragDp.y).coerceIn(topY, bottomY)
            val x = if (full) restX else (restX + dragDp.x).coerceIn(leftX, maxOf(leftX, rightX))
            val open = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(item.url))) } }
            val toggleSize = {
                val mid = (range.start + range.endInclusive) / 2f
                VideoPiP.setWidth(context, if (widthDp > mid) range.start else range.endInclusive, range)
            }

            Column(
                Modifier
                    .offset(x = x.dp, y = y.dp)
                    .width(widthDp.dp)
                    .imasFloatingWindow()
                    // 2 本指のつまみは、プレーヤー (WebView) より先に受けて大きさ変えに使う。
                    .pointerInput(range) {
                        awaitEachGesture {
                            var pinching = false
                            do {
                                val event = awaitPointerEvent(PointerEventPass.Initial)
                                val pressed = event.changes.count { it.pressed }
                                if (pressed >= 2) {
                                    pinching = true
                                    val zoom = event.calculateZoom()
                                    if (zoom != 1f) pinchScale *= zoom
                                    event.changes.forEach { it.consume() }
                                }
                            } while (event.changes.any { it.pressed })
                            if (pinching) {
                                VideoPiP.setWidth(context, targetW, range)
                                pinchScale = 1f
                            }
                        }
                    }
            ) {
                // 上のバー: つまんで動かす・動画名・YouTube で開く・閉じる。2 回押すと大きさを切り替える。
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(BarHeight)
                        .pointerInput(Unit) { detectTapGestures(onDoubleTap = { toggleSize() }) }
                        .pointerInput(topY, bottomY, leftX, rightX) {
                            val tracker = VelocityTracker()
                            detectDragGestures(
                                onDragStart = { tracker.resetTracking() },
                                onDrag = { change, amount ->
                                    change.consume()
                                    tracker.addPosition(change.uptimeMillis, change.position)
                                    drag += amount
                                },
                                onDragEnd = {
                                    val v = tracker.calculateVelocity()
                                    val d = with(density) { Offset((drag.x + v.x * 0.15f).toDp().value, (drag.y + v.y * 0.15f).toDp().value) }
                                    val curY = if (VideoPiP.dock == VideoPiP.Dock.TOP) topY else bottomY
                                    VideoPiP.dock = if (curY + d.y < (topY + bottomY) / 2f) VideoPiP.Dock.TOP else VideoPiP.Dock.BOTTOM
                                    if (rightX - leftX >= 1f) {
                                        val curX = if (VideoPiP.side == VideoPiP.Side.START) leftX else rightX
                                        VideoPiP.side = if (curX + d.x < (leftX + rightX) / 2f) VideoPiP.Side.START else VideoPiP.Side.END
                                    }
                                    drag = Offset.Zero
                                },
                                onDragCancel = { drag = Offset.Zero }
                            )
                        }
                        .semantics { customActions = listOf(CustomAccessibilityAction("大きさを切り替える") { toggleSize(); true }) }
                        .padding(start = DS.sp4, end = DS.sp2),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(DS.sp3)
                ) {
                    ImasWindowGrip()
                    ImasText(
                        item.title ?: "参考動画", ImasTextRole.META, color = DS.ink2,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f)
                    )
                    ImasIconButton(
                        icon = Icons.AutoMirrored.Filled.OpenInNew, label = "YouTube で開く",
                        size = ImasIconButtonSize.SMALL, style = ImasIconButtonStyle.PLAIN, onClick = { open() }
                    )
                    ImasIconButton(
                        icon = Icons.Filled.Close, label = "小窓を閉じる",
                        size = ImasIconButtonSize.SMALL, style = ImasIconButtonStyle.PLAIN, onClick = { VideoPiP.close() }
                    )
                }
                Box(Modifier.fillMaxWidth().height(playerH.dp)) {
                    if (VideoPiP.isUnplayable) {
                        YouTubeUnplayableNotice(onOpen = { open(); VideoPiP.close() }, modifier = Modifier.fillMaxSize())
                    } else {
                        key(item.videoId) {
                            YouTubeInlinePlayer(
                                item.player,
                                onUnplayable = { VideoPiP.markUnplayable(item.videoId) },
                                modifier = Modifier.fillMaxSize()
                            )
                        }
                    }
                }
            }
        }
    }
}
