package com.fugaif.imaslivedb.ui.components

import android.content.Intent
import android.net.Uri
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
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
 * なので小窓は幅いっぱい・プレーヤーの高さは 200 以上で、閉じる操作はプレーヤーの外 (上のバー) に置く。
 */
object VideoPiP {
    /** 小窓で流している動画。 */
    data class Item(val videoId: String, val title: String?, val url: String, val player: YouTubeEmbedPlayer)

    /** 小窓の置き場所。バーをつまんで上下へずらすと、近いほうの端に寄る。 */
    enum class Dock { TOP, BOTTOM }

    var item by mutableStateOf<Item?>(null)
        private set

    /** 押してみて埋め込みを止めていると分かった動画。一覧の行も案内に替える。 */
    var unplayableVideoIds by mutableStateOf(emptySet<String>())
        private set

    var dock by mutableStateOf(Dock.BOTTOM)

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

/** アプリの画面の一番上に重ねる小窓。流している動画が無ければ何も描かない。 */
@Composable
fun VideoPiPHost() {
    val context = LocalContext.current
    val density = LocalDensity.current
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
            val width: Dp = min(maxWidth - DS.sp4 * 2, 520.dp)
            // 規約の 200 dp を割らない (幅の狭い端末では上下に黒が入る)。
            val playerHeight: Dp = max(200.dp, width * 9f / 16f)
            val height = BarHeight + playerHeight
            val topY = DS.sp3
            val bottomY = maxOf(topY, maxHeight - BottomClearance - DS.sp3 - height)
            var dragPx by remember { mutableFloatStateOf(0f) }
            val restY by animateDpAsState(
                if (VideoPiP.dock == VideoPiP.Dock.TOP) topY else bottomY,
                spring(dampingRatio = 0.86f, stiffness = Spring.StiffnessMediumLow),
                label = "pip_dock"
            )
            val y = with(density) { (restY + dragPx.toDp()).coerceIn(topY, bottomY) }
            val open = { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(item.url))) } }

            Column(
                Modifier
                    .align(Alignment.TopCenter)
                    .offset(y = y)
                    .width(width)
                    .clip(RoundedCornerShape(DS.rSM))
                    .background(DS.surface)
                    .border(1.dp, DS.line, RoundedCornerShape(DS.rSM))
            ) {
                // 上のバー: つまんで上下へ動かす・動画名・YouTube で開く・閉じる。
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(BarHeight)
                        .draggable(
                            orientation = Orientation.Vertical,
                            state = rememberDraggableState { delta -> dragPx += delta },
                            onDragStopped = { velocity ->
                                val restPx = with(density) { (if (VideoPiP.dock == VideoPiP.Dock.TOP) topY else bottomY).toPx() }
                                val landing = restPx + dragPx + velocity * 0.15f
                                val middle = with(density) { ((topY + bottomY) / 2).toPx() }
                                VideoPiP.dock = if (landing < middle) VideoPiP.Dock.TOP else VideoPiP.Dock.BOTTOM
                                dragPx = 0f
                            }
                        )
                        .padding(start = DS.sp4, end = DS.sp2),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(DS.sp3)
                ) {
                    Box(Modifier.size(width = 4.dp, height = 18.dp).clip(RoundedCornerShape(2.dp)).background(DS.ink3))
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
                Box(Modifier.fillMaxWidth().height(playerHeight)) {
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
