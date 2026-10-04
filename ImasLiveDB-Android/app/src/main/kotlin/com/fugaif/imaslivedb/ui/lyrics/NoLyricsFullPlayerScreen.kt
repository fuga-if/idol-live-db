package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.automirrored.filled.TextSnippet
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.player.LyricsPlayback
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.theme.DS

/**
 * 歌詞の無い曲 (取れなかった曲) のフル再生に付いていく画面。曲名と曲送りだけを出す。
 * iOS `NowPlayingLyricsPlayerView.noLyrics` の移植。
 */
@Composable
fun NoLyricsFullPlayerScreen(song: Song?, playback: LyricsPlayback, onClose: () -> Unit) {
    val isPlaying by playback.isPlaying.collectAsState()
    val hasQueue by playback.hasQueue.collectAsState()
    val canSkipNext by playback.canSkipNext.collectAsState()

    Column(Modifier.fillMaxSize().background(DS.bg).padding(DS.sp5)) {
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1f))
            ImasIconButton(icon = Icons.Filled.ExpandMore, label = "閉じる", onClick = onClose, style = ImasIconButtonStyle.PLAIN)
        }
        Spacer(Modifier.weight(1f))
        ImasEmptyState(icon = Icons.AutoMirrored.Filled.TextSnippet, title = song?.title ?: "この曲の歌詞はまだありません")
        Spacer(Modifier.weight(1f))
        Row(
            Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(DS.sp8),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Spacer(Modifier.weight(1f))
            if (hasQueue) {
                ImasIconButton(icon = Icons.Filled.SkipPrevious, label = "前の曲", onClick = { playback.skipPrevious() })
            }
            ImasIconButton(
                icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                label = if (isPlaying) "一時停止" else "再生",
                style = ImasIconButtonStyle.FILLED,
                onClick = { playback.togglePlay() }
            )
            if (hasQueue) {
                ImasIconButton(icon = Icons.Filled.SkipNext, label = "次の曲", enabled = canSkipNext, onClick = { playback.skipNext() })
            }
            Spacer(Modifier.weight(1f))
        }
    }
}
