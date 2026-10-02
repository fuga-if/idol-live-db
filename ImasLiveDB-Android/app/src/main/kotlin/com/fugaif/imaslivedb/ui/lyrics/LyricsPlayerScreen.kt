package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.lyrics.LyricCall
import com.fugaif.imaslivedb.data.lyrics.LyricLine
import com.fugaif.imaslivedb.data.lyrics.LyricLineKind
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasCallRows
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLikeHeatSeekBar
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerLyricLine
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerOverlayLine
import com.fugaif.imaslivedb.ui.designsystem.imasLyricClock
import com.fugaif.imaslivedb.ui.designsystem.lyricColor
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.imas_core.lyricActiveCall
import uniffi.imas_core.lyricActiveLine
import uniffi.imas_core.lyricActiveOverlay
import uniffi.imas_core.lyricHasTiming
import uniffi.imas_core.lyricLikeHeat
import uniffi.imas_core.lyricOverlaySplit

/**
 * 歌詞プレイヤー。全画面で、いま歌われている行を大きく出す (Apple Music の歌詞表示と同じ読ませ方)。
 * iOS `LyricsPlayerView` の移植。
 *
 * - 行をタップ … その行の歌い出しへ飛ぶ (時刻のある行だけ)
 * - 行をダブルタップ … ここ好き
 *
 * ⚠️ 歌詞の本文にテキスト選択・コピー・共有の口を付けないこと (このファイルから `SelectionContainer` を
 * 呼ばないこと。[com.fugaif.imaslivedb.ui.songs.SongLyricsTab] 冒頭の注記と同じ)。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LyricsPlayerScreen(
    song: Song,
    seed: String?,
    artistLine: String?,
    lyrics: Lyrics,
    likeCounts: Map<String, Int>,
    onLikeCountChanged: (String, Int) -> Unit,
    onEditTimings: () -> Unit,
    onClose: () -> Unit
) {
    val module = AppModule.from(LocalContext.current)
    val playback = module.lyricsPlayback
    val scope = rememberCoroutineScope()

    var positionMs by remember { mutableStateOf<Int?>(null) }
    var activeLineId by remember { mutableStateOf<String?>(null) }
    var activeOverlayId by remember { mutableStateOf<String?>(null) }
    var startFailed by remember { mutableStateOf(false) }
    var likes by remember { mutableStateOf(setOf<String>()) }

    val starts = remember(lyrics) { lyrics.lines.map { it.startMs?.toLong() } }
    val mainStarts = remember(lyrics) { lyrics.lines.map { if (it.isOverlay) null else it.startMs?.toLong() } }
    val overlayStarts = remember(lyrics) { lyrics.lines.map { if (it.isOverlay) it.startMs?.toLong() else null } }
    val allCalls = remember(lyrics) { lyrics.lines.flatMap { it.calls } }
    val callStarts = remember(allCalls) { allCalls.map { it.startMs?.toLong() } }
    val hasTiming = remember(starts) { lyricHasTiming(starts) }
    val loadedSongId by playback.loadedSongId.collectAsState()
    val isPlaying by playback.isPlaying.collectAsState()
    val isFullLoaded = loadedSongId == song.id

    LaunchedEffect(song.id) {
        likes = module.userMarkRepository.lyricLikes(song.id)
        if (playback.loadedSongId.value != song.id) {
            startFailed = !playback.startFull(song.id, song.appleMusicId ?: "")
        }
    }
    LaunchedEffect(isFullLoaded) {
        while (true) {
            val ms = playback.positionMs()
            if (ms != null) {
                positionMs = ms
                val index = lyricActiveLine(mainStarts, ms.toLong())?.toInt()
                val id = index?.let { lyrics.lines[it].id }
                if (id != activeLineId) activeLineId = id
                val overlayIndex = lyricActiveOverlay(overlayStarts, ms.toLong())?.toInt()
                val overlayId = overlayIndex?.let { lyrics.lines[it].id }
                if (overlayId != activeOverlayId) activeOverlayId = overlayId
            }
            delay(150)
        }
    }

    val durationMs = run {
        val lastStart = starts.filterNotNull().maxOrNull()?.toInt() ?: 0
        playback.durationMs() ?: song.durationSec?.let { it * 1000 } ?: (lastStart + 8000)
    }

    fun like(line: LyricLine) {
        scope.launch {
            val now = module.userMarkRepository.toggleLyricLike(song.id, line.id)
            likes = if (now) likes + line.id else likes - line.id
            if (module.authService.state.value.isSignedIn) {
                runCatching { module.lyricsApi.setLike(song.id, line.id, now) }.getOrNull()?.let {
                    onLikeCountChanged(line.id, it)
                }
            }
        }
    }

    Column(Modifier.fillMaxSize().background(DS.bg)) {
        // 頭
        Row(
            Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp4),
            horizontalArrangement = Arrangement.spacedBy(DS.sp4),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ArtworkImage(url = song.artworkUrl, size = 52.dp, previewUrl = null, songTitle = song.title, songId = song.id, seed = seed, brand = song.brandId)
            Column(Modifier.weight(1f)) {
                ImasText(song.title, ImasTextRole.ROW_TITLE, maxLines = 1)
                if (!artistLine.isNullOrEmpty()) ImasText(artistLine, ImasTextRole.ROW_SUBTITLE, maxLines = 1)
            }
            ImasIconButton(icon = Icons.Filled.Speed, label = "タイミングを編集", onClick = onEditTimings, style = ImasIconButtonStyle.PLAIN)
            ImasIconButton(icon = Icons.Filled.ExpandMore, label = "閉じる", onClick = onClose, style = ImasIconButtonStyle.PLAIN)
        }

        // 歌詞
        val listState = rememberLazyListState()
        LaunchedEffect(activeLineId) {
            val id = activeLineId ?: return@LaunchedEffect
            val index = lyrics.lines.indexOfFirst { it.id == id }
            if (index >= 0) listState.animateScrollToItem(maxOf(0, index - 1))
        }
        LazyColumn(Modifier.weight(1f).padding(horizontal = DS.sp5), state = listState) {
            item {
                if (!hasTiming) {
                    Column(Modifier.padding(vertical = DS.sp4)) {
                        ImasNote("この曲はまだ行の時刻が記録されていないので、追従できません。")
                        Spacer(Modifier.height(DS.sp3))
                        ImasButton(title = "タイミングを記録する", onClick = onEditTimings, role = ImasButtonRole.SECONDARY)
                    }
                }
                if (startFailed) {
                    ImasNote("再生には Apple Music でのフル再生が必要です。", modifier = Modifier.padding(vertical = DS.sp2))
                }
            }
            itemsIndexed(lyrics.lines) { _, line ->
                LyricsPlayerRow(
                    line = line, hasTiming = hasTiming, isLiked = likes.contains(line.id),
                    isActive = line.id == activeLineId, isOverlayActive = line.id == activeOverlayId,
                    seed = seed,
                    onTap = {
                        val start = line.startMs ?: return@LyricsPlayerRow
                        scope.launch { playback.startFull(song.id, song.appleMusicId ?: ""); playback.seek(start) }
                    },
                    onDoubleTap = { like(line) }
                )
            }
            item { Spacer(Modifier.height(DS.sp8)) }
        }

        // 下の操作
        Column(
            Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp4),
            verticalArrangement = Arrangement.spacedBy(DS.sp3)
        ) {
            CallLane(allCalls = allCalls, callStarts = callStarts, positionMs = positionMs ?: 0, seed = seed)
            val counts = lyrics.lines.map { (likeCounts[it.id] ?: it.likeCount).coerceAtLeast(0).toUInt() }
            val heat = if (hasTiming) lyricLikeHeat(starts, counts, durationMs.toLong(), 60u) else null
            ImasLikeHeatSeekBar(
                levels = heat?.levels ?: emptyList(),
                progress = if (isFullLoaded) (positionMs ?: 0).toDouble() / durationMs else null,
                peak = heat?.peakMs?.let { it.toDouble() / durationMs },
                seed = seed,
                allowsScrub = true,
                onSeek = { fraction -> scope.launch { playback.startFull(song.id, song.appleMusicId ?: ""); playback.seek((fraction * durationMs).toInt()) } }
            )
            Row(Modifier.fillMaxWidth()) {
                ImasText(imasLyricClock(positionMs ?: 0), ImasTextRole.IMPRINT, color = DS.ink3)
                Spacer(Modifier.weight(1f))
                ImasText("-" + imasLyricClock(maxOf(0, durationMs - (positionMs ?: 0))), ImasTextRole.IMPRINT, color = DS.ink3)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.sp8), verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                ImasIconButton(icon = Icons.Filled.Replay10, label = "10 秒戻す", onClick = { playback.seek(maxOf(0, (positionMs ?: 0) - 10_000)) })
                ImasIconButton(
                    icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    label = if (isPlaying) "一時停止" else "再生",
                    style = ImasIconButtonStyle.FILLED,
                    onClick = {
                        if (isFullLoaded) playback.togglePlay()
                        else scope.launch { startFailed = !playback.startFull(song.id, song.appleMusicId ?: "") }
                    }
                )
                ImasIconButton(icon = Icons.Filled.Forward10, label = "10 秒進める", onClick = { playback.seek(minOf(durationMs, (positionMs ?: 0) + 10_000)) })
                Spacer(Modifier.weight(1f))
            }
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun LyricsPlayerRow(
    line: LyricLine,
    hasTiming: Boolean,
    isLiked: Boolean,
    isActive: Boolean,
    isOverlayActive: Boolean,
    seed: String?,
    onTap: () -> Unit,
    onDoubleTap: () -> Unit
) {
    if (line.kind == LyricLineKind.BLANK) {
        Spacer(Modifier.height(DS.sp3))
        return
    }
    val isCurrent = !hasTiming || isActive
    Column(
        Modifier
            .fillMaxWidth()
            .padding(vertical = DS.sp1)
            .combinedClickable(onClick = onTap, onDoubleClick = onDoubleTap)
    ) {
        if (line.isOverlay) {
            val overlay = lyricOverlaySplit(line.text).overlay ?: line.text
            ImasPlayerOverlayLine(text = overlay, isCurrent = !hasTiming || isOverlayActive, seed = seed)
        } else {
            val split = lyricOverlaySplit(line.text)
            ImasPlayerLyricLine(
                text = split.main.ifEmpty { line.text }, isCurrent = isCurrent,
                isMarker = line.kind == LyricLineKind.MARKER, isLiked = isLiked, seed = seed
            )
            val overlayText = split.overlay
            if (overlayText != null && split.main.isNotEmpty()) {
                ImasPlayerOverlayLine(text = overlayText, isCurrent = isCurrent, seed = seed)
            }
        }
        if (line.calls.isNotEmpty()) {
            ImasCallRows(calls = line.calls, anchorIndexes = null)
        }
    }
}

@Composable
private fun CallLane(allCalls: List<LyricCall>, callStarts: List<Long?>, positionMs: Int, seed: String?) {
    if (callStarts.none { it != null }) return
    val theme = imasTheme(seed = seed)
    val current = lyricActiveCall(callStarts, positionMs.toLong())?.toInt()
    val next = callStarts.withIndex().filter { (it.value ?: -1L) > positionMs.toLong() }.minByOrNull { it.value ?: 0L }?.index
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.sp2), verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Campaign, contentDescription = null, tint = if (current != null) theme.accent else DS.ink3)
        when {
            current != null -> ImasText(allCalls[current].text, ImasTextRole.ROW_TITLE, color = allCalls[current].emphasis.lyricColor(theme.accent), maxLines = 1)
            next != null -> ImasText("次 " + allCalls[next].text, ImasTextRole.ROW_LABEL, color = DS.ink3, maxLines = 1)
            else -> ImasText("—", ImasTextRole.ROW_LABEL, color = DS.ink3)
        }
    }
}
