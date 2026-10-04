package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.PlaylistPlay
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.LyricsPlayback
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasRow
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowLeading
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.theme.BrandColors

/**
 * 歌詞プレイヤーの下に出す「次は」の 1 行。押すとその曲へ送る。iOS `UpNextRow` の移植。
 * 右端の記号で「次はこれ」(終わったら似た曲を足して流し続ける) を入れ切りする。
 */
@Composable
fun UpNextRow(playback: LyricsPlayback) {
    val context = LocalContext.current
    val next by playback.upNext.collectAsState()
    val autoplayNext by playback.autoplayNext.collectAsState()
    var song by remember { mutableStateOf<Song?>(null) }

    LaunchedEffect(next?.first) {
        val id = next?.first
        song = if (id == null) null else AppModule.from(context).songRepository.fetchSong(id)
    }

    if (next != null) {
        val current = song
        ImasRow(
            title = current?.title ?: "次の曲",
            subtitle = subtitle(next?.second),
            leading = ImasRowLeading.Artwork(
                title = current?.title.orEmpty(),
                seed = BrandColors.hex(current?.brandId),
                imageUrl = current?.artworkUrl
            ),
            trailing = ImasRowTrailing.Custom { AutoplayToggle(playback, autoplayNext) },
            density = ImasRowDensity.COMPACT,
            modifier = Modifier.clickable { playback.skipNext() }
        )
    } else if (playback.loadedSongId.collectAsState().value != null) {
        ImasRow(
            title = if (autoplayNext) "次の曲を探しています" else "この曲で終わります",
            subtitle = if (autoplayNext) null else "右の記号で、似た曲を続けて流せます",
            leading = ImasRowLeading.Icon(
                icon = Icons.AutoMirrored.Filled.PlaylistPlay,
                tone = ImasIconTileTone.NEUTRAL
            ),
            trailing = ImasRowTrailing.Custom { AutoplayToggle(playback, autoplayNext) },
            density = ImasRowDensity.COMPACT
        )
    }
}

private fun subtitle(label: String?): String =
    listOfNotNull("次は", label).joinToString(" · ")

@Composable
private fun AutoplayToggle(playback: LyricsPlayback, isOn: Boolean) {
    ImasIconButton(
        icon = Icons.Filled.AllInclusive,
        label = if (isOn) "次はこれ: オン" else "次はこれ: オフ",
        size = ImasIconButtonSize.SMALL,
        style = if (isOn) ImasIconButtonStyle.FILLED else ImasIconButtonStyle.PLAIN,
        onClick = { playback.setAutoplayNext(!isOn) }
    )
}
