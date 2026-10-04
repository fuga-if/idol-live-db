package com.fugaif.imaslivedb.ui.lyrics

import android.content.Context
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.automirrored.filled.PlaylistAdd
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Forward10
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.MobileOff
import androidx.compose.material.icons.filled.Replay10
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.foundation.layout.IntrinsicSize
import com.fugaif.imaslivedb.data.lyrics.LyricLine
import com.fugaif.imaslivedb.data.lyrics.LyricLineKind
import com.fugaif.imaslivedb.data.lyrics.LyricPartCast
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLikeHeatSeekBar
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPartNames
import com.fugaif.imaslivedb.ui.designsystem.ImasPartStripe
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerCallLine
import com.fugaif.imaslivedb.ui.designsystem.ImasEcho
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerLyricLine
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerOverlayLine
import com.fugaif.imaslivedb.ui.designsystem.LocalImasHaze
import com.fugaif.imaslivedb.ui.designsystem.imasFloatingChrome
import com.fugaif.imaslivedb.ui.designsystem.imasHazeSource
import com.fugaif.imaslivedb.ui.designsystem.imasLyricClock
import com.fugaif.imaslivedb.ui.designsystem.lyricColor
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.imas_core.lyricActiveCall
import uniffi.imas_core.lyricActiveLine
import uniffi.imas_core.lyricActiveOverlay
import uniffi.imas_core.lyricHasTiming
import uniffi.imas_core.lyricLikeHeat
import uniffi.imas_core.lyricMainRange
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
    onClose: () -> Unit,
    cast: LyricPartCast = LyricPartCast.EMPTY
) {
    val context = LocalContext.current
    val module = AppModule.from(context)
    val playback = module.lyricsPlayback
    val scope = rememberCoroutineScope()
    val haptics = rememberImasHaptics()

    var positionMs by remember { mutableStateOf<Int?>(null) }
    var activeLineId by remember { mutableStateOf<String?>(null) }
    var activeOverlayId by remember { mutableStateOf<String?>(null) }
    // いま出しているコールの添字 (曲の順)。変わった瞬間に震わせる (コール練習。iOS `LyricsPlayerView` と対)。
    var activeCallIndex by remember { mutableStateOf<Int?>(null) }
    // コールのタイミングで震わせるか。既定オン (iOS `@AppStorage("lyrics.call_haptics")` と同じ鍵)。
    var callHaptics by remember {
        mutableStateOf(context.getSharedPreferences(CALL_HAPTICS_PREFS, Context.MODE_PRIVATE).getBoolean(CALL_HAPTICS_KEY, true))
    }
    fun toggleCallHaptics() {
        callHaptics = !callHaptics
        context.getSharedPreferences(CALL_HAPTICS_PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(CALL_HAPTICS_KEY, callHaptics).apply()
    }
    var startFailed by remember { mutableStateOf(false) }
    var likes by remember { mutableStateOf(setOf<String>()) }
    var showsAddToPlaylist by remember { mutableStateOf(false) }
    var showsQueue by remember { mutableStateOf(false) }

    val starts = remember(lyrics) { lyrics.lines.map { it.startMs?.toLong() } }
    val mainStarts = remember(lyrics) { lyrics.lines.map { if (it.isOverlay) null else it.startMs?.toLong() } }
    val overlayStarts = remember(lyrics) { lyrics.lines.map { if (it.isOverlay) it.startMs?.toLong() else null } }
    val allCalls = remember(lyrics) { lyrics.lines.flatMap { it.calls } }
    val callStarts = remember(allCalls) { allCalls.map { it.startMs?.toLong() } }
    // いま出しているコールの id (iOS `activeCallId`)。
    val activeCallId = activeCallIndex?.let { allCalls.getOrNull(it)?.id }
    val hasTiming = remember(starts) { lyricHasTiming(starts) }
    val loadedSongId by playback.loadedSongId.collectAsState()
    val isPlaying by playback.isPlaying.collectAsState()
    val appleMusic by playback.appleMusicState.collectAsState()
    val hasQueue by playback.hasQueue.collectAsState()
    val canSkipNext by playback.canSkipNext.collectAsState()
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
                // コール練習: 次のコールに入った瞬間だけ震わせる (コールが切れたときは震わせない)。
                val callIndex = lyricActiveCall(callStarts, ms.toLong())?.toInt()
                if (callIndex != activeCallIndex) {
                    activeCallIndex = callIndex
                    if (callIndex != null && callHaptics && isPlaying) haptics.impactHeavy()
                }
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

    // 歌詞は画面いっぱいに流し、頭と下の操作はその上に浮かべる (API 31 以降は下の操作がガラスで、
    // 後ろを流れる歌詞が透けて見える)。紙面の歌詞そのものは平らなまま。iOS `LyricsPlayerView` と対。
    Box(Modifier.fillMaxSize().background(DS.bg)) {
        val hazeState = remember { HazeState() }
        var headerHeightPx by remember { mutableIntStateOf(0) }
        var controlsHeightPx by remember { mutableIntStateOf(0) }
        val density = LocalDensity.current

        CompositionLocalProvider(LocalImasHaze provides hazeState) {
            // 歌詞
            val listState = rememberLazyListState()
            LaunchedEffect(activeLineId) {
                val id = activeLineId ?: return@LaunchedEffect
                val index = lyrics.lines.indexOfFirst { it.id == id }
                if (index >= 0) listState.animateScrollToItem(maxOf(0, index - 1))
            }
            LazyColumn(
                modifier = Modifier.fillMaxSize().imasHazeSource(),
                state = listState,
                contentPadding = PaddingValues(
                    start = DS.sp5,
                    end = DS.sp5,
                    top = with(density) { headerHeightPx.toDp() },
                    bottom = with(density) { controlsHeightPx.toDp() } + DS.sp3
                )
            ) {
                item {
                    if (!hasTiming) {
                        Column(Modifier.padding(vertical = DS.sp4)) {
                            ImasNote("この曲はまだ行の時刻が記録されていないので、追従できません。")
                            Spacer(Modifier.height(DS.sp3))
                            ImasButton(title = "タイミングを記録する", onClick = onEditTimings, role = ImasButtonRole.SECONDARY)
                        }
                    }
                    AppleMusicSignInNotice(appleMusic, onSignIn = playback::signIn, modifier = Modifier.padding(vertical = DS.sp2))
                    // 繋がっているのに始められなかった (曲が Apple Music に無い等) ときだけ出す。
                    if (startFailed && appleMusic == com.fugaif.imaslivedb.player.AppleMusicState.READY) {
                        ImasNote("この曲は Apple Music で鳴らせませんでした。", modifier = Modifier.padding(vertical = DS.sp2))
                    }
                }
                itemsIndexed(lyrics.lines) { _, line ->
                    LyricsPlayerRow(
                        line = line, hasTiming = hasTiming, isLiked = likes.contains(line.id),
                        isActive = line.id == activeLineId, isOverlayActive = line.id == activeOverlayId,
                        activeCallId = activeCallId,
                        seed = seed, cast = cast,
                        onTap = {
                            val start = line.startMs ?: return@LyricsPlayerRow
                            scope.launch { playback.startFull(song.id, song.appleMusicId ?: ""); playback.seek(start) }
                        },
                        onDoubleTap = { like(line) }
                    )
                }
            }

            // 頭 (地は平らな実のまま。ガラスにしない)
            Row(
                Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .onSizeChanged { headerHeightPx = it.height }
                    .background(DS.bg)
                    .padding(horizontal = DS.sp5, vertical = DS.sp4),
                horizontalArrangement = Arrangement.spacedBy(DS.sp4),
                verticalAlignment = Alignment.CenterVertically
            ) {
                ArtworkImage(url = song.artworkUrl, size = 52.dp, previewUrl = null, songTitle = song.title, songId = song.id, seed = seed, brand = song.brandId)
                Column(Modifier.weight(1f)) {
                    ImasText(song.title, ImasTextRole.ROW_TITLE, maxLines = 1)
                    if (!artistLine.isNullOrEmpty()) ImasText(artistLine, ImasTextRole.ROW_SUBTITLE, maxLines = 1)
                }
                if (allCalls.isNotEmpty()) {
                    ImasIconButton(
                        icon = if (callHaptics) Icons.Filled.Vibration else Icons.Filled.MobileOff,
                        label = if (callHaptics) "コールで震わせる: オン" else "コールで震わせる: オフ",
                        onClick = ::toggleCallHaptics,
                        size = ImasIconButtonSize.SMALL,
                        style = ImasIconButtonStyle.PLAIN
                    )
                }
                ImasIconButton(
                    icon = Icons.AutoMirrored.Filled.PlaylistAdd,
                    label = "プレイリストに追加",
                    onClick = { showsAddToPlaylist = true },
                    style = ImasIconButtonStyle.PLAIN
                )
                ImasIconButton(icon = Icons.Filled.Speed, label = "タイミングを編集", onClick = onEditTimings, style = ImasIconButtonStyle.PLAIN)
                ImasIconButton(icon = Icons.Filled.ExpandMore, label = "閉じる", onClick = onClose, style = ImasIconButtonStyle.PLAIN)
            }

            // 下の操作 (浮いている枠。API 31 以降は後ろの歌詞が透けて見えるガラス)
            Column(
                Modifier
                    .align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .onSizeChanged { controlsHeightPx = it.height }
                    .padding(horizontal = DS.sp4, vertical = DS.sp4)
                    .imasFloatingChrome()
                    .padding(horizontal = DS.sp3, vertical = DS.sp3),
                verticalArrangement = Arrangement.spacedBy(DS.sp3)
            ) {
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
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    ImasText(imasLyricClock(positionMs ?: 0), ImasTextRole.IMPRINT, color = DS.ink3)
                    Spacer(Modifier.weight(1f))
                    if (isFullLoaded) {
                        // 次に流れる曲と自動再生 (∞) は、Apple Music と同じく下の操作の並びに置く。
                        ImasIconButton(
                            icon = Icons.AutoMirrored.Filled.List,
                            label = "次に流れる曲",
                            size = ImasIconButtonSize.SMALL,
                            style = ImasIconButtonStyle.PLAIN,
                            onClick = { showsQueue = true }
                        )
                        Spacer(Modifier.weight(1f))
                    }
                    ImasText("-" + imasLyricClock(maxOf(0, durationMs - (positionMs ?: 0))), ImasTextRole.IMPRINT, color = DS.ink3)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(DS.sp8), verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.weight(1f))
                    if (hasQueue) {
                        ImasIconButton(icon = Icons.Filled.SkipPrevious, label = "前の曲", onClick = { playback.skipPrevious() })
                    }
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
                    if (hasQueue) {
                        ImasIconButton(icon = Icons.Filled.SkipNext, label = "次の曲", enabled = canSkipNext, onClick = { playback.skipNext() })
                    }
                    Spacer(Modifier.weight(1f))
                }
            }
        }
    }

    if (showsAddToPlaylist) {
        Dialog(onDismissRequest = { showsAddToPlaylist = false }) {
            com.fugaif.imaslivedb.ui.playlists.AddToPlaylistSheet(
                song = song,
                onDismiss = { showsAddToPlaylist = false }
            )
        }
    }
    if (showsQueue) {
        PlayQueueSheet(playback = playback, onDismiss = { showsQueue = false })
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
    activeCallId: String?,
    seed: String?,
    cast: LyricPartCast,
    onTap: () -> Unit,
    onDoubleTap: () -> Unit
) {
    if (line.kind == LyricLineKind.BLANK) {
        Spacer(Modifier.height(DS.sp3))
        return
    }
    val isCurrent = !hasTiming || isActive
    val theme = imasTheme(seed = seed)
    Row(
        Modifier
            .fillMaxWidth()
            .height(IntrinsicSize.Min)
            .padding(vertical = DS.sp1)
            .combinedClickable(onClick = onTap, onDoubleClick = onDoubleTap),
        horizontalArrangement = Arrangement.spacedBy(DS.sp3)
    ) {
        if (line.singers.isNotEmpty()) ImasPartStripe(colors = cast.colors(line.singers))
        Column(Modifier.weight(1f)) {
            if (line.isOverlay) {
                val overlay = lyricOverlaySplit(line.text).overlay ?: line.text
                ImasPlayerOverlayLine(text = overlay, isCurrent = !hasTiming || isOverlayActive, seed = seed)
            } else {
                val split = lyricOverlaySplit(line.text)
                ImasPlayerLyricLine(
                    text = split.main.ifEmpty { line.text }, isCurrent = isCurrent,
                    isMarker = line.kind == LyricLineKind.MARKER, isLiked = isLiked,
                    // 被せを外したメインの行の中の位置に置き直す (被せに掛かるものは印を付けない)。
                    echoes = line.calls.filter { line.echoes(it) }.mapNotNull { call ->
                        lyricMainRange(line.text, call.start.toUInt(), call.end.toUInt())?.let { range ->
                            ImasEcho(start = range.start.toInt(), end = range.end.toInt(), isActive = call.id == activeCallId)
                        }
                    },
                    seed = seed
                )
                val overlayText = split.overlay
                if (overlayText != null && split.main.isNotEmpty()) {
                    ImasPlayerOverlayLine(text = overlayText, isCurrent = isCurrent, seed = seed)
                }
            }
            ImasPartNames(names = cast.names(line.singers))
            // コールは行の直下に流す。いま出すコールだけ大きく点ける (歌詞と同じ文字のものは
            // 行に出さず、上の歌詞を点ける)。
            line.calls.filter { !line.echoes(it) }.forEach { call ->
                ImasPlayerCallLine(
                    marker = if (call.hasAnchor) "↳" else "»",
                    text = call.text,
                    color = call.emphasis.lyricColor(theme.accent),
                    isActive = call.id == activeCallId
                )
            }
        }
    }
}

/** コール練習の震えの設定 (iOS `@AppStorage("lyrics.call_haptics")` と同じ鍵)。 */
private const val CALL_HAPTICS_PREFS = "imas_settings"
private const val CALL_HAPTICS_KEY = "lyrics.call_haptics"
