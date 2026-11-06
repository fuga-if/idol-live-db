package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AppleMusicState
import uniffi.imas_core.FullPlaybackNeed
import com.fugaif.imaslivedb.player.RoutedLyricsPlayback
import com.fugaif.imaslivedb.player.LyricsPlayback
import uniffi.imas_core.appleMusicUnavailableNotice
import uniffi.imas_core.fullPlaybackFailedNote
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind

/**
 * Apple Music に繋がっていないときの案内。歌詞プレイヤー・タイミング編集の頭に出す。
 *
 * 鳴らそうとした時点でサインインの画面 (アプリ内ブラウザ) は自動で開くので、ここは
 * 「いま何が起きているか」と、閉じてしまったときに開き直す口を出すだけ。繋がっていれば何も出さない
 * (Spotify で鳴らせるときも [RoutedLyricsPlayback] が READY を返すので何も出さない)。
 *
 * Apple Music で鳴らせない端末 (Android の多く) では、Spotify で鳴らす道を案内する。
 * 連携済みで鳴らす許可だけ無い (プレイリストだけの頃のログイン) なら、その場でログインし直せる。
 */
@Composable
fun AppleMusicSignInNotice(state: AppleMusicState, onSignIn: () -> Unit, modifier: Modifier = Modifier) {
    when (state) {
        AppleMusicState.READY -> Unit
        AppleMusicState.UNAVAILABLE -> {
            val context = LocalContext.current
            val spotifyService = AppModule.from(context).spotifyService
            val spotify by spotifyService.state.collectAsState()
            val clientId = spotify.clientId
            val relogin = spotify.isConnected && clientId != null
            ImasNotice(
                kind = ImasNoticeKind.INFO,
                message = appleMusicUnavailableNotice(spotify.isConnected),
                modifier = modifier,
                icon = Icons.Filled.MusicNote,
                actionTitle = if (relogin) "Spotify にもう一度ログイン" else null,
                actionIcon = if (relogin) Icons.AutoMirrored.Filled.Login else null,
                onAction = if (relogin && clientId != null) { { spotifyService.startSignIn(context, clientId) } } else null,
            )
        }
        AppleMusicState.SIGNED_OUT -> ImasNotice(
            kind = ImasNoticeKind.INFO,
            title = "Apple Music にサインイン",
            message = "サインインすると、曲をフル尺で鳴らして歌詞を追いかけられます。",
            modifier = modifier,
            icon = Icons.Filled.MusicNote,
            actionTitle = "サインイン",
            actionIcon = Icons.AutoMirrored.Filled.OpenInNew,
            onAction = onSignIn,
        )
        AppleMusicState.SIGNING_IN -> ImasNotice(
            kind = ImasNoticeKind.INFO,
            title = "ブラウザでサインインしています",
            message = "サインインを終えてアプリに戻ると、再生が始まります。",
            modifier = modifier,
            icon = Icons.Filled.MusicNote,
            actionTitle = "もう一度開く",
            actionIcon = Icons.AutoMirrored.Filled.OpenInNew,
            onAction = onSignIn,
        )
    }
}

/**
 * フル再生を始められなかったときの一文。鳴らそうとしたサービスの名前で言う
 * (Spotify で鳴らそうとしたのに「Apple Music で」と出すと、Apple Music に落ちたように読める)。
 * サービスはどちらにも繋がっていなければ null。文はコア (`fullPlaybackFailedNote`)。
 */
fun fullPlaybackFailedText(playback: LyricsPlayback, need: FullPlaybackNeed): String =
    fullPlaybackFailedNote((playback as? RoutedLyricsPlayback)?.currentService(), need)
