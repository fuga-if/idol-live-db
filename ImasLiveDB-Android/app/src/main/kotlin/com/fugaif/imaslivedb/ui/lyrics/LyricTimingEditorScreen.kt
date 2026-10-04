package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.automirrored.filled.KeyboardReturn
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay5
import androidx.compose.material.icons.filled.Forward5
import androidx.compose.material.icons.filled.PanTool
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.TouchApp
import androidx.compose.material.icons.outlined.Layers
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
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.fugaif.imaslivedb.data.lyrics.LyricCall
import com.fugaif.imaslivedb.data.lyrics.LyricLine
import com.fugaif.imaslivedb.data.lyrics.LyricLineKind
import com.fugaif.imaslivedb.data.lyrics.LyricPartCast
import com.fugaif.imaslivedb.data.lyrics.LyricPartMark
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.lyrics.colorsAt
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricTimeLabel
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPartNames
import com.fugaif.imaslivedb.ui.designsystem.ImasPartsHighlight
import com.fugaif.imaslivedb.ui.designsystem.ImasPartsSelectableLine
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerCallLine
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerLyricLine
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyFlowText
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyText
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.designsystem.ImasTimingBlock
import com.fugaif.imaslivedb.ui.designsystem.ImasTimingTimeline
import com.fugaif.imaslivedb.ui.designsystem.lyricColor
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.imasTheme
import com.fugaif.imaslivedb.ui.theme.rememberImasHaptics
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.imas_core.LyricPartSegment
import uniffi.imas_core.lyricActiveCall
import uniffi.imas_core.lyricActiveLine
import uniffi.imas_core.lyricCallSpans
import uniffi.imas_core.lyricIsOverlayLine
import uniffi.imas_core.lyricLineSpans
import uniffi.imas_core.lyricNextRecordable
import uniffi.imas_core.lyricOverlaySpans
import uniffi.imas_core.lyricPartsApplicable

/** 曲の順に並べたコール 1 件と、ぶら下がる行の添字。 */
private data class CallRef(val call: LyricCall, val line: Int)

/**
 * 歌詞行とコールの時刻 (タイミング) を付ける・直す画面。iOS `LyricTimingEditorView` の移植。
 *
 * 1. ざっくり付ける … 曲を流しながら、下の大きいボタンを歌い出しに合わせて押す。
 * 2. 直す … 横長のタイムラインで帯を選び、-0.1 / +0.1 秒で寄せるか、帯の頭のつまみをなぞる。
 *
 * 保存するまでサーバにも端末にも残さない。行の本文は画面に出すだけで、送らない。
 */
@Composable
fun LyricTimingEditorScreen(
    song: Song,
    seed: String?,
    lyrics: Lyrics,
    recorder: LyricTimingRecorder,
    onSaved: () -> Unit,
    onClose: () -> Unit,
    /** パートの段で選ぶ歌唱者 (原唱者)。2 人以上のときだけパートの段を出す。 */
    cast: LyricPartCast = LyricPartCast.EMPTY
) {
    val module = AppModule.from(LocalContext.current)
    val playback = module.lyricsPlayback
    val scope = rememberCoroutineScope()
    val haptics = rememberImasHaptics()

    var playheadMs by remember { mutableStateOf(0) }
    var scrubMs by remember { mutableStateOf<Int?>(null) }
    var selectedId by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }
    var startFailed by remember { mutableStateOf(false) }
    val isPlaying by playback.isPlaying.collectAsState()
    val loadedSongId by playback.loadedSongId.collectAsState()
    // 歌詞をなぞってから少しの間は、曲に付いていくのを止める。
    var followPausedUntil by remember { mutableStateOf(0L) }
    // パートの段の筆 (塗る歌う人)。null なら原唱者の先頭。
    // 筆 (塗る歌う人。複数人を一度に塗れる)。null なら原唱者の先頭 1 人。
    var partsBrushIds by remember { mutableStateOf<List<String>?>(null) }
    val brush = partsBrushIds ?: listOfNotNull(cast.artists.firstOrNull()?.id)
    val laneListState = rememberLazyListState()

    val duration = run {
        val lastStart = recorder.starts.filterNotNull().maxOrNull() ?: 0
        playback.durationMs() ?: song.durationSec?.let { it * 1000 } ?: (lastStart + 8000)
    }
    val shownMs = scrubMs ?: playheadMs

    fun isOverlay(index: Int): Boolean {
        val line = lyrics.lines[index]
        return line.kind != com.fugaif.imaslivedb.data.lyrics.LyricLineKind.BLANK &&
            lyricIsOverlayLine(line.text, recorder.layers[index])
    }
    val mainStarts = recorder.startsForCore.mapIndexed { i, v -> if (isOverlay(i)) null else v }
    val overlayStarts = recorder.startsForCore.mapIndexed { i, v -> if (isOverlay(i)) v else null }
    val currentIndex = lyricActiveLine(mainStarts, shownMs.toLong())?.toInt()
    // パートを付ける行: タイムラインで選んだ行、選んでいなければいま歌っている行 (見出しには付けない)。
    val partsTargetId: String? = selectedId
        ?.takeIf { sel -> lyrics.lines.any { it.id == sel && it.kind == com.fugaif.imaslivedb.data.lyrics.LyricLineKind.LYRIC } }
        ?: currentIndex?.let { i ->
            lyrics.lines[i].id.takeIf { lyrics.lines[i].kind == com.fugaif.imaslivedb.data.lyrics.LyricLineKind.LYRIC }
        }
    val allCalls = lyrics.lines.flatMapIndexed { i, line -> line.calls.map { CallRef(it, i) } }

    /** 筆の人たちを、行の字の範囲に塗る / 外す (範囲の字がみな筆の全員入りなら外す)。規則はコア。 */
    fun paint(lineId: String, start: Int, end: Int) {
        if (brush.isEmpty()) return
        haptics.selection()
        recorder.paint(lineId, start, end, brush, cast.artists.map { it.id })
    }

    LaunchedEffect(Unit) {
        if (playback.loadedSongId.value != song.id) {
            startFailed = !playback.startFull(song.id, song.appleMusicId ?: "")
        }
    }
    LaunchedEffect(loadedSongId) {
        while (true) {
            if (scrubMs == null) {
                val ms = playback.positionMs()
                if (ms != null && ms != playheadMs) playheadMs = ms
            }
            delay(80)
        }
    }

    suspend fun save() {
        if (recorder.save(module.lyricsApi)) {
            onSaved()
            onClose()
        } else {
            val state = recorder.saveState
            if (state is LyricTimingRecorder.SaveState.Failed) saveError = state.message
        }
    }

    Column(Modifier.fillMaxSize().background(DS.bg)) {
        // 頭
        Row(
            Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp3),
            horizontalArrangement = Arrangement.spacedBy(DS.sp3),
            verticalAlignment = Alignment.CenterVertically
        ) {
            ImasIconButton(icon = Icons.Filled.Close, label = "閉じる", style = ImasIconButtonStyle.PLAIN, onClick = {
                if (recorder.isDirty) confirmDiscard = true else onClose()
            })
            Column(Modifier.weight(1f)) {
                ImasText("タイミング編集", ImasTextRole.ROW_TITLE)
                ImasText(song.title, ImasTextRole.ROW_SUBTITLE, maxLines = 1)
            }
            ImasIconButton(
                icon = Icons.AutoMirrored.Filled.Undo, label = "取り消す", style = ImasIconButtonStyle.PLAIN,
                enabled = recorder.canUndo, onClick = { recorder.undo() }
            )
            ImasButton(
                title = "保存", role = ImasButtonRole.PRIMARY, size = ImasButtonSize.SMALL,
                isLoading = recorder.saveState == LyricTimingRecorder.SaveState.Saving,
                enabled = recorder.isDirty && recorder.saveState != LyricTimingRecorder.SaveState.Saving,
                onClick = { scope.launch { save() } }
            )
        }

        // 段の並び。コールがあればコール、原唱者が 2 人以上ならパートを足す。
        val lanes = remember(recorder.hasCalls, cast) {
            buildList {
                add(LyricTimingRecorder.Lane.LINES)
                if (recorder.hasCalls) add(LyricTimingRecorder.Lane.CALLS)
                if (lyricPartsApplicable(cast.artists.size.toUInt())) add(LyricTimingRecorder.Lane.PARTS)
            }
        }
        if (lanes.size > 1) {
            ImasTabs(
                options = lanes,
                selection = recorder.lane,
                onSelect = { recorder.lane = it },
                label = {
                    when (it) {
                        LyricTimingRecorder.Lane.LINES -> "歌詞"
                        LyricTimingRecorder.Lane.CALLS -> "コール"
                        LyricTimingRecorder.Lane.PARTS -> "パート"
                    }
                },
                seed = seed,
                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp3)
            )
        }

        val appleMusic by playback.appleMusicState.collectAsState()
        if (recorder.lane == LyricTimingRecorder.Lane.LINES) {
            // 今の行と、次に記録するもの。
            Column(Modifier.fillMaxWidth().padding(horizontal = DS.sp5), verticalArrangement = Arrangement.spacedBy(DS.sp4)) {
                AppleMusicSignInNotice(appleMusic, onSignIn = playback::signIn)
                // 繋がっているのに始められなかった (曲が Apple Music に無い等) ときだけ出す。
                if (startFailed && appleMusic == com.fugaif.imaslivedb.player.AppleMusicState.READY) {
                    ImasNote("この曲は Apple Music で鳴らせませんでした。")
                }
                Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
                    ImasText("いま", ImasTextRole.EYEBROW)
                    ImasPlayerLyricLine(text = currentIndex?.let { lyrics.lines[it].text } ?: "（イントロ）", isCurrent = true, seed = seed)
                }
                val next = recorder.cursor
                if (next != null) {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
                        ImasText("次に記録する行", ImasTextRole.EYEBROW)
                        upcoming(lyrics, next).forEachIndexed { offset, index ->
                            ImasPlayerLyricLine(
                                text = lyrics.lines[index].text, isCurrent = offset == 0,
                                isMarker = lyrics.lines[index].kind == LyricLineKind.MARKER, seed = seed
                            )
                        }
                    }
                } else {
                    ImasNote("最後の行まで記録しました。タイムラインで帯を選ぶと前後に寄せられます。")
                }
            }
            Spacer(Modifier.weight(1f))
        } else {
            // コールとパートは、歌詞を上下に動かして入れる行を選ぶ (曲に付いていくが、なぞると止まる)。
            Column(Modifier.fillMaxWidth().padding(horizontal = DS.sp5), verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
                AppleMusicSignInNotice(appleMusic, onSignIn = playback::signIn)
                if (startFailed && appleMusic == com.fugaif.imaslivedb.player.AppleMusicState.READY) {
                    ImasNote("この曲は Apple Music で鳴らせませんでした。")
                }
            }
            LaneLyricsList(
                lyrics = lyrics,
                recorder = recorder,
                cast = cast,
                seed = seed,
                currentIndex = currentIndex,
                allCalls = allCalls,
                selectedId = selectedId,
                onSelect = { selectedId = it },
                startFailed = startFailed,
                onPaint = { lineId, start, end -> paint(lineId, start, end) },
                partsTargetId = partsTargetId,
                listState = laneListState,
                followPausedUntil = { followPausedUntil },
                onUserScroll = { followPausedUntil = System.currentTimeMillis() + 4000 },
                modifier = Modifier.weight(1f)
            )
        }

        // タイムライン
        run {
            val spans = lyricLineSpans(mainStarts, duration.toLong())
            val overlayBlocks = lyricOverlaySpans(overlayStarts, duration.toLong()).map {
                ImasTimingBlock(lyrics.lines[it.index.toInt()].id, it.startMs.toInt(), it.endMs.toInt(), lyrics.lines[it.index.toInt()].text)
            }
            val blocks = spans.map {
                ImasTimingBlock(lyrics.lines[it.index.toInt()].id, it.startMs.toInt(), it.endMs.toInt(), lyrics.lines[it.index.toInt()].text)
            }
            val callBlocks = lyricCallSpans(recorder.callStartsForCore, duration.toLong()).map {
                val ref = allCalls[it.index.toInt()]
                ImasTimingBlock(ref.call.id, it.startMs.toInt(), it.endMs.toInt(), ref.call.text)
            }
            ImasTimingTimeline(
                blocks = blocks, subLanes = listOf(overlayBlocks, callBlocks), playheadMs = shownMs,
                selectedId = selectedId, seed = seed,
                onScrub = { scrubMs = it },
                onScrubEnd = { ms -> scrubMs = null; playheadMs = ms; playback.seek(ms) },
                onSelect = { id -> selectedId = if (selectedId == id) null else id },
                onMoveStart = { id, ms -> recorder.adjust(id, ms) }
            )
        }

        // 選んだ帯の操作
        Row(
            Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp1),
            horizontalArrangement = Arrangement.spacedBy(DS.sp2),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val id = selectedId
            val start = id?.let { recorder.start(it) }
            if (id != null && start != null) {
                ImasLyricTimeLabel(ms = start, isEmphasized = true)
                val lineIndex = recorder.lineIds.indexOf(id)
                if (lineIndex >= 0) {
                    val overlay = isOverlay(lineIndex)
                    ImasIconButton(
                        icon = if (overlay) Icons.Filled.Layers else Icons.Outlined.Layers,
                        label = if (overlay) "メインに戻す" else "被せにする",
                        onClick = { recorder.setOverlay(id, !overlay) }
                    )
                }
                Spacer(Modifier.weight(1f))
                ImasButton(title = "-0.1秒", role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL, onClick = { recorder.nudge(id, -100) })
                ImasButton(title = "+0.1秒", role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL, onClick = { recorder.nudge(id, 100) })
                ImasIconButton(icon = Icons.Filled.MyLocation, label = "再生位置に合わせる", onClick = { recorder.adjust(id, playheadMs) })
                ImasIconButton(icon = Icons.Filled.PlayArrow, label = "この行から再生", onClick = {
                    playback.seek(maxOf(0, start - 1500))
                    if (!playback.isPlaying.value) playback.togglePlay()
                })
            } else {
                ImasNote("帯をタップして選ぶと、前後に寄せられます。地をなぞると再生位置が動きます。")
            }
        }

        // 再生のトランスポート
        Row(
            Modifier.fillMaxWidth().padding(top = DS.sp4),
            horizontalArrangement = Arrangement.spacedBy(DS.sp8),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Spacer(Modifier.weight(1f))
            ImasIconButton(icon = Icons.Filled.Replay5, label = "5 秒戻す", onClick = { playback.seek(maxOf(0, playheadMs - 5000)) })
            ImasIconButton(
                icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                label = if (isPlaying) "一時停止" else "再生",
                style = ImasIconButtonStyle.FILLED,
                onClick = { playback.togglePlay() }
            )
            ImasIconButton(icon = Icons.Filled.Forward5, label = "5 秒進める", onClick = { playback.seek(minOf(duration, playheadMs + 5000)) })
            Spacer(Modifier.weight(1f))
        }

        if (recorder.lane == LyricTimingRecorder.Lane.PARTS) {
            // 歌う人のアイコン (筆)。タップで筆に足す / 外す (何人でも)。「全員を選ぶ」で原唱者みんな。
            val everyone = cast.artists.map { it.id }
            val isEveryone = brush.toSet() == everyone.toSet()
            Column(
                Modifier.padding(vertical = DS.sp4),
                verticalArrangement = Arrangement.spacedBy(DS.sp3)
            ) {
                Row(
                    Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = DS.sp5),
                    horizontalArrangement = Arrangement.spacedBy(DS.sp3)
                ) {
                    cast.artists.forEach { idol ->
                        val isOn = idol.id in brush
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            modifier = Modifier
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() }, indication = null
                                ) {
                                    val next = brush.toMutableList()
                                    // 筆は 1 人は残す (空の筆では塗れない)。
                                    if (idol.id in next) { if (next.size > 1) next.remove(idol.id) } else next.add(idol.id)
                                    partsBrushIds = everyone.filter { it in next }
                                }
                                .semantics { contentDescription = "${idol.shortName}で塗る"; selected = isOn }
                        ) {
                            ImasAvatar(label = idol.shortName, seed = idol.color, brand = idol.brandId, size = 48.dp, isPick = isOn, entityId = idol.id)
                            ImasText(idol.shortName, ImasTextRole.META, color = if (isOn) DS.ink else DS.ink3, maxLines = 1)
                        }
                    }
                }
                Row(Modifier.padding(horizontal = DS.sp5), horizontalArrangement = Arrangement.spacedBy(DS.sp2)) {
                    ImasButton(
                        title = if (isEveryone) "1 人に戻す" else "全員を選ぶ", icon = Icons.Filled.Groups,
                        role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL,
                        onClick = { partsBrushIds = if (isEveryone) everyone.take(1) else everyone }
                    )
                    ImasButton(
                        title = "前の行と同じ人にする", icon = Icons.AutoMirrored.Filled.KeyboardReturn,
                        role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL,
                        enabled = partsTargetId != null,
                        onClick = {
                            val id = partsTargetId ?: return@ImasButton
                            haptics.selection()
                            recorder.copyPreviousSingers(id)
                        }
                    )
                }
            }
        } else {
            // 記録ボタン
            ImasButton(
                title = when {
                    recorder.laneCursor == null -> "最後まで記録しました"
                    recorder.lane == LyricTimingRecorder.Lane.LINES -> "歌い出しで押す"
                    else -> "コールの頭で押す"
                },
                icon = Icons.Filled.TouchApp,
                role = ImasButtonRole.PRIMARY,
                size = ImasButtonSize.LARGE,
                fillsWidth = true,
                enabled = recorder.laneCursor != null && loadedSongId == song.id,
                onClick = {
                    val ms = playback.positionMs() ?: return@ImasButton
                    recorder.recordNext(ms)
                },
                modifier = Modifier.padding(horizontal = DS.sp5, vertical = DS.sp4)
            )
        }
    }

    ImasConfirmDestructive(
        title = "保存せずに閉じますか？",
        isPresented = confirmDiscard,
        onDismiss = { confirmDiscard = false },
        onConfirm = onClose,
        actionTitle = "保存せずに閉じる",
        dismissTitle = "編集を続ける"
    )
    ImasErrorAlert(message = saveError, onDismiss = { saveError = null })
}

// MARK: - コールとパートの段: 歌詞を動かして選ぶ

/**
 * コールとパートの段の中身。曲の流れに合わせて歌詞全体をスクロールし (`currentIndex` の行に追従)、
 * 指でなぞると 4 秒止まる。iOS `LyricTimingEditorView.laneLyrics` の移植。
 */
@Composable
private fun LaneLyricsList(
    lyrics: Lyrics,
    recorder: LyricTimingRecorder,
    cast: LyricPartCast,
    seed: String?,
    currentIndex: Int?,
    allCalls: List<CallRef>,
    selectedId: String?,
    onSelect: (String?) -> Unit,
    startFailed: Boolean,
    onPaint: (String, Int, Int) -> Unit,
    partsTargetId: String?,
    listState: LazyListState,
    followPausedUntil: () -> Long,
    onUserScroll: () -> Unit,
    modifier: Modifier = Modifier
) {
    val accent = imasTheme(seed = seed).accent
    val isParts = recorder.lane == LyricTimingRecorder.Lane.PARTS

    // 指でなぞっている間と、離して少しの間は、曲に付いていく追従を止める。
    LaunchedEffect(listState) {
        while (true) {
            if (listState.isScrollInProgress) onUserScroll()
            delay(200)
        }
    }
    LaunchedEffect(currentIndex) {
        val index = currentIndex ?: return@LaunchedEffect
        if (System.currentTimeMillis() < followPausedUntil()) return@LaunchedEffect
        val viewport = listState.layoutInfo.viewportSize.height
        runCatching { listState.animateScrollToItem(index, scrollOffset = -(viewport * 0.3f).toInt()) }
    }

    LazyColumn(
        modifier,
        state = listState,
        verticalArrangement = Arrangement.spacedBy(DS.sp4),
        contentPadding = PaddingValues(horizontal = DS.sp5, vertical = DS.sp4)
    ) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
                if (startFailed) {
                    ImasNote(if (isParts) "パート分けには Apple Music でのフル再生が必要です。" else "記録には Apple Music でのフル再生が必要です。")
                }
                ImasText(
                    if (isParts) "歌う人を選んでから行をタップすると、行まるごと塗れます。いま歌っている行 (選んだ行) は、語をタップするか長押しでなぞると、その字だけ塗れます。もう一度で外れます。"
                    else "コールをタップして選ぶと、前後に寄せられます。",
                    ImasTextRole.META, color = DS.ink3
                )
            }
        }
        itemsIndexed(lyrics.lines, key = { _, line -> line.id }) { index, line ->
            val isCurrent = index == currentIndex
            when (line.kind) {
                LyricLineKind.BLANK -> Spacer(Modifier.height(DS.sp1))
                LyricLineKind.MARKER -> ImasText(line.text, ImasTextRole.EYEBROW, color = DS.ink3)
                LyricLineKind.LYRIC -> if (isParts) {
                    PartsLaneRow(
                        line = line, isCurrent = isCurrent, isTarget = line.id == partsTargetId,
                        recorder = recorder, cast = cast,
                        onSelectTarget = { onSelect(line.id) },
                        onPaint = { start, end -> onPaint(line.id, start, end) }
                    )
                } else {
                    CallsLaneRow(
                        line = line, isCurrent = isCurrent, calls = allCalls, recorder = recorder,
                        selectedId = selectedId, onSelect = onSelect, accent = accent
                    )
                }
            }
        }
    }
}

/** コールの段の 1 行。行の下にコールを並べ、タップで選ぶ (タイムラインと同じ選択)。 */
@Composable
private fun CallsLaneRow(
    line: LyricLine,
    isCurrent: Boolean,
    calls: List<CallRef>,
    recorder: LyricTimingRecorder,
    selectedId: String?,
    onSelect: (String?) -> Unit,
    accent: androidx.compose.ui.graphics.Color
) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
        LaneLyricText(line.text, isCurrent)
        line.calls.forEach { call ->
            val order = calls.indexOfFirst { it.call.id == call.id }
            val isNext = order >= 0 && order == recorder.callCursor
            Row(
                Modifier.clickable(
                    interactionSource = remember { MutableInteractionSource() }, indication = null
                ) { onSelect(if (selectedId == call.id) null else call.id) },
                horizontalArrangement = Arrangement.spacedBy(DS.sp2),
                verticalAlignment = Alignment.CenterVertically
            ) {
                ImasPlayerCallLine(
                    marker = if (call.hasAnchor) "↳" else "»",
                    text = call.text,
                    color = call.emphasis.lyricColor(accent),
                    isActive = selectedId == call.id || isNext
                )
                if (isNext) ImasText("次に記録", ImasTextRole.META)
                recorder.start(call.id)?.let { ms -> ImasLyricTimeLabel(ms = ms, isEmphasized = false) }
            }
        }
    }
}

/**
 * パートの段の 1 行。歌う人 (筆) を選んでから、行をタップすると行まるごと塗る / 外す。
 * 選んだ行 (いま歌っている行) は語をタップ・長押しでなぞると、その字だけ塗る / 外す。
 */
@Composable
private fun PartsLaneRow(
    line: LyricLine,
    isCurrent: Boolean,
    isTarget: Boolean,
    recorder: LyricTimingRecorder,
    cast: LyricPartCast,
    onSelectTarget: () -> Unit,
    onPaint: (Int, Int) -> Unit
) {
    val segments: List<LyricPartSegment> = recorder.segments(line.id)
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
        if (isTarget) {
            // 塗った字には歌う人 (先頭の人) の色を敷く。語のタップ・なぞりは [ImasPartsSelectableLine] が担う。
            val highlights = segments.mapNotNull { segment ->
                cast.colors(segment.singers).firstOrNull()?.let { hex ->
                    ImasPartsHighlight(segment.start.toInt(), segment.end.toInt(), imasTheme(seed = hex).accent)
                }
            }
            ImasPartsSelectableLine(text = line.text, highlights = highlights, onSelect = onPaint)
        } else {
            val marks: List<LyricPartMark> = segments.mapNotNull { segment ->
                val colors = cast.colors(segment.singers)
                if (colors.isEmpty()) null else LyricPartMark(segment.start.toInt(), segment.end.toInt(), colors)
            }
            Row(
                Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    onSelectTarget()
                    onPaint(0, line.text.codePointCount(0, line.text.length))
                }
            ) {
                LaneLyricText(line.text, isCurrent, parts = marks)
            }
        }
        ImasPartNames(groups = segments.map { cast.names(it.singers) })
    }
}

/** 段の中の歌詞 1 行 (振り仮名は親字の上に、歌う人は字の下の色の線で)。 */
@Composable
private fun LaneLyricText(text: String, isCurrent: Boolean, parts: List<LyricPartMark> = emptyList(), modifier: Modifier = Modifier) {
    val color = if (isCurrent) DS.ink else DS.ink3
    if (ImasRubyText.hasRuby(text) || parts.isNotEmpty()) {
        ImasRubyFlowText(
            text = text, style = ImasTextRole.BODY.style, color = color, modifier = modifier,
            partsAt = { start -> parts.colorsAt(start) }
        )
    } else {
        ImasText(text, ImasTextRole.BODY, color = color, modifier = modifier)
    }
}

/** 次に記録する行と、その先の記録対象 2 行の添字 (計 3 件)。 */
private fun upcoming(lyrics: Lyrics, cursor: Int): List<Int> {
    val result = mutableListOf(cursor)
    var after = cursor.toUInt()
    while (result.size < 3) {
        val next = lyricNextRecordable(lyrics.lines.map { it.kind.raw }, after) ?: break
        result.add(next.toInt())
        after = next
    }
    return result
}
