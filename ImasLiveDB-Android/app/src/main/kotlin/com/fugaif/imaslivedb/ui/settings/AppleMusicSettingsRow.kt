package com.fugaif.imaslivedb.ui.settings

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AppleMusicState
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow

/**
 * 設定の「Apple Music」。サインインの入口と、いまフル尺で鳴らせるか。
 *
 * 曲の行の再生ボタンは、未サインインならサインインを出さずに試聴へ落とす
 * ([com.fugaif.imaslivedb.player.SongRowPlayback])。歌詞を開かないとサインインに気付けなかったので、ここにも置く。
 * iOS は端末の Apple Music を使うので、同じ欄で許可の状態を出す (`AppleMusicSettingsRow.swift`)。
 */
@Composable
fun AppleMusicSettingsRow() {
    val playback = AppModule.from(LocalContext.current).lyricsPlayback
    val state by playback.appleMusicState.collectAsState()
    when (state) {
        AppleMusicState.READY -> ImasNavRow(
            title = "サインイン済み",
            subtitle = "曲をフル尺で鳴らし、歌詞を追いかけられます",
            icon = Icons.Filled.MusicNote,
            showsChevron = false,
        )
        AppleMusicState.SIGNED_OUT -> ImasNavRow(
            title = "Apple Music にサインイン",
            subtitle = "サインインするまで、曲は試聴 (30 秒) で鳴ります",
            icon = Icons.Filled.MusicNote,
            onClick = playback::signIn,
        )
        AppleMusicState.SIGNING_IN -> ImasNavRow(
            title = "ブラウザでサインインしています",
            subtitle = "終えてアプリに戻ると使えるようになります。押すともう一度開きます",
            icon = Icons.Filled.MusicNote,
            onClick = playback::signIn,
        )
        AppleMusicState.UNAVAILABLE -> ImasNavRow(
            title = "この端末では使えません",
            subtitle = "曲は試聴で鳴ります。歌詞はそのまま読めます",
            icon = Icons.Filled.MusicNote,
            showsChevron = false,
        )
    }
}
