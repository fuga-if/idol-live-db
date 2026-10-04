package com.fugaif.imaslivedb.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.player.SongRowPlayback
import kotlinx.coroutines.launch

/** 曲の行の再生ボタンの配線 (鳴っているか・押したとき)。フル尺優先で試聴へ落とす ([SongRowPlayback])。 */
internal class SongRowPlayWiring(val isPlaying: Boolean, val onTap: () -> Unit)

@Composable
internal fun rememberSongRowPlay(songId: String?, appleMusicId: String?, previewUrl: String?): SongRowPlayWiring {
    val playback = AppModule.from(LocalContext.current).lyricsPlayback
    val preview by AudioPreviewManager.playbackState.collectAsState()
    val loadedSongId by playback.loadedSongId.collectAsState()
    val isFullPlaying by playback.isPlaying.collectAsState()
    val scope = rememberCoroutineScope()
    val isPlaying = songId != null &&
        (preview.isPlaying(songId) || (loadedSongId == songId && isFullPlaying))
    return SongRowPlayWiring(isPlaying) {
        if (songId != null) scope.launch { SongRowPlayback.toggle(playback, songId, appleMusicId, previewUrl) }
    }
}
