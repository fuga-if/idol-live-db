package com.fugaif.imaslivedb.ui.songs

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.fugaif.imaslivedb.data.lyrics.CallEmphasis
import com.fugaif.imaslivedb.data.lyrics.LyricJoiner
import com.fugaif.imaslivedb.data.lyrics.LyricLine
import com.fugaif.imaslivedb.data.lyrics.LyricLineKind
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.lyrics.LyricsResult
import com.fugaif.imaslivedb.data.lyrics.StructureChange
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasBadge
import com.fugaif.imaslivedb.ui.designsystem.ImasBadgeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCallLegend
import com.fugaif.imaslivedb.ui.designsystem.ImasCallRows
import com.fugaif.imaslivedb.ui.designsystem.ImasClapGlyph
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasLikeHeatSeekBar
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLikeMark
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLineRow
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLineState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.lyricColor
import com.fugaif.imaslivedb.ui.lyrics.LyricTimingEditorScreen
import com.fugaif.imaslivedb.ui.lyrics.LyricTimingRecorder
import com.fugaif.imaslivedb.ui.lyrics.LyricsPlayerScreen
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.imas_core.lyricActiveLine
import uniffi.imas_core.lyricChunks
import uniffi.imas_core.lyricHasTiming
import uniffi.imas_core.lyricLikeHeat

/**
 * 楽曲詳細の歌詞タブ。iOS `SongLyricsTab` の移植 (= 実質コールガイド)。
 *
 * コールの編集 (iOS `CallGuideEditorModel` / 範囲選択してコールを付ける導線) はこの移植の
 * 対象外。閲覧・ここ好き・行の時刻の記録・行の区切りの編集だけをここに持つ。
 *
 * 歌詞は曲詳細のタブを開いたときに [SongDetailViewModel] が 1 回だけ取りに行く (タブを
 * 開いても追加のリクエストは飛ばない設計は iOS と同じだが、Android は束ね取得が無いので
 * 歌詞タブを初めて開いたときに [LyricsApi.lyrics] を呼ぶ形)。
 *
 * ⚠️ JASRAC / NexTone 許諾の条件により、歌詞は保存も一括取得もさせない:
 * - 本文にテキスト選択 (`SelectionContainer`) や共有の口を**付けない**。
 * - コールの保存で歌詞本文を送らない ([LyricsApi.saveTimings] / `editStructure` は
 *   行 ID・位置・時刻しか送らない)。
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SongLyricsTab(
    song: Song,
    seed: String?,
    artistLine: String?,
    lyricsResult: LyricsResult?,
    isLyricsLoading: Boolean,
    onReload: () -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val module = AppModule.from(context)
    val scope = rememberCoroutineScope()
    val authState by module.authService.state.collectAsState()
    val canEdit = authState.isSignedIn

    var isEditingStructure by remember { mutableStateOf(false) }
    var structureBusyLineId by remember { mutableStateOf<String?>(null) }
    var structureMenuLineId by remember { mutableStateOf<String?>(null) }
    var structureError by remember { mutableStateOf<String?>(null) }
    var showPlayer by remember { mutableStateOf(false) }
    var recorder by remember { mutableStateOf<LyricTimingRecorder?>(null) }
    var recordUnavailable by remember { mutableStateOf(false) }
    var activeLineId by remember { mutableStateOf<String?>(null) }
    var likes by remember { mutableStateOf(setOf<String>()) }
    var likeCounts by remember { mutableStateOf(mapOf<String, Int>()) }
    var heatTick by remember { mutableStateOf(0) }

    val lyrics = (lyricsResult as? LyricsResult.Loaded)?.lyrics
    val playback = module.lyricsPlayback

    LaunchedEffect(song.id) { likes = module.userMarkRepository.lyricLikes(song.id) }

    // ここ好きの山のシークバーの進み (0.5 秒ごと)。再生中だけ描き直せば足りるが、
    // 判定を複雑にしないため常時軽く回す (iOS `TimelineView(.periodic(from:by:))` と同じ意図)。
    LaunchedEffect(Unit) { while (true) { delay(500); heatTick++ } }

    // 再生に追従している今の行。記録中・区切り編集中は出さない。
    LaunchedEffect(lyrics?.updatedAt, isEditingStructure, recorder) {
        if (lyrics == null || isEditingStructure || recorder != null) { activeLineId = null; return@LaunchedEffect }
        val starts = lyrics.startsForCore
        if (!lyricHasTiming(starts)) { activeLineId = null; return@LaunchedEffect }
        while (true) {
            if (playback.loadedSongId.value == song.id) {
                val ms = playback.positionMs()
                if (ms != null) {
                    val index = lyricActiveLine(starts, ms.toLong())?.toInt()
                    activeLineId = index?.let { lyrics.lines[it].id }
                }
            }
            delay(200)
        }
    }

    fun toggleLike(line: LyricLine) {
        scope.launch {
            val now = module.userMarkRepository.toggleLyricLike(song.id, line.id)
            likes = if (now) likes + line.id else likes - line.id
            if (authState.isSignedIn) {
                runCatching { module.lyricsApi.setLike(song.id, line.id, now) }.getOrNull()?.let {
                    likeCounts = likeCounts + (line.id to it)
                }
            }
        }
    }

    suspend fun beginRecording(current: Lyrics) {
        if (playback.loadedSongId.value != song.id) {
            val ok = playback.startFull(song.id, song.appleMusicId ?: "")
            if (!ok) { recordUnavailable = true; return }
        }
        recorder = LyricTimingRecorder(current, song.id)
    }

    fun changeStructure(lineId: String, change: StructureChange) {
        if (structureBusyLineId != null) return
        structureBusyLineId = lineId
        scope.launch {
            try {
                module.lyricsApi.editStructure(song.id, change)
                onReload()
            } catch (e: Exception) {
                structureError = e.message ?: "行の区切りを変えられませんでした"
            } finally {
                structureBusyLineId = null
            }
        }
    }

    Column(modifier.padding(top = DS.sp4).padding(horizontal = DS.sp5)) {
        when {
            isLyricsLoading || lyricsResult == null -> ImasInlineLoading()
            lyricsResult is LyricsResult.Failed -> ImasEmptyState(
                ImasEmptyStateKind.FAILED, title = "歌詞を表示できません",
                message = lyricsResult.message, actionTitle = "再試行", onAction = onReload
            )
            lyricsResult is LyricsResult.NotLicensed -> ImasEmptyState(
                icon = Icons.Filled.VisibilityOff, title = "この曲の歌詞は Android ではまだ表示できません"
            )
            lyricsResult is LyricsResult.NeedsLogin -> ImasEmptyState(
                ImasEmptyStateKind.SIGN_IN_REQUIRED, title = "歌詞の表示にはログインが必要です",
                message = "ログインすると、登録済みの曲の歌詞を表示できます。"
            )
            lyricsResult is LyricsResult.NotFound || lyrics == null || !lyrics.hasContent -> ImasEmptyState(
                icon = Icons.Filled.FormatQuote, title = "歌詞はまだありません",
                message = "この曲の歌詞はまだ登録されていません。"
            )
            else -> {
                if (lyrics.isDraft) {
                    ImasBadge(
                        text = "下書き（未公開）。この表示は管理者のみ", kind = ImasBadgeKind.ATTENTION,
                        modifier = Modifier.padding(bottom = DS.sp2)
                    )
                }
                EditBar(
                    canEdit = canEdit, isEditingStructure = isEditingStructure,
                    onToggleStructureEdit = { isEditingStructure = !isEditingStructure },
                    onOpenPlayer = { showPlayer = true },
                    onBeginRecording = { scope.launch { beginRecording(lyrics) } }
                )
                if (isEditingStructure) {
                    ImasNote(
                        "語をタップすると、その語の前で行を切り離します。行の右下の鎖のボタンで次の行とくっつけます。歌詞の文字は変わりません。",
                        modifier = Modifier.padding(vertical = DS.sp2)
                    )
                    LyricsCard(song.title, artistLine) {
                        StructureBody(
                            lyrics = lyrics, busyLineId = structureBusyLineId,
                            menuLineId = structureMenuLineId,
                            onOpenMenu = { structureMenuLineId = it },
                            onCloseMenu = { structureMenuLineId = null },
                            onSplit = { lineId, at -> changeStructure(lineId, StructureChange.Split(lineId, at)) },
                            onMerge = { lineId, joiner -> changeStructure(lineId, StructureChange.Merge(lineId, joiner)) }
                        )
                    }
                } else {
                    LyricsCard(song.title, artistLine) {
                        ViewingBody(
                            lyrics = lyrics, seed = seed, likes = likes, activeLineId = activeLineId,
                            heatTick = heatTick, song = song,
                            onToggleLike = ::toggleLike
                        )
                    }
                }
                if (!lyrics.source.isNullOrEmpty()) {
                    ImasNote("出典: ${lyrics.source}", modifier = Modifier.padding(top = DS.sp2))
                }
            }
        }
        if (lyrics != null) NexToneLicenseNotice()
    }

    if (showPlayer && lyrics != null) {
        Dialog(onDismissRequest = { showPlayer = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LyricsPlayerScreen(
                song = song, seed = seed, artistLine = artistLine, lyrics = lyrics,
                likeCounts = likeCounts, onLikeCountChanged = { id, count -> likeCounts = likeCounts + (id to count) },
                onEditTimings = { showPlayer = false; scope.launch { beginRecording(lyrics) } },
                onClose = { showPlayer = false }
            )
        }
    }
    val activeRecorder = recorder
    if (activeRecorder != null && lyrics != null) {
        Dialog(onDismissRequest = {}, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LyricTimingEditorScreen(
                song = song, seed = seed, lyrics = lyrics, recorder = activeRecorder,
                onSaved = onReload, onClose = { recorder = null }
            )
        }
    }
    ImasErrorAlert(message = structureError, onDismiss = { structureError = null }, title = "保存できませんでした")
    ImasErrorAlert(
        message = if (recordUnavailable) "記録には Apple Music でのフル再生が必要です。" else null,
        onDismiss = { recordUnavailable = false }, title = "タイミングを記録できません"
    )
}

@Composable
private fun LyricsCard(title: String, artistLine: String?, content: @Composable () -> Unit) {
    com.fugaif.imaslivedb.ui.designsystem.ImasCard {
        ImasText(title, ImasTextRole.CARD_TITLE, modifier = Modifier.padding(bottom = DS.sp2))
        if (!artistLine.isNullOrEmpty()) ImasText(artistLine, ImasTextRole.NOTE, modifier = Modifier.padding(bottom = DS.sp3))
        content()
    }
}

@Composable
private fun EditBar(
    canEdit: Boolean,
    isEditingStructure: Boolean,
    onToggleStructureEdit: () -> Unit,
    onOpenPlayer: () -> Unit,
    onBeginRecording: () -> Unit
) {
    if (!canEdit) return
    Row(Modifier.fillMaxWidth().padding(bottom = DS.sp2), horizontalArrangement = Arrangement.spacedBy(DS.sp3)) {
        Spacer(Modifier.weight(1f))
        if (isEditingStructure) {
            ImasButton(title = "区切りの編集を終了", role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL, onClick = onToggleStructureEdit)
        } else {
            ImasIconButton(icon = Icons.Filled.ContentCut, label = "行の区切りを編集", size = ImasIconButtonSize.SMALL, onClick = onToggleStructureEdit)
            ImasIconButton(icon = Icons.Filled.QueueMusic, label = "歌詞プレイヤー", size = ImasIconButtonSize.SMALL, onClick = onOpenPlayer)
            ImasIconButton(icon = Icons.Filled.Speed, label = "タイミングを編集", size = ImasIconButtonSize.SMALL, onClick = onBeginRecording)
        }
    }
}

// MARK: - 閲覧

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ViewingBody(
    lyrics: Lyrics,
    seed: String?,
    likes: Set<String>,
    activeLineId: String?,
    heatTick: Int,
    song: Song,
    onToggleLike: (LyricLine) -> Unit
) {
    val emphases = lyrics.usedEmphases
    val claps = lyrics.usedClaps
    val showsOverTiming = lyrics.usesOverTiming
    if (emphases.isNotEmpty() || claps.isNotEmpty() || showsOverTiming) {
        ImasCallLegend(emphases, claps, showsOverTiming, modifier = Modifier.padding(bottom = DS.sp4))
    }
    LikeHeatBar(lyrics = lyrics, seed = seed, song = song, heatTick = heatTick)
    if (likes.isEmpty()) {
        ImasNote("好きな行をダブルタップで「ここ好き」", modifier = Modifier.padding(bottom = DS.sp3))
    }
    val theme = imasTheme(seed = seed)
    lyrics.lines.forEach { line ->
        val state = if (line.id == activeLineId) ImasLyricLineState.CURRENT else ImasLyricLineState.NORMAL
        ImasLyricLineRow(state = state, seed = seed) {
            ViewingRow(line = line, isLiked = likes.contains(line.id), accent = theme.accent, onToggleLike = onToggleLike)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ViewingRow(line: LyricLine, isLiked: Boolean, accent: Color, onToggleLike: (LyricLine) -> Unit) {
    when (line.kind) {
        LyricLineKind.LYRIC -> {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(vertical = DS.sp1)
                    .combinedClickable(onClick = {}, onDoubleClick = { onToggleLike(line) }),
                horizontalArrangement = Arrangement.spacedBy(DS.sp2),
                verticalAlignment = Alignment.Top
            ) {
                ImasClapGlyph(clap = line.clap, modifier = Modifier.padding(top = DS.sp1))
                Column(Modifier.weight(1f)) {
                    // ⚠️ ここに SelectionContainer / テキストコピーの口を足さないこと。
                    Text(
                        text = highlightedLyricText(line.text, highlightsFor(line, accent)),
                        style = com.fugaif.imaslivedb.ui.theme.ImasTextRole.BODY.style,
                        color = DS.ink
                    )
                    if (line.calls.isNotEmpty()) ImasCallRows(calls = line.calls, anchorIndexes = anchorIndexesFor(line))
                }
                if (isLiked) ImasLyricLikeMark(seed = null, modifier = Modifier.padding(top = DS.sp1))
            }
        }
        LyricLineKind.MARKER -> {
            Column(Modifier.fillMaxWidth()) {
                SectionMarker(line.text)
                if (line.calls.isNotEmpty()) {
                    ImasCallRows(calls = line.calls, anchorIndexes = null, modifier = Modifier.padding(bottom = DS.sp3))
                }
            }
        }
        LyricLineKind.BLANK -> Spacer(Modifier.height(DS.sp5))
    }
}

/** 「イントロ」「サビ」等の構成マーカー。歌詞本文と混ざらないよう罫線で挟む。 */
@Composable
private fun SectionMarker(text: String) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = DS.sp3),
        horizontalArrangement = Arrangement.spacedBy(DS.sp3),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.weight(1f).height(1.dp).background(DS.sep))
        ImasText(text, ImasTextRole.EYEBROW)
        Box(Modifier.weight(1f).height(1.dp).background(DS.sep))
    }
}

@Composable
private fun LikeHeatBar(lyrics: Lyrics, seed: String?, song: Song, heatTick: Int) {
    val module = AppModule.from(LocalContext.current)
    val playback = module.lyricsPlayback
    val starts = lyrics.startsForCore
    if (!lyricHasTiming(starts)) return
    val scope = rememberCoroutineScope()
    val counts = lyrics.lines.map { it.likeCount.coerceAtLeast(0).toUInt() }
    val lastStart = starts.filterNotNull().maxOrNull() ?: 0
    val duration = playback.durationMs() ?: song.durationSec?.let { it * 1000 } ?: (lastStart.toInt() + 8000)
    val heat = lyricLikeHeat(starts, counts, duration.toLong(), 60u)
    val isFullLoaded = playback.loadedSongId.value == song.id
    // heatTick の変化を読むことで 0.5 秒ごとに再描画し、進みの線を再生に追従させる。
    @Suppress("UNUSED_EXPRESSION") heatTick
    if (!isFullLoaded && heat.levels.isEmpty()) return
    Column(Modifier.padding(bottom = DS.sp4)) {
        if (heat.levels.isNotEmpty()) ImasText("みんなのここ好き", ImasTextRole.META)
        ImasLikeHeatSeekBar(
            levels = heat.levels,
            progress = if (isFullLoaded) playback.positionMs()?.let { it.toDouble() / duration } else null,
            peak = heat.peakMs?.let { it.toDouble() / duration },
            seed = seed,
            onSeek = { fraction ->
                scope.launch { playback.startFull(song.id, song.appleMusicId ?: ""); playback.seek((fraction * duration).toInt()) }
            }
        )
    }
}

// MARK: - 行の区切り (くっつける / 切り離す)

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun StructureBody(
    lyrics: Lyrics,
    busyLineId: String?,
    menuLineId: String?,
    onOpenMenu: (String) -> Unit,
    onCloseMenu: () -> Unit,
    onSplit: (String, Int) -> Unit,
    onMerge: (String, LyricJoiner) -> Unit
) {
    lyrics.lines.forEachIndexed { index, line ->
        when (line.kind) {
            LyricLineKind.LYRIC -> {
                Column(Modifier.fillMaxWidth().padding(bottom = DS.sp1)) {
                    FlowRow(
                        modifier = Modifier.alpha(if (busyLineId == line.id) 0.4f else 1f)
                    ) {
                        lyricChunks(line.text).forEach { chunk ->
                            Text(
                                chunk.text,
                                style = com.fugaif.imaslivedb.ui.theme.ImasTextRole.BODY.style,
                                color = DS.ink,
                                modifier = Modifier.combinedClickableSimple {
                                    if (chunk.start > 0u) onSplit(line.id, chunk.start.toInt())
                                }
                            )
                        }
                    }
                    val nextIsLyric = index + 1 < lyrics.lines.size && lyrics.lines[index + 1].kind == LyricLineKind.LYRIC
                    if (nextIsLyric) {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                            Box {
                                ImasIconButton(
                                    icon = Icons.Filled.Link, label = "次の行とくっつける",
                                    size = ImasIconButtonSize.SMALL, enabled = busyLineId == null,
                                    onClick = { onOpenMenu(line.id) }
                                )
                                DropdownMenu(expanded = menuLineId == line.id, onDismissRequest = onCloseMenu) {
                                    LyricJoiner.entries.forEach { joiner ->
                                        DropdownMenuItem(
                                            text = { Text(joiner.label) },
                                            onClick = { onCloseMenu(); onMerge(line.id, joiner) }
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            LyricLineKind.MARKER -> SectionMarker(line.text)
            LyricLineKind.BLANK -> Spacer(Modifier.height(DS.sp5))
        }
    }
}

@Composable
private fun Modifier.combinedClickableSimple(onClick: () -> Unit): Modifier =
    this.clickable(
        interactionSource = remember { MutableInteractionSource() },
        indication = null,
        onClick = onClick
    )

// MARK: - アンカーの見せ方

/**
 * 行内のアンカーごとの色。同じ範囲に複数のコールが載っているときは**強い方**の色で敷く
 * (演者要望 > おこのみで > 通常)。iOS `SongLyricsTab.highlights(for:)` と同じ規則。
 */
@Composable
private fun highlightsFor(line: LyricLine, accent: Color): List<LyricHighlight> {
    val order = mutableListOf<String>()
    val strongest = mutableMapOf<String, com.fugaif.imaslivedb.data.lyrics.LyricCall>()
    for (call in line.calls.filter { it.hasAnchor }) {
        val key = "${call.start}-${call.end}"
        val current = strongest[key]
        if (current == null) {
            order.add(key)
            strongest[key] = call
        } else if (rank(call.emphasis) > rank(current.emphasis)) {
            strongest[key] = call
        }
    }
    return order.mapNotNull { key -> strongest[key]?.let { LyricHighlight(it.start, it.end, it.emphasis.lyricColor(accent)) } }
}

private fun rank(emphasis: CallEmphasis): Int = when (emphasis) {
    CallEmphasis.NORMAL -> 0
    CallEmphasis.OPTIONAL -> 1
    CallEmphasis.PERFORMER_REQUEST -> 2
}

/**
 * 同じ行に複数のアンカーがあるときだけ ①②③ を振る (iOS `SongLyricsTab.anchorIndexes(for:)`)。
 * 1 つしか無い行に番号を振っても情報が増えないので null を返す。
 */
private fun anchorIndexesFor(line: LyricLine): Map<String, Int>? {
    val groups = mutableMapOf<String, Int>()
    val result = mutableMapOf<String, Int>()
    var order = 0
    for (call in line.calls.filter { it.hasAnchor }) {
        val key = "${call.start}-${call.end}"
        if (groups[key] == null) { groups[key] = order; order++ }
        result[call.id] = groups[key]!!
    }
    return if (order > 1) result else null
}

private data class LyricHighlight(val start: Int, val end: Int, val color: Color)

/**
 * アンカー範囲に色を敷いた行を組み立てる (iOS `CallGuideText.attributed`)。
 *
 * ⚠️ `start`/`end` は Unicode スカラー (= Java の codePoint) 単位。Kotlin の `String` は
 * UTF-16 なので、絵文字などサロゲートペアを含む行では文字添字への変換が必要 ([codePointToCharIndex])。
 */
private fun highlightedLyricText(text: String, highlights: List<LyricHighlight>): AnnotatedString {
    if (highlights.isEmpty()) return AnnotatedString(text)
    val totalScalars = text.codePointCount(0, text.length)
    return buildAnnotatedString {
        var cursor = 0
        for (h in highlights.sortedBy { it.start }) {
            val s = maxOf(h.start, cursor)
            val e = minOf(h.end, totalScalars)
            if (s >= e) continue
            if (s > cursor) append(text.substring(codePointToCharIndex(text, cursor), codePointToCharIndex(text, s)))
            withStyle(SpanStyle(background = h.color.copy(alpha = 0.18f), textDecoration = TextDecoration.Underline)) {
                append(text.substring(codePointToCharIndex(text, s), codePointToCharIndex(text, e)))
            }
            cursor = e
        }
        val tail = codePointToCharIndex(text, cursor)
        if (tail < text.length) append(text.substring(tail))
    }
}

private fun codePointToCharIndex(text: String, codePointIndex: Int): Int {
    if (codePointIndex <= 0) return 0
    var charIndex = 0
    var count = 0
    while (count < codePointIndex && charIndex < text.length) {
        charIndex += Character.charCount(text.codePointAt(charIndex))
        count++
    }
    return charIndex
}

// MARK: - NexTone 許諾の掲示

/** NexTone 許諾の掲示物 (iOS `NexToneLicense`)。NexTone 管理曲 (学マス・876 系に多い) の歌詞を出す根拠。 */
object NexToneLicense {
    /** NexTone の許諾番号は英字2文字 + 数字9桁の11桁。 */
    const val NUMBER = "ID000012667"
    /** 掲示に使う表記。NexTone の許諾メールの表記 (「許諾番号：ID…」) に合わせる。 */
    const val NOTICE = "NexTone許諾番号 $NUMBER"
}

/**
 * NexTone の許諾マークと許諾番号 (iOS `JASRACLicenseNotice(.lyrics)` の NexTone 分のみ)。
 * マーク画像は NexTone から受け取った原本 (`res/drawable-nodpi/nextone_mark.png`)。
 * 色を変えたり縦横比を崩したりしないこと。
 */
@Composable
private fun NexToneLicenseNotice() {
    Column(
        Modifier.fillMaxWidth().padding(vertical = DS.sp5),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        androidx.compose.foundation.Image(
            painter = androidx.compose.ui.res.painterResource(id = com.fugaif.imaslivedb.R.drawable.nextone_mark),
            contentDescription = null,
            modifier = Modifier.height(28.dp).width(28.dp)
        )
        ImasText(NexToneLicense.NOTICE, ImasTextRole.META, modifier = Modifier.padding(top = DS.sp1))
    }
}
