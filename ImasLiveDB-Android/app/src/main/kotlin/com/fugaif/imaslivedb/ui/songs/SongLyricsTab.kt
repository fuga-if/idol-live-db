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
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.FormatQuote
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Link
import androidx.compose.material.icons.filled.QueueMusic
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Superscript
import androidx.compose.material.icons.filled.TextFields
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
import com.fugaif.imaslivedb.data.lyrics.LyricPartCast
import com.fugaif.imaslivedb.data.lyrics.Lyrics
import com.fugaif.imaslivedb.data.lyrics.LyricsResult
import com.fugaif.imaslivedb.data.lyrics.StructureChange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.LyricsSession
import com.fugaif.imaslivedb.ui.designsystem.ImasAsideStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasAvatar
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
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricAside
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLikeMark
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLineRow
import com.fugaif.imaslivedb.ui.designsystem.ImasLyricLineState
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasPartNames
import com.fugaif.imaslivedb.ui.designsystem.ImasPartStripe
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyFlowText
import com.fugaif.imaslivedb.ui.designsystem.ImasRubyText
import com.fugaif.imaslivedb.ui.designsystem.RubyHighlight
import com.fugaif.imaslivedb.ui.designsystem.codePointToCharIndex
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
import uniffi.imas_core.LyricRubyChoice
import uniffi.imas_core.lyricPartsApplicable
import uniffi.imas_core.lyricRubyChoices

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
    originalArtists: List<Idol> = emptyList(),
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
    // 非 null = パート分けを編集している (行 ID → 歌唱者のアイドル id)。
    var partsDraft by remember { mutableStateOf<Map<String, List<String>>?>(null) }
    // パート分けの「筆」= いま付けている歌唱者。行をタップするとこの人を付け外しする。
    var partsBrush by remember { mutableStateOf<String?>(null) }
    var partsSaving by remember { mutableStateOf(false) }

    val lyrics = (lyricsResult as? LyricsResult.Loaded)?.lyrics
    val playback = module.lyricsPlayback
    // パート分けは原唱者が 2 人以上の曲だけ (ソロ曲では帯も名前も出さない。imas-core `lyricPartsApplicable`)。
    val partsApplicable = remember(originalArtists) { lyricPartsApplicable(originalArtists.size.toUInt()) }
    val partCast = remember(originalArtists, partsApplicable) {
        if (partsApplicable) LyricPartCast(originalArtists) else LyricPartCast.EMPTY
    }

    fun currentParts(l: Lyrics): Map<String, List<String>> =
        l.lines.filter { it.singers.isNotEmpty() }.associate { it.id to it.singers }

    LaunchedEffect(song.id) { likes = module.userMarkRepository.lyricLikes(song.id) }

    // フル再生中の曲なら、再生中バーから今の行・歌詞プレイヤーを出せるよう預ける (メモリだけ)。
    val loadedSongId by playback.loadedSongId.collectAsState()
    LaunchedEffect(song.id, lyrics?.updatedAt, loadedSongId, partCast) {
        if (lyrics != null && loadedSongId == song.id) {
            LyricsSession.register(
                LyricsSession.Entry(
                    song = song, seed = seed, artistLine = artistLine,
                    artworkUrl = song.artworkUrl, lyrics = lyrics, cast = partCast
                )
            )
        }
    }

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
        // 鳴らせない端末だけは開かない。未サインインなら、編集画面がサインインの案内を出し、
        // サインインの画面も鳴らそうとした時点で自動で開く (戻ると鳴り始める)。
        if (playback.appleMusicState.value == com.fugaif.imaslivedb.player.AppleMusicState.UNAVAILABLE) {
            recordUnavailable = true
            return
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

    // 筆の人をその行に付け外しする。並びは原唱者の並びに揃える (帯の縞の順を決めておく)。
    fun togglePart(lineId: String) {
        val brush = partsBrush ?: return
        val draft = partsDraft ?: return
        var singers = draft[lineId] ?: emptyList()
        singers = if (brush in singers) singers - brush else singers + brush
        singers = partCast.ordered(singers)
        partsDraft = if (singers.isEmpty()) draft - lineId else draft + (lineId to singers)
    }

    suspend fun saveParts(current: Lyrics) {
        val draft = partsDraft ?: return
        partsSaving = true
        try {
            val lines = current.lines.mapNotNull { line -> draft[line.id]?.let { line.id to it } }
            module.lyricsApi.saveParts(song.id, lines)
            partsDraft = null
            partsBrush = null
            onReload()
        } catch (e: Exception) {
            structureError = e.message ?: "保存できませんでした"
        } finally {
            partsSaving = false
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
                val draft = partsDraft
                EditBar(
                    canEdit = canEdit, isEditingStructure = isEditingStructure,
                    showsPartsButton = partsApplicable,
                    partsDraft = draft, partsSaving = partsSaving,
                    partsUnchanged = draft != null && draft == currentParts(lyrics),
                    onToggleStructureEdit = { isEditingStructure = !isEditingStructure },
                    onOpenPlayer = { showPlayer = true },
                    onBeginRecording = { scope.launch { beginRecording(lyrics) } },
                    onBeginParts = {
                        partsDraft = currentParts(lyrics)
                        partsBrush = originalArtists.firstOrNull()?.id
                    },
                    onCancelParts = { partsDraft = null; partsBrush = null },
                    onSaveParts = { scope.launch { saveParts(lyrics) } }
                )
                when {
                    draft != null -> {
                        ImasNote(
                            "歌う人を選んでから、歌詞の行をタップします。もう一度タップすると外れます。",
                            modifier = Modifier.padding(vertical = DS.sp2)
                        )
                        PartsBrushBar(artists = originalArtists, brush = partsBrush, onSelect = { partsBrush = it })
                        LyricsCard(song.title, artistLine) {
                            PartsBody(lyrics = lyrics, draft = draft, cast = partCast, onToggle = ::togglePart)
                        }
                    }
                    isEditingStructure -> {
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
                                onMerge = { lineId, joiner -> changeStructure(lineId, StructureChange.Merge(lineId, joiner)) },
                                onToggleRuby = { lineId, at, isRuby ->
                                    changeStructure(
                                        lineId,
                                        if (isRuby) StructureChange.Unruby(lineId, at) else StructureChange.Ruby(lineId, at)
                                    )
                                },
                                onRubyBase = { lineId, at, isRuby, base ->
                                    changeStructure(
                                        lineId,
                                        if (isRuby) StructureChange.RubyBase(lineId, at, base) else StructureChange.Ruby(lineId, at, base)
                                    )
                                }
                            )
                        }
                    }
                    else -> {
                        LyricsCard(song.title, artistLine) {
                            ViewingBody(
                                lyrics = lyrics, seed = seed, likes = likes, activeLineId = activeLineId,
                                heatTick = heatTick, song = song, cast = partCast,
                                onToggleLike = ::toggleLike
                            )
                        }
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
                onClose = { showPlayer = false }, cast = partCast
            )
        }
    }
    val activeRecorder = recorder
    if (activeRecorder != null && lyrics != null) {
        Dialog(onDismissRequest = {}, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            LyricTimingEditorScreen(
                song = song, seed = seed, lyrics = lyrics, recorder = activeRecorder,
                onSaved = onReload, onClose = { recorder = null }, cast = partCast
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
    showsPartsButton: Boolean,
    partsDraft: Map<String, List<String>>?,
    partsSaving: Boolean,
    partsUnchanged: Boolean,
    onToggleStructureEdit: () -> Unit,
    onOpenPlayer: () -> Unit,
    onBeginRecording: () -> Unit,
    onBeginParts: () -> Unit,
    onCancelParts: () -> Unit,
    onSaveParts: () -> Unit
) {
    if (!canEdit) return
    Row(Modifier.fillMaxWidth().padding(bottom = DS.sp2), horizontalArrangement = Arrangement.spacedBy(DS.sp3)) {
        Spacer(Modifier.weight(1f))
        when {
            partsDraft != null -> {
                ImasButton(title = "やめる", role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL, onClick = onCancelParts)
                ImasButton(
                    title = "保存", role = ImasButtonRole.PRIMARY, size = ImasButtonSize.SMALL,
                    isLoading = partsSaving, enabled = !partsSaving && !partsUnchanged, onClick = onSaveParts
                )
            }
            isEditingStructure -> {
                ImasButton(title = "区切りの編集を終了", role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL, onClick = onToggleStructureEdit)
            }
            else -> {
                if (showsPartsButton) {
                    ImasIconButton(icon = Icons.Filled.Group, label = "パート分け", size = ImasIconButtonSize.SMALL, onClick = onBeginParts)
                }
                ImasIconButton(icon = Icons.Filled.ContentCut, label = "行の区切りを編集", size = ImasIconButtonSize.SMALL, onClick = onToggleStructureEdit)
                ImasIconButton(icon = Icons.Filled.QueueMusic, label = "歌詞プレイヤー", size = ImasIconButtonSize.SMALL, onClick = onOpenPlayer)
                ImasIconButton(icon = Icons.Filled.Speed, label = "タイミングを編集", size = ImasIconButtonSize.SMALL, onClick = onBeginRecording)
            }
        }
    }
}

// MARK: - パート分け (誰が歌うか)

/** 筆 (歌唱者) を選ぶ帯。原唱者のアイコンを並べ、選んだ人に輪を付ける。 */
@Composable
private fun PartsBrushBar(artists: List<Idol>, brush: String?, onSelect: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = DS.sp2),
        horizontalArrangement = Arrangement.spacedBy(DS.sp2)
    ) {
        artists.forEach { idol ->
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .padding(vertical = DS.sp1)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onSelect(idol.id) }
            ) {
                ImasAvatar(label = idol.shortName, seed = idol.color, brand = idol.brandId, size = 36.dp, isPick = brush == idol.id, entityId = idol.id)
                Text(
                    idol.shortName,
                    style = com.fugaif.imaslivedb.ui.theme.ImasTextRole.META.style,
                    color = if (brush == idol.id) DS.ink else DS.ink3,
                    maxLines = 1
                )
            }
        }
    }
}

@Composable
private fun PartsBody(lyrics: Lyrics, draft: Map<String, List<String>>, cast: LyricPartCast, onToggle: (String) -> Unit) {
    lyrics.lines.forEach { line ->
        when (line.kind) {
            LyricLineKind.LYRIC -> {
                val singers = draft[line.id] ?: emptyList()
                Row(
                    Modifier
                        .fillMaxWidth()
                        .height(IntrinsicSize.Min)
                        .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onToggle(line.id) }
                        .padding(vertical = DS.sp2),
                    horizontalArrangement = Arrangement.spacedBy(DS.sp2),
                    verticalAlignment = Alignment.Top
                ) {
                    ImasPartStripe(colors = cast.colors(singers))
                    Column(Modifier.weight(1f)) {
                        Text(
                            line.text,
                            style = com.fugaif.imaslivedb.ui.theme.ImasTextRole.BODY.style,
                            color = DS.ink
                        )
                        ImasPartNames(names = cast.names(singers))
                    }
                }
            }
            LyricLineKind.MARKER -> SectionMarker(line.text)
            LyricLineKind.BLANK -> Spacer(Modifier.height(DS.sp3))
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
    cast: LyricPartCast,
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
            ViewingRow(line = line, isLiked = likes.contains(line.id), accent = theme.accent, cast = cast, onToggleLike = onToggleLike)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun ViewingRow(line: LyricLine, isLiked: Boolean, accent: Color, cast: LyricPartCast, onToggleLike: (LyricLine) -> Unit) {
    when (line.kind) {
        LyricLineKind.LYRIC -> {
            Row(
                Modifier
                    .fillMaxWidth()
                    .height(IntrinsicSize.Min)
                    .padding(vertical = DS.sp1)
                    .combinedClickable(onClick = {}, onDoubleClick = { onToggleLike(line) }),
                horizontalArrangement = Arrangement.spacedBy(DS.sp2),
                verticalAlignment = Alignment.Top
            ) {
                ImasClapGlyph(clap = line.clap, modifier = Modifier.padding(top = DS.sp1))
                if (line.singers.isNotEmpty()) ImasPartStripe(colors = cast.colors(line.singers))
                Column(Modifier.weight(1f)) {
                    // ⚠️ ここに SelectionContainer / テキストコピーの口を足さないこと。
                    val highlights = highlightsFor(line, accent)
                    // 括弧で書いた脇の字 (被せ・歌わない字) は一段小さく薄く出す (規則はコア)。
                    val asideStyle = ImasLyricAside.forViewing()
                    if (ImasRubyText.hasRuby(line.text)) {
                        // 振り仮名は親字の上に乗せる (Text では組めないので FlowRow で自前に組む)。
                        ImasRubyFlowText(
                            text = line.text,
                            style = ImasTextRole.BODY.style,
                            color = DS.ink,
                            highlightAt = rubyHighlightLookup(line.text, highlights),
                            asideStyle = asideStyle
                        )
                    } else {
                        Text(
                            text = highlightedLyricText(line.text, highlights, asideStyle),
                            style = ImasTextRole.BODY.style,
                            color = DS.ink
                        )
                    }
                    ImasPartNames(names = cast.names(line.singers))
                    // 歌詞と同じ文字の同時コールは行に並べない (歌詞のその部分を濃く敷いて示す)。
                    val listed = line.calls.filter { !line.echoes(it) }
                    if (listed.isNotEmpty()) ImasCallRows(calls = listed, anchorIndexes = anchorIndexesFor(line))
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
    onMerge: (String, LyricJoiner) -> Unit,
    onToggleRuby: (String, Int, Boolean) -> Unit,
    onRubyBase: (String, Int, Boolean, Int) -> Unit
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
                    RubyToggles(
                        line = line, busy = busyLineId != null,
                        onToggle = { at, isRuby -> onToggleRuby(line.id, at, isRuby) },
                        onRubyBase = { at, isRuby, base -> onRubyBase(line.id, at, isRuby, base) }
                    )
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

/**
 * 行の中の振り仮名 (《》) と、振り仮名にできる括弧を並べる (候補の規則はコアの `lyricRubyChoices`)。
 * 親字の頭は選べる (当て字や、漢字のまとまりの一部だけに掛けるとき)。位置はスカラー (= コードポイント)
 * のまま扱う (iOS `SongLyricsTab.rubyToggles` の移植)。
 */
@Composable
private fun RubyToggles(
    line: LyricLine,
    busy: Boolean,
    onToggle: (Int, Boolean) -> Unit,
    onRubyBase: (Int, Boolean, Int) -> Unit
) {
    val choices = remember(line.text) { lyricRubyChoices(line.text) }
    if (choices.isEmpty()) return
    // 振る字を選んでいる最中の候補の開き位置 (同時に 1 つだけ)。
    var pickerOpen by remember { mutableStateOf<UInt?>(null) }
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
        horizontalArrangement = Arrangement.spacedBy(DS.sp2)
    ) {
        choices.forEach { choice ->
            val at = choice.open.toInt()
            if (choice.isRuby) {
                ImasButton(
                    title = "「${choice.reading}」をルビにしない", icon = Icons.Filled.TextFields,
                    role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL, enabled = !busy,
                    onClick = { onToggle(at, true) }
                )
                if (choice.bases.size > 1) {
                    Box {
                        ImasButton(
                            title = "「${choice.reading}」を振る字を選ぶ", icon = Icons.Filled.Superscript,
                            role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL, enabled = !busy,
                            onClick = { pickerOpen = choice.open }
                        )
                        RubyBasePickerMenu(
                            text = line.text, choice = choice, expanded = pickerOpen == choice.open,
                            onDismiss = { pickerOpen = null },
                            onSelect = { base -> pickerOpen = null; onRubyBase(at, true, base.toInt()) }
                        )
                    }
                }
            } else {
                Box {
                    ImasButton(
                        title = "「${choice.reading}」をルビにする", icon = Icons.Filled.Superscript,
                        role = ImasButtonRole.PLAIN, size = ImasButtonSize.SMALL, enabled = !busy,
                        onClick = {
                            // 漢字の直後なら漢字のまとまりに振る (違えば「振る字を選ぶ」で直す)。当て字は選んでもらう。
                            if (choice.base != null) onToggle(at, false) else pickerOpen = choice.open
                        }
                    )
                    RubyBasePickerMenu(
                        text = line.text, choice = choice, expanded = pickerOpen == choice.open,
                        onDismiss = { pickerOpen = null },
                        onSelect = { base -> pickerOpen = null; onRubyBase(at, false, base.toInt()) }
                    )
                }
            }
        }
    }
}

/** 「「reading」を振る字」を選ぶドロップダウン ([choice.bases] から)。いまの親字には「(いま)」を付す。 */
@Composable
private fun RubyBasePickerMenu(
    text: String,
    choice: LyricRubyChoice,
    expanded: Boolean,
    onDismiss: () -> Unit,
    onSelect: (UInt) -> Unit
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        choice.bases.forEach { base ->
            val label = "「${rubyBaseText(text, base, choice.open)}」"
            val isCurrent = choice.isRuby && choice.base == base
            DropdownMenuItem(
                text = { Text(if (isCurrent) "$label (いま)" else label) },
                onClick = { onSelect(base) }
            )
        }
    }
}

/** 親字の頭を [base] にしたときの親字 (「｜」は除く)。 */
private fun rubyBaseText(text: String, base: UInt, open: UInt): String {
    val s = codePointToCharIndex(text, base.toInt())
    val e = codePointToCharIndex(text, open.toInt())
    return text.substring(s, e).filter { it != '｜' }
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
    return order.mapNotNull { key ->
        strongest[key]?.let {
            LyricHighlight(
                it.start, it.end, it.emphasis.lyricColor(accent),
                isEcho = line.calls.any { c -> c.start == it.start && c.end == it.end && line.echoes(c) }
            )
        }
    }
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
    // 行に並べない (歌詞と同じ文字の同時) コールは番号を振る数に入れない。
    for (call in line.calls.filter { it.hasAnchor && !line.echoes(it) }) {
        val key = "${call.start}-${call.end}"
        if (groups[key] == null) { groups[key] = order; order++ }
        result[call.id] = groups[key]!!
    }
    return if (order > 1) result else null
}

private data class LyricHighlight(val start: Int, val end: Int, val color: Color, val isEcho: Boolean = false)

/**
 * 各コードポイントがどのアンカーに入るか (重なりは先勝ち)。[highlightedLyricText] と
 * [rubyHighlightLookup] の両方で使う (iOS `CallGuideText.owners`)。
 */
private fun ownersFor(text: String, highlights: List<LyricHighlight>): Array<Int?> {
    val totalScalars = text.codePointCount(0, text.length)
    val owner = arrayOfNulls<Int>(totalScalars)
    var cursor = 0
    for ((index, h) in highlights.withIndex().sortedBy { it.value.start }) {
        val s = maxOf(h.start, cursor)
        val e = minOf(h.end, totalScalars)
        if (s >= e) continue
        for (k in s until e) owner[k] = index
        cursor = e
    }
    return owner
}

/**
 * アンカー範囲に色を敷いた行を組み立てる (iOS `CallGuideText.attributed`)。振り仮名のある行は
 * ここを通らず [ImasRubyFlowText] (+ [rubyHighlightLookup]) で組む。
 *
 * ⚠️ `start`/`end` は Unicode スカラー (= Java の codePoint) 単位。Kotlin の `String` は
 * UTF-16 なので、絵文字などサロゲートペアを含む行では文字添字への変換が必要 ([codePointToCharIndex])。
 */
private fun highlightedLyricText(text: String, highlights: List<LyricHighlight>, asideStyle: ImasAsideStyle): AnnotatedString {
    val owner = ownersFor(text, highlights)
    // 括弧で書いた脇の字 (被せ・歌わない字) は一段小さく薄く出す。アンカーの敷きと両立させる。
    val aside = ImasRubyText.asides(text)
    return buildAnnotatedString {
        var k = 0
        while (k < owner.size) {
            val start = k
            val current = owner[k]
            val isAside = aside[k]
            while (k < owner.size && owner[k] == current && aside[k] == isAside) k++
            val segmentText = text.substring(codePointToCharIndex(text, start), codePointToCharIndex(text, k))
            val highlight = current?.let { highlights[it] }
            var style: SpanStyle? = if (isAside) SpanStyle(fontSize = asideStyle.fontSize, color = asideStyle.color, fontWeight = asideStyle.weight) else null
            if (highlight != null) {
                // 同時コールの「一緒に」範囲は、歌詞と同じ文字を 2 回出さない代わりにここを濃く太字にする。
                val highlightStyle = SpanStyle(
                    background = highlight.color.copy(alpha = if (highlight.isEcho) 0.32f else 0.18f),
                    fontWeight = if (highlight.isEcho) FontWeight.Bold else null,
                    textDecoration = TextDecoration.Underline
                )
                style = style?.merge(highlightStyle) ?: highlightStyle
            }
            if (style == null) append(segmentText) else withStyle(style) { append(segmentText) }
        }
    }
}

/**
 * [ImasRubyFlowText] の `highlightAt` に渡す、コードポイント添字からアンカーの装いを引く関数
 * (iOS `CallGuideText.rubyAttributed` の移植)。振り仮名の読みそのものには装いを付けない
 * (呼び出し側が親字の先頭添字しか渡さないため、自然とそうなる)。
 */
private fun rubyHighlightLookup(text: String, highlights: List<LyricHighlight>): (Int) -> RubyHighlight? {
    val owner = ownersFor(text, highlights)
    return { k ->
        owner.getOrNull(k)?.let { highlights[it] }?.let { h ->
            RubyHighlight(
                background = h.color.copy(alpha = if (h.isEcho) 0.32f else 0.18f),
                bold = h.isEcho,
                underline = true
            )
        }
    }
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
