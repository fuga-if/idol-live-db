package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import uniffi.imas_core.NowPlayingBar as NowPlayingBarData
import uniffi.imas_core.NowPlayingKind

/**
 * ナビゲーションバーの直上に出す再生中バー (ミニプレイヤー)。iOS の `NowPlayingBarView` と対。
 *
 * 出すのは **このアプリが鳴らしている音** だけ。
 *
 * 何を出すかの判断はコア (`imas-core` の `now_playing`) が持つ。ここはコアが返した
 * 1 枚を描くだけで、名義の組み立ても試聴の書き分けもしない。iOS と別々に書くと
 * 必ず片方だけずれる。
 *
 * Android には Apple Music のフル尺再生が無い (`AudioPreviewManager` は 30 秒試聴だけ) ので
 * 種別は常に [NowPlayingKind.PREVIEW]。
 */
@Composable
fun NowPlayingBar(onSongClick: (String) -> Unit) {
    val context = LocalContext.current
    val playback by AudioPreviewManager.playbackState.collectAsState()
    var bar by remember { mutableStateOf<NowPlayingBarData?>(null) }

    // 再生状態が変わったときだけ引き直す。曲が同じなら一時停止/再開でも 1 回で済む。
    LaunchedEffect(playback.nowPlayingSongId, playback.isPlaying) {
        val songId = playback.nowPlayingSongId
        bar = if (songId == null) {
            null
        } else {
            AppModule.from(context).snapshotStoreProvider.query { store ->
                store.nowPlayingBar(songId, NowPlayingKind.PREVIEW, playback.isPlaying)
            }
        }
    }

    val current = bar ?: return

    Column(modifier = Modifier.fillMaxWidth().background(DS.surface)) {
        ImasRowDivider()

        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onSongClick(current.songId) }
                .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
        ) {
            ArtworkImage(url = current.artworkUrl, size = 40.dp, songTitle = current.title)

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    current.title,
                    style = ImasType.text(15.sp, FontWeight.Medium),
                    color = DS.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis
                )
                SubtitleLine(current)
            }

            ImasIconButton(
                icon = if (current.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                label = if (current.isPlaying) "一時停止" else "再生",
                style = ImasIconButtonStyle.PLAIN,
                onClick = {
                    // stop ではなく pause。stop は曲ごと手放すのでバーが消えてしまう。
                    if (current.isPlaying) AudioPreviewManager.pause() else AudioPreviewManager.resume()
                }
            )
        }
    }
}

/**
 * 2 行目。名義と「試聴」の印を別の [Text] にする。
 *
 * 1 本に繋いで 1 行に収めると、長い名義に押し出されて **末尾の印だけが真っ先に消える**。
 * 伝えたいのは「30 秒で終わる」の方なので、印には省略を許さない。
 */
@Composable
private fun SubtitleLine(bar: NowPlayingBarData) {
    val subtitle = bar.subtitle
    val mark = bar.previewMark
    if (subtitle == null && mark == null) return

    val style = ImasType.text(12.sp)
    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
        if (subtitle != null) {
            Text(
                subtitle,
                style = style,
                color = DS.ink3,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false)
            )
        }
        if (mark != null) {
            if (subtitle != null) Text("·", style = style, color = DS.ink3)
            Text(mark, style = style, color = DS.ink3, maxLines = 1)
        }
    }
}
