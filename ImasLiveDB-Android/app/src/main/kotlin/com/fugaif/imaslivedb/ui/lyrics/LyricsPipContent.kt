package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.lyrics.LyricLineKind
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.LyricsSession
import com.fugaif.imaslivedb.ui.designsystem.ImasPartNames
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerCallLine
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerLyricLine
import com.fugaif.imaslivedb.ui.designsystem.lyricColor
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasTheme
import kotlinx.coroutines.delay
import uniffi.imas_core.lyricActiveCall
import uniffi.imas_core.lyricActiveLine
import uniffi.imas_core.lyricMainRange
import uniffi.imas_core.lyricOverlaySplit

/** 絵の大きさ (16:9)。PiP の窓の大きさに合わせて、これを丸ごと縮めて出す (字の大きさの比を保つ)。 */
private val CanvasWidth = 480.dp
private val CanvasHeight = 270.dp

/**
 * PiP の窓の中身。いま歌っている行 (歌う人の色で字を塗る)・歌う人・コール・次の行。iOS `LyricsPictureInPicture` の絵と対。
 *
 * ⚠️ 歌詞の本文を出すのは、いま歌っている行と次の行の 2 行だけ。
 */
@Composable
fun LyricsPipContent(modifier: Modifier = Modifier) {
    val playback = AppModule.from(LocalContext.current).lyricsPlayback
    val session by LyricsSession.state.collectAsState()
    val loadedSongId by playback.loadedSongId.collectAsState()
    val entry = session?.takeIf { it.song.id == loadedSongId }
    var positionMs by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) {
        while (true) {
            positionMs = playback.positionMs() ?: 0
            delay(200)
        }
    }

    BoxWithConstraints(modifier.fillMaxSize().background(DS.bg), contentAlignment = Alignment.Center) {
        val density = LocalDensity.current
        val scale = minOf(maxWidth / CanvasWidth, maxHeight / CanvasHeight)
        CompositionLocalProvider(LocalDensity provides Density(density.density * scale, density.fontScale)) {
            Box(Modifier.requiredSize(CanvasWidth, CanvasHeight).padding(horizontal = 24.dp, vertical = 18.dp)) {
                if (entry == null) {
                    ImasText("♪", ImasTextRole.HERO_TITLE, color = DS.ink3, modifier = Modifier.align(Alignment.CenterStart))
                } else {
                    PipLines(entry, positionMs)
                }
            }
        }
    }
}

@Composable
private fun PipLines(entry: LyricsSession.Entry, positionMs: Int) {
    val lines = entry.lyrics.lines
    val mainStarts = remember(lines) { lines.map { if (it.isOverlay) null else it.startMs?.toLong() } }
    val calls = remember(lines) { lines.flatMap { line -> line.calls.map { line to it } } }
    val callStarts = remember(calls) { calls.map { it.second.startMs?.toLong() } }
    val index = lyricActiveLine(mainStarts, positionMs.toLong())?.toInt()
    val current = index?.takeIf { lines[it].kind == LyricLineKind.LYRIC }?.let { lines[it] }
    val next = lines.drop((index ?: -1) + 1).firstOrNull { it.kind == LyricLineKind.LYRIC && !it.isOverlay }
    val call = lyricActiveCall(callStarts, positionMs.toLong())?.toInt()?.let { calls[it] }
    val theme = imasTheme(seed = entry.seed)

    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        // 曲名 (差し色の短い印を頭に)。
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(3.dp).height(14.dp).background(theme.accent))
            Spacer(Modifier.width(8.dp))
            ImasText(entry.song.title, ImasTextRole.ROW_SUBTITLE, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Spacer(Modifier.height(4.dp))
        Box(Modifier.heightIn(max = 120.dp).clipToBounds()) {
            if (current != null) {
                val mainText = lyricOverlaySplit(current.text).main.ifEmpty { current.text }
                val parts = entry.cast.marks(current, mapRange = if (mainText == current.text) null else { start, end ->
                    lyricMainRange(current.text, start.toUInt(), end.toUInt())?.let { it.start.toInt() to it.end.toInt() }
                })
                ImasPlayerLyricLine(text = mainText, isCurrent = true, parts = parts, seed = entry.seed)
            } else {
                // イントロ・間奏。
                ImasPlayerLyricLine(text = "♪", isCurrent = false, seed = entry.seed)
            }
        }
        if (current != null) ImasPartNames(groups = entry.cast.groups(current))
        if (call != null) {
            val (line, c) = call
            ImasPlayerCallLine(
                marker = "»", text = if (line.echoes(c)) "一緒に" else c.text,
                color = c.emphasis.lyricColor(theme.accent), isActive = true
            )
        }
        Spacer(Modifier.weight(1f))
        if (next != null) {
            Box(Modifier.heightIn(max = 44.dp).clipToBounds()) {
                ImasPlayerLyricLine(
                    text = lyricOverlaySplit(next.text).main.ifEmpty { next.text },
                    isCurrent = false, seed = entry.seed
                )
            }
        }
    }
}
