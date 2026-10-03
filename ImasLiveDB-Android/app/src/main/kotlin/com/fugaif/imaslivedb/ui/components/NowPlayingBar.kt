package com.fugaif.imaslivedb.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
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
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.player.LyricsSession
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasPartStripe
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDivider
import com.fugaif.imaslivedb.ui.lyrics.LyricsPlayerScreen
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasType
import kotlinx.coroutines.delay
import uniffi.imas_core.lyricActiveLine
import uniffi.imas_core.lyricOverlaySplit
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

    // Apple Music のフル再生が読み込まれていれば、そちらを優先する (歌詞タブがそのとき
    // LyricsSession に預けていれば、今の行も出す)。試聴は 30 秒の切り出しで行の時刻と
    // 突き合わせられないので、フル再生とは別の経路のまま。
    val lyricsPlayback = AppModule.from(context).lyricsPlayback
    val loadedSongId by lyricsPlayback.loadedSongId.collectAsState()
    val isFullPlaying by lyricsPlayback.isPlaying.collectAsState()
    val sessionEntry by LyricsSession.state.collectAsState()
    var showsLyricsPlayer by remember { mutableStateOf(false) }
    var likeCounts by remember { mutableStateOf(mapOf<String, Int>()) }

    // 鳴っている曲が変わったら (止めたら) 歌詞を手放す。
    LaunchedEffect(loadedSongId) { LyricsSession.release(unlessSongId = loadedSongId) }

    val fullEntry = loadedSongId?.let { id -> sessionEntry?.takeIf { it.song.id == id } }

    if (fullEntry != null) {
        Column(modifier = Modifier.fillMaxWidth().background(DS.surface)) {
            ImasRowDivider()
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(DS.Space.rowGap),
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showsLyricsPlayer = true }
                    .padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap)
            ) {
                ArtworkImage(url = fullEntry.artworkUrl, size = 40.dp, songTitle = fullEntry.song.title)
                Column(modifier = Modifier.weight(1f)) {
                    BarTitle(fullEntry.song.title)
                    NowPlayingLyricLine(entry = fullEntry, playback = lyricsPlayback) {
                        SubtitleLine(NowPlayingBarData(
                            songId = fullEntry.song.id, title = fullEntry.song.title,
                            artworkUrl = fullEntry.artworkUrl, subtitle = fullEntry.artistLine,
                            previewMark = null, isPlaying = isFullPlaying
                        ))
                    }
                }
                ImasIconButton(
                    icon = if (isFullPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    label = if (isFullPlaying) "一時停止" else "再生",
                    style = ImasIconButtonStyle.PLAIN,
                    onClick = { lyricsPlayback.togglePlay() }
                )
            }
        }
        if (showsLyricsPlayer) {
            Dialog(onDismissRequest = { showsLyricsPlayer = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
                LyricsPlayerScreen(
                    song = fullEntry.song, seed = fullEntry.seed, artistLine = fullEntry.artistLine,
                    lyrics = fullEntry.lyrics, likeCounts = likeCounts,
                    onLikeCountChanged = { id, count -> likeCounts = likeCounts + (id to count) },
                    // 記録は曲の詳細の歌詞タブから (記録の画面はそちらが持つ)。
                    onEditTimings = { showsLyricsPlayer = false; onSongClick(fullEntry.song.id) },
                    onClose = { showsLyricsPlayer = false },
                    cast = fullEntry.cast
                )
            }
        }
        return
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
                BarTitle(current.title)
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

/** 1 行目の曲名。試聴・フル再生の両方のバーで使う (ここ 1 箇所だけ手書きの文字スタイル)。 */
@Composable
private fun BarTitle(title: String) {
    Text(
        title,
        style = ImasType.text(15.sp, FontWeight.Medium),
        color = DS.ink,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis
    )
}

/** 2 行目 (名義・いま歌われている行) の文字スタイル。試聴・フル再生の両方で使う。 */
private val NowPlayingSubtitleStyle = ImasType.text(12.sp)

/**
 * 再生中バーの 2 行目に出す、いま歌われている行 (と歌う人の帯)。iOS `NowPlayingLyricLine` と対。
 *
 * 位置は周期で読む (バーは画面に出続けるので、行の切り替わりより少し細かく)。
 * 最初の行の前 (イントロ) は [fallback] (名義) を出す。
 *
 * ⚠️ 歌詞の本文を出すので、選択・コピーの口を付けないこと。
 */
@Composable
private fun NowPlayingLyricLine(
    entry: LyricsSession.Entry,
    playback: com.fugaif.imaslivedb.player.LyricsPlayback,
    fallback: @Composable () -> Unit
) {
    // メインの行だけに時刻を入れた並び (被せの行に今の行を取られない)。
    val mainStarts = remember(entry.lyrics) { entry.lyrics.lines.map { if (it.isOverlay) null else it.startMs?.toLong() } }
    var lineId by remember(entry.song.id) { mutableStateOf<String?>(null) }

    LaunchedEffect(entry.song.id, mainStarts) {
        while (true) {
            val ms = playback.positionMs()
            lineId = ms?.let { lyricActiveLine(mainStarts, it.toLong())?.toInt() }?.let { entry.lyrics.lines[it].id }
            delay(250)
        }
    }

    val line = lineId?.let { id -> entry.lyrics.lines.firstOrNull { it.id == id } }
    if (line != null && line.kind == com.fugaif.imaslivedb.data.lyrics.LyricLineKind.LYRIC) {
        val split = lyricOverlaySplit(line.text)
        Row(
            Modifier.height(IntrinsicSize.Min),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (line.singers.isNotEmpty()) {
                ImasPartStripe(colors = entry.cast.colors(line.singers), modifier = Modifier.height(14.dp))
            }
            Text(
                split.main.ifEmpty { line.text },
                style = NowPlayingSubtitleStyle,
                color = DS.ink3,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis
            )
        }
    } else {
        fallback()
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

    Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight), verticalAlignment = Alignment.CenterVertically) {
        if (subtitle != null) {
            Text(
                subtitle,
                style = NowPlayingSubtitleStyle,
                color = DS.ink3,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false)
            )
        }
        if (mark != null) {
            if (subtitle != null) Text("·", style = NowPlayingSubtitleStyle, color = DS.ink3)
            Text(mark, style = NowPlayingSubtitleStyle, color = DS.ink3, maxLines = 1)
        }
    }
}
