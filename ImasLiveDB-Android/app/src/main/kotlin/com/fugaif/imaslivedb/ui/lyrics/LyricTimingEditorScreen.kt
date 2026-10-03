package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Undo
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Layers
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay5
import androidx.compose.material.icons.filled.Forward5
import androidx.compose.material.icons.filled.PanTool
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
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasErrorAlert
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButton
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricTimeLabel
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerLyricLine
import com.fugaif.imaslivedb.ui.designsystem.ImasTabs
import com.fugaif.imaslivedb.ui.designsystem.ImasTimingBlock
import com.fugaif.imaslivedb.ui.designsystem.ImasTimingTimeline
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import uniffi.imas_core.lyricActiveCall
import uniffi.imas_core.lyricActiveLine
import uniffi.imas_core.lyricCallSpans
import uniffi.imas_core.lyricIsOverlayLine
import uniffi.imas_core.lyricLineSpans
import uniffi.imas_core.lyricNextRecordable
import uniffi.imas_core.lyricOverlaySpans

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
    onClose: () -> Unit
) {
    val module = AppModule.from(LocalContext.current)
    val playback = module.lyricsPlayback
    val scope = rememberCoroutineScope()

    var playheadMs by remember { mutableStateOf(0) }
    var scrubMs by remember { mutableStateOf<Int?>(null) }
    var selectedId by remember { mutableStateOf<String?>(null) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var saveError by remember { mutableStateOf<String?>(null) }
    var startFailed by remember { mutableStateOf(false) }
    val isPlaying by playback.isPlaying.collectAsState()
    val loadedSongId by playback.loadedSongId.collectAsState()

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
    data class CallRef(val call: com.fugaif.imaslivedb.data.lyrics.LyricCall, val line: Int)
    val allCalls = lyrics.lines.flatMapIndexed { i, line -> line.calls.map { CallRef(it, i) } }

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

        if (recorder.hasCalls) {
            ImasTabs(
                options = listOf(LyricTimingRecorder.Lane.LINES, LyricTimingRecorder.Lane.CALLS),
                selection = recorder.lane,
                onSelect = { recorder.lane = it },
                label = { if (it == LyricTimingRecorder.Lane.LINES) "歌詞" else "コール" },
                seed = seed,
                modifier = Modifier.fillMaxWidth().padding(horizontal = DS.sp5, vertical = DS.sp3)
            )
        }

        // 今の行/コールと、次に記録するもの。
        Column(Modifier.fillMaxWidth().padding(horizontal = DS.sp5), verticalArrangement = Arrangement.spacedBy(DS.sp4)) {
            val appleMusic by playback.appleMusicState.collectAsState()
            AppleMusicSignInNotice(appleMusic, onSignIn = playback::signIn)
            // 繋がっているのに始められなかった (曲が Apple Music に無い等) ときだけ出す。
            if (startFailed && appleMusic == com.fugaif.imaslivedb.player.AppleMusicState.READY) {
                ImasNote("この曲は Apple Music で鳴らせませんでした。")
            }
            if (recorder.lane == LyricTimingRecorder.Lane.CALLS) {
                val current = lyricActiveCall(recorder.callStartsForCore, shownMs.toLong())?.toInt()
                Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
                    ImasText("いまのコール", ImasTextRole.EYEBROW)
                    ImasPlayerLyricLine(text = current?.let { allCalls[it].call.text } ?: "—", isCurrent = true, seed = seed)
                }
                val next = recorder.callCursor
                if (next != null) {
                    Column(verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
                        ImasText("次に記録するコール", ImasTextRole.EYEBROW)
                        for (index in next until minOf(allCalls.size, next + 3)) {
                            Column {
                                ImasText(lyrics.lines[allCalls[index].line].text, ImasTextRole.META, maxLines = 1)
                                ImasPlayerLyricLine(text = allCalls[index].call.text, isCurrent = index == next, seed = seed)
                            }
                        }
                    }
                } else {
                    ImasNote("最後のコールまで記録しました。タイムラインの下の段で前後に寄せられます。")
                }
            } else {
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
                                isMarker = lyrics.lines[index].kind == com.fugaif.imaslivedb.data.lyrics.LyricLineKind.MARKER, seed = seed
                            )
                        }
                    }
                } else {
                    ImasNote("最後の行まで記録しました。タイムラインで帯を選ぶと前後に寄せられます。")
                }
            }
        }

        Spacer(Modifier.weight(1f))

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
