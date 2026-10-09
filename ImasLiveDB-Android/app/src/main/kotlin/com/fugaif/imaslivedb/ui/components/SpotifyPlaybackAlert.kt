package com.fugaif.imaslivedb.ui.components

import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.RoutedLyricsPlayback
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceDialog
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import uniffi.imas_core.SpotifyFailure
import uniffi.imas_core.spotifyFailureMessage

/**
 * Spotify で鳴らせなかったときの案内。iOS `.spotifyPlaybackAlert()`。アプリの根に 1 つ置く
 * (ダイアログは窓なので、シートの上にも出る)。鳴らす先が無いときは Spotify アプリを開く口を添える。
 */
@Composable
fun SpotifyPlaybackAlert() {
    val context = LocalContext.current
    val playback = AppModule.from(context).lyricsPlayback as? RoutedLyricsPlayback ?: return
    val failure by playback.spotifyFailure.collectAsState()
    val current = failure ?: return
    val title = "Spotify で鳴らせませんでした"
    if (current == SpotifyFailure.NO_DEVICE) {
        ImasChoiceDialog(
            title = title,
            isPresented = true,
            options = listOf("open" to "Spotify を開く"),
            onPick = {
                val app = context.packageManager.getLaunchIntentForPackage("com.spotify.music")
                runCatching {
                    context.startActivity(app ?: Intent(Intent.ACTION_VIEW, Uri.parse("https://open.spotify.com")))
                }
            },
            onDismiss = playback::clearSpotifyFailure,
            message = spotifyFailureMessage(current),
            dismissTitle = "OK",
        )
    } else {
        ImasErrorAlert(message = spotifyFailureMessage(current), onDismiss = playback::clearSpotifyFailure, title = title)
    }
}
