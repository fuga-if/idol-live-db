package com.fugaif.imaslivedb.ui.lyrics

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
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
import androidx.compose.material.icons.automirrored.filled.Redo
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
import androidx.compose.material.icons.filled.AutoFixNormal
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.FormatColorFill
import androidx.compose.material.icons.filled.GroupAdd
import androidx.compose.material.icons.filled.Groups
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
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
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasIconButtonStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLineRow
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLineState
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricTimeLabel
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPartNames
import com.fugaif.imaslivedb.ui.designsystem.ImasPartsHighlight
import com.fugaif.imaslivedb.ui.designsystem.ImasPartsSelectableLine
import com.fugaif.imaslivedb.ui.designsystem.ImasPlayerCallLine
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyFlowText
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyText
import com.fugaif.imaslivedb.ui.designsystem.ImasSegmented
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
@OptIn(ExperimentalFoundationApi::class)
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
    // 消しゴムを持っているか (塗る代わりに、その字の歌う人をみな外す)。
    var partsErasing by remember { mutableStateOf(false) }
    /** 「一緒に歌う」を持っているか (歌う人のタップが、持ち替えでなく筆に足す / 外すになる)。 */
    var partsAdding by remember { mutableStateOf(false) }
    // 行をタップして次に記録する行を選んだ直後か (指の下の一覧を寄せない)。
    var pickedByTap by remember { mutableStateOf(false) }
    // パートの段の見せ方。false = 曲に付いていく (聴きながら)、true = 一覧 (追従と再生の操作を畳む。聴かずに塗る)。
    var partsAsList by remember { mutableStateOf(false) }
    val isPartsList = recorder.lane == LyricTimingRecorder.Lane.PARTS && partsAsList
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
    // 一覧では、選んだ行だけ (曲に付いていかない)。
    val partsTargetId: String? = selectedId
        ?.takeIf { sel -> lyrics.lines.any { it.id == sel && it.kind == com.fugaif.imaslivedb.data.lyrics.LyricLineKind.LYRIC } }
        ?: currentIndex?.takeIf { !isPartsList }?.let { i ->
            lyrics.lines[i].id.takeIf { lyrics.lines[i].kind == com.fugaif.imaslivedb.data.lyrics.LyricLineKind.LYRIC }
        }
    val allCalls = lyrics.lines.flatMapIndexed { i, line -> line.calls.map { CallRef(it, i) } }

    /** 筆の人たちを、行の字の範囲に塗る / 外す (範囲の字がみな筆の全員入りなら外す)。規則はコア。 */
    fun paint(lineId: String, start: Int, end: Int) {
        if (partsErasing) {
            haptics.selection()
            recorder.erase(lineId, start, end)
            return
        }
        if (brush.isEmpty()) return
        haptics.selection()
        recorder.paint(lineId, start, end, brush, cast.artists.map { it.id })
    }

    /** 再生位置を動かす。次に記録するものも、その位置の次へ寄せる (途中から押し直せるように)。 */
    fun seek(ms: Int) {
        playheadMs = ms
        playback.seek(ms)
        recorder.aim(ms)
    }

    /**
     * 塗る行を選ぶ。聴きながら塗っていて行に時刻があれば、その行の頭へ戻す
     * (今の行がその行になるので、そのまま聴き直して塗れる。過ぎた行を塗り直すため)。
     * 被せの行は今の行にならないので選ぶだけ。
     */
    fun pickPartsLine(lineId: String) {
        val index = lyrics.lines.indexOfFirst { it.id == lineId }
        val start = recorder.start(lineId)
        if (!isPartsList && index >= 0 && !isOverlay(index) && playback.loadedSongId.value == song.id && start != null) {
            selectedId = null
            followPausedUntil = 0L
            seek(start)
        } else {
            selectedId = lineId
        }
    }

    LaunchedEffect(Unit) {
        // 曲の途中で開いたら、そこから押し直せるようにする (記録済みの曲を頭から押させない)。
        if (playback.loadedSongId.value == song.id) {
            playback.positionMs()?.takeIf { it > 0 }?.let { recorder.aim(it) }
        }
        if (playback.loadedSongId.value != song.id) {
            startFailed = !playback.startFull(song.id, song.appleMusicId ?: "")
            // 鳴らせないなら、パートは一覧で塗る (曲に付いていけないので)。
            if (startFailed) partsAsList = true
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
            ImasIconButton(
                icon = Icons.AutoMirrored.Filled.Redo, label = "やり直す", style = ImasIconButtonStyle.PLAIN,
                enabled = recorder.canRedo, onClick = { recorder.redo() }
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
        // 歌詞を上下に動かして、記録する行・コールを入れる行・塗る行を選ぶ。
        Column(Modifier.fillMaxWidth().padding(horizontal = DS.sp5), verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
            AppleMusicSignInNotice(appleMusic, onSignIn = playback::signIn)
            // 繋がっているのに始められなかった (曲が Apple Music に無い等) ときだけ出す。
            if (startFailed && appleMusic == com.fugaif.imaslivedb.player.AppleMusicState.READY) {
                ImasNote("この曲は Apple Music で鳴らせませんでした。")
            }
            if (recorder.lane == LyricTimingRecorder.Lane.LINES) CursorBar(recorder)
            if (recorder.lane == LyricTimingRecorder.Lane.PARTS) {
                ImasSegmented(
                    labels = listOf("リアルタイム", "一覧"),
                    selection = if (partsAsList) 1 else 0,
                    onSelect = { partsAsList = it == 1 },
                    modifier = Modifier.fillMaxWidth()
                )
            }
        }
        LaneLyricsList(
            lyrics = lyrics,
            recorder = recorder,
            cast = cast,
            seed = seed,
            currentIndex = currentIndex.takeIf { !isPartsList },
            allCalls = allCalls,
            selectedId = selectedId,
            onSelect = { selectedId = it },
            startFailed = startFailed && !isPartsList,
            isPartsList = isPartsList,
            onPaint = { lineId, start, end -> paint(lineId, start, end) },
            partsTargetId = partsTargetId,
            partsErasing = partsErasing,
            onPickPartsLine = ::pickPartsLine,
            listState = laneListState,
            followPausedUntil = { followPausedUntil },
            onUserScroll = { followPausedUntil = System.currentTimeMillis() + 4000 },
            pickedByTap = { pickedByTap },
            onPickByTap = { pickedByTap = true },
            onPickHandled = { pickedByTap = false },
            modifier = Modifier.weight(1f)
        )

        // 一覧でパートを塗るときは、タイムラインと再生の操作を畳んで歌詞を広く見せる。
        if (!isPartsList) {
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
                    onScrubEnd = { ms -> scrubMs = null; seek(ms) },
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
                    ImasIconButton(icon = Icons.Filled.PlayArrow, label = "この行から再生して押し直す", onClick = {
                        seek(maxOf(0, start - 1500))
                        recorder.aim(id)
                        if (!playback.isPlaying.value) playback.togglePlay()
                    })
                } else {
                    ImasNote("帯をタップして選ぶと、前後に寄せられます。地をなぞって戻すと、そこから押し直せます。")
                }
            }

            // 再生のトランスポート
            Row(
                Modifier.fillMaxWidth().padding(top = DS.sp4),
                horizontalArrangement = Arrangement.spacedBy(DS.sp8),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Spacer(Modifier.weight(1f))
                ImasIconButton(icon = Icons.Filled.Replay5, label = "5 秒戻す", onClick = { seek(maxOf(0, playheadMs - 5000)) })
                ImasIconButton(
                    icon = if (isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow,
                    label = if (isPlaying) "一時停止" else "再生",
                    style = ImasIconButtonStyle.FILLED,
                    onClick = { playback.togglePlay() }
                )
                ImasIconButton(icon = Icons.Filled.Forward5, label = "5 秒進める", onClick = { seek(minOf(duration, playheadMs + 5000)) })
                Spacer(Modifier.weight(1f))
            }
        }

        if (recorder.lane == LyricTimingRecorder.Lane.PARTS) {
            // 歌う人のアイコン (筆)。タップでその人 1 人に持ち替え、「一緒に歌う」を持っているとき・長押しで足す / 外す。「全員を選ぶ」で原唱者みんな。
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
                    // 消しゴム: 持っている間は、行や語をタップ・なぞると、その字の歌う人をみな外す。
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        ImasIconButton(
                            icon = Icons.Filled.AutoFixNormal, label = "消しゴム",
                            style = if (partsErasing) ImasIconButtonStyle.FILLED else ImasIconButtonStyle.PLAIN,
                            onClick = { partsErasing = !partsErasing; partsAdding = false },
                            modifier = Modifier.semantics { selected = partsErasing }
                        )
                        ImasText("消しゴム", ImasTextRole.META, color = if (partsErasing) DS.ink else DS.ink3, maxLines = 1)
                    }
                    // 一緒に歌う: 持っている間は、歌う人のタップで筆に足す / 外す (2 人以上で歌う所を塗る)。
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        ImasIconButton(
                            icon = Icons.Filled.GroupAdd, label = "一緒に歌う",
                            style = if (partsAdding) ImasIconButtonStyle.FILLED else ImasIconButtonStyle.PLAIN,
                            onClick = { partsAdding = !partsAdding; partsErasing = false },
                            modifier = Modifier.semantics { selected = partsAdding }
                        )
                        ImasText("一緒に歌う", ImasTextRole.META, color = if (partsAdding) DS.ink else DS.ink3, maxLines = 1)
                    }
                    cast.artists.forEach { idol ->
                        val isOn = !partsErasing && idol.id in brush
                        // 筆をその人 1 人に持ち替える (消しゴムからも持ち替える)。
                        val pick = {
                            partsErasing = false
                            partsBrushIds = listOf(idol.id)
                        }
                        // 一緒に歌う人として筆に足す / 外す (筆は 1 人は残す。空の筆では塗れない)。
                        val toggle = {
                            haptics.selection()
                            if (partsErasing) {
                                pick()
                            } else {
                                val next = brush.toMutableList()
                                if (idol.id in next) { if (next.size > 1) next.remove(idol.id) } else next.add(idol.id)
                                partsBrushIds = everyone.filter { it in next }
                            }
                        }
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            modifier = Modifier
                                // タップはその人 1 人に持ち替える (パートチェンジ)。「一緒に歌う」を持っているとき・長押しは足す / 外す。
                                .combinedClickable(
                                    interactionSource = remember { MutableInteractionSource() }, indication = null,
                                    onLongClickLabel = "一緒に歌う人に足す・外す",
                                    onLongClick = toggle,
                                    onClick = { if (partsAdding) toggle() else pick() }
                                )
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
                        onClick = {
                            partsErasing = false
                            partsBrushIds = if (isEveryone) everyone.take(1) else everyone
                        }
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
                    recorder.lane == LyricTimingRecorder.Lane.LINES ->
                        if (recorder.cursorOverwrites) "歌い出しで押し直す" else "歌い出しで押す"
                    else -> if (recorder.cursorOverwrites) "コールの頭で押し直す" else "コールの頭で押す"
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

// MARK: - 段ごとの歌詞: 動かして選ぶ

/**
 * 段の中身 (歌詞全体のスクロール)。歌詞の段は次に記録する行に、コールとパートの段は
 * 曲の流れ (`currentIndex` の行) に追従し、指でなぞると 4 秒止まる。
 * iOS `LyricTimingEditorView.laneLyrics` の移植。
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
    isPartsList: Boolean,
    onPaint: (String, Int, Int) -> Unit,
    partsTargetId: String?,
    partsErasing: Boolean,
    onPickPartsLine: (String) -> Unit,
    listState: LazyListState,
    followPausedUntil: () -> Long,
    onUserScroll: () -> Unit,
    pickedByTap: () -> Boolean,
    onPickByTap: () -> Unit,
    onPickHandled: () -> Unit,
    modifier: Modifier = Modifier
) {
    val accent = imasTheme(seed = seed).accent
    val isParts = recorder.lane == LyricTimingRecorder.Lane.PARTS
    val isLines = recorder.lane == LyricTimingRecorder.Lane.LINES

    // 指でなぞっている間と、離して少しの間は、曲に付いていく追従を止める。
    LaunchedEffect(listState) {
        while (true) {
            if (listState.isScrollInProgress) onUserScroll()
            delay(200)
        }
    }
    // 歌詞の段は次に記録する行に付いていく (押すたびに 1 行進む)。行をタップして選んだときは寄せない。
    LaunchedEffect(recorder.cursor, isLines) {
        val cursor = recorder.cursor ?: return@LaunchedEffect
        if (!isLines) return@LaunchedEffect
        if (pickedByTap()) { onPickHandled(); return@LaunchedEffect }
        val viewport = listState.layoutInfo.viewportSize.height
        // 先頭の案内文の分、添字を 1 つずらす。
        runCatching { listState.animateScrollToItem(cursor + 1, scrollOffset = -(viewport * 0.35f).toInt()) }
    }
    LaunchedEffect(currentIndex) {
        if (isLines) return@LaunchedEffect
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
                    ImasNote(if (isParts) "聴きながら塗るには Apple Music でのフル再生が必要です。一覧なら聴かずに塗れます。" else "記録には Apple Music でのフル再生が必要です。")
                }
                ImasText(
                    when (recorder.lane) {
                        LyricTimingRecorder.Lane.LINES -> "行をタップすると、その行から記録します。押すたびに次の行へ進みます。"
                        LyricTimingRecorder.Lane.CALLS -> "コールをタップして選ぶと、前後に寄せられます。"
                        LyricTimingRecorder.Lane.PARTS -> if (isPartsList) {
                            "行をタップして選び、語をタップ・なぞるか、コールの印か刷毛で塗ります。もう一度で外れます。"
                        } else "いま歌っている行を塗ります。過ぎた行はタップするとそこへ戻って聴き直せます。語をタップ・なぞるか、コールの印か刷毛で塗ります。"
                    },
                    ImasTextRole.META, color = DS.ink3
                )
            }
        }
        itemsIndexed(lyrics.lines, key = { _, line -> line.id }) { index, line ->
            val isCurrent = index == currentIndex
            when {
                line.kind == LyricLineKind.BLANK -> Spacer(Modifier.height(DS.sp1))
                isLines -> LinesLaneRow(
                    line = line, isCurrent = isCurrent, isNext = index == recorder.cursor,
                    start = recorder.start(line.id), accent = accent, seed = seed,
                    onPick = {
                        if (recorder.cursor != index) onPickByTap()
                        recorder.aim(line.id)
                    }
                )
                line.kind == LyricLineKind.MARKER -> ImasText(line.text, ImasTextRole.EYEBROW, color = DS.ink3)
                else -> if (isParts) {
                    PartsLaneRow(
                        line = line, isCurrent = isCurrent, isTarget = line.id == partsTargetId,
                        isErasing = partsErasing, recorder = recorder, cast = cast,
                        onSelectTarget = { onPickPartsLine(line.id) },
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

/** 歌詞の段の頭: 次に記録する行の状態と、1 行ずつ選び直す矢印。 */
@Composable
private fun CursorBar(recorder: LyricTimingRecorder) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(DS.sp3),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
            ImasText("次に記録する行", ImasTextRole.EYEBROW)
            ImasText(
                when {
                    recorder.cursor == null -> "最後まで記録しました。行をタップすると、そこから押し直せます。"
                    recorder.cursorOverwrites -> "記録済み・押すと上書き"
                    else -> "まだ時刻がありません"
                },
                ImasTextRole.META, color = DS.ink3, maxLines = 2
            )
        }
        ImasIconButton(icon = Icons.Filled.KeyboardArrowUp, label = "前の行にする", onClick = { recorder.stepCursor(-1) })
        ImasIconButton(
            icon = Icons.Filled.KeyboardArrowDown, label = "次の行にする",
            enabled = recorder.cursor != null, onClick = { recorder.stepCursor(1) }
        )
    }
}

/** 歌詞の段の 1 行。タップでその行を次に記録する行にする。記録した時刻を右に添える。 */
@Composable
private fun LinesLaneRow(
    line: LyricLine,
    isCurrent: Boolean,
    isNext: Boolean,
    start: Int?,
    accent: androidx.compose.ui.graphics.Color,
    seed: String?,
    onPick: () -> Unit
) {
    // 次に記録する行は「ここを押す」の印 (薄い地)、いま鳴っている行は濃い地。
    val state = when {
        isNext -> ImasLyricLineState.CURSOR
        isCurrent -> ImasLyricLineState.CURRENT
        else -> ImasLyricLineState.NORMAL
    }
    ImasLyricLineRow(
        state = state, seed = seed,
        modifier = Modifier
            .clickable(onClickLabel = "この行から記録する", onClick = onPick)
            .semantics { selected = isNext }
    ) {
        Row(
            Modifier.fillMaxWidth().padding(vertical = DS.sp2),
            horizontalArrangement = Arrangement.spacedBy(DS.sp3),
            verticalAlignment = Alignment.Top
        ) {
            Column(Modifier.weight(1f)) {
                if (line.kind == LyricLineKind.MARKER) {
                    ImasText(line.text, ImasTextRole.EYEBROW, color = DS.ink3)
                } else {
                    LaneLyricText(line.text, isCurrent || isNext)
                }
            }
            Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
                if (isNext) ImasText("次に記録", ImasTextRole.META, color = accent)
                ImasLyricTimeLabel(ms = start, isEmphasized = isNext)
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
 * パートの段の 1 行。行をタップすると塗る行に選ぶ (聴きながらなら、その行の頭へ戻して聴き直す)。
 * 選んだ行 (いま歌っている行) は語をタップ・長押しでなぞると、その字だけ塗る / 外す。
 * 右の刷毛で行まるごと、行の下のコールの印でそのコールの掛かる字だけ塗れる
 * (コールの所だけみんなで歌う、を 1 タップで)。
 * 塗ると前に歌っていた人と入れ替わる (パートチェンジ)。2 人で歌う所は筆に 2 人選んで塗る。
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun PartsLaneRow(
    line: LyricLine,
    isCurrent: Boolean,
    isTarget: Boolean,
    isErasing: Boolean,
    recorder: LyricTimingRecorder,
    cast: LyricPartCast,
    onSelectTarget: () -> Unit,
    onPaint: (Int, Int) -> Unit
) {
    val segments: List<LyricPartSegment> = recorder.segments(line.id)
    // 色は空白に置かない (語と語のあいだに色の塊が浮く)。
    val ink: List<LyricPartSegment> = recorder.inkSegments(line.id, line.text)
    val length = line.text.codePointCount(0, line.text.length)
    Column(verticalArrangement = Arrangement.spacedBy(DS.sp1)) {
        if (isTarget) {
            Row(horizontalArrangement = Arrangement.spacedBy(DS.sp2), verticalAlignment = Alignment.Top) {
                // 塗った字には歌う人 (先頭の人) の色を敷く。語のタップ・なぞりは [ImasPartsSelectableLine] が担う。
                val highlights = ink.mapNotNull { segment ->
                    cast.colors(segment.singers).firstOrNull()?.let { hex ->
                        ImasPartsHighlight(segment.start.toInt(), segment.end.toInt(), imasTheme(seed = hex).accent)
                    }
                }
                ImasPartsSelectableLine(
                    text = line.text, highlights = highlights, onSelect = onPaint, modifier = Modifier.weight(1f)
                )
                ImasIconButton(
                    icon = if (isErasing) Icons.Filled.AutoFixNormal else Icons.Filled.FormatColorFill,
                    label = if (isErasing) "行まるごと消す" else "行まるごと塗る",
                    size = ImasIconButtonSize.SMALL,
                    onClick = { onPaint(0, length) }
                )
            }
            // コールの掛かる字 (歌詞と同じ文字を一緒に歌う所など) を、範囲ぴったりに塗る。
            val anchored = line.calls.filter { it.hasAnchor && !it.isPenlight }
            if (anchored.isNotEmpty()) {
                FlowRow(horizontalArrangement = Arrangement.spacedBy(DS.sp2), verticalArrangement = Arrangement.spacedBy(DS.sp2)) {
                    anchored.forEach { call ->
                        ImasButton(
                            title = call.anchorText.ifEmpty { call.text },
                            icon = if (isErasing) Icons.Filled.AutoFixNormal else Icons.Filled.Campaign,
                            role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL,
                            onClick = { onPaint(call.start, call.end) },
                            accessibilityLabel = "コール「${call.text}」の所を${if (isErasing) "消す" else "塗る"}"
                        )
                    }
                }
            }
        } else {
            val marks: List<LyricPartMark> = ink.mapNotNull { segment ->
                val colors = cast.colors(segment.singers)
                if (colors.isEmpty()) null else LyricPartMark(segment.start.toInt(), segment.end.toInt(), colors)
            }
            Row(
                Modifier.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                    onSelectTarget()
                }
            ) {
                LaneLyricText(line.text, isCurrent, parts = marks)
            }
        }
        ImasPartNames(groups = segments.map { cast.names(it.singers) })
    }
}

/** 段の中の歌詞 1 行 (振り仮名は親字の上に、歌う人は字の色で)。 */
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
