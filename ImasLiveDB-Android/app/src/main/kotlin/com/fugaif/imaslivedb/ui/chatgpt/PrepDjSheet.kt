package com.fugaif.imaslivedb.ui.chatgpt

import android.util.Log
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AddBox
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.PlaylistPlayback
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasChipRow
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasFilterChip
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowDensity
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.designsystem.ImasSongRow
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import uniffi.imas_core.PrepDjPlan
import uniffi.imas_core.PrepDjTrack
import uniffi.imas_core.prepDjMaxOrderChars
import uniffi.imas_core.prepDjOrderExamples

private sealed interface PrepDjPhase {
    data object Loading : PrepDjPhase
    data class Loaded(val plan: PrepDjPlan) : PrepDjPhase

    /** 流れを組めない公演 (予測の対象でない)。 */
    data object Unavailable : PrepDjPhase
    data class Failed(val message: String) : PrepDjPhase
}

/**
 * 予習 DJ / 復習 DJ。公演 1 つぶんの曲を、本番の流れに並べて続けて流す。iOS `PrepDJSheet`。
 *
 * 並べ方はコア (`prepDjPlan`)。開催前は機械予測の上位を流れに並べ直し、セトリがあれば披露順のまま。
 * ChatGPT とつないでいれば、注文を聞いて組み直し、1 曲ごとに語りを付けられる ([com.fugaif.imaslivedb.data.chatgpt.PrepDjRunner.modelPlan])。
 * 語りはモデルの文なので、事実の行 (コアが作る) と分けて出す。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PrepDjSheet(showId: String, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val session by module.chatGptPlanService.state.collectAsState()
    val loadedSongId by module.lyricsPlayback.loadedSongId.collectAsState()
    val isPlaying by module.lyricsPlayback.isPlaying.collectAsState()
    val scope = rememberCoroutineScope()

    var phase by remember { mutableStateOf<PrepDjPhase>(PrepDjPhase.Loading) }
    var order by remember { mutableStateOf("") }
    var asking by remember { mutableStateOf<String?>(null) }
    var askError by remember { mutableStateOf<String?>(null) }
    var askJob by remember { mutableStateOf<Job?>(null) }
    // いまの頼みの印。やめた頼みの後始末が、次の頼みの表示に触らないようにする。
    var askToken by remember { mutableStateOf<Any?>(null) }
    var playFailed by remember { mutableStateOf(false) }
    var savedNote by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        phase = PrepDjPhase.Loading
        phase = try {
            module.prepDjRunner.basePlan(showId)?.let { PrepDjPhase.Loaded(it) } ?: PrepDjPhase.Unavailable
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e("PrepDj", "prep_dj_failed show=$showId: ${e.message}")
            PrepDjPhase.Failed(e.message ?: "")
        }
    }

    fun ask() {
        if (!session.canUsePlan || asking != null) return
        askError = null
        asking = "流れを考えています…"
        val note = order
        val token = Any()
        askToken = token
        askJob = scope.launch {
            try {
                val plan = module.prepDjRunner.modelPlan(showId, note) { label -> if (askToken === token) asking = label }
                if (askToken !== token) return@launch
                savedNote = null
                phase = PrepDjPhase.Loaded(plan)
            } catch (e: CancellationException) {
                // やめた。
                throw e
            } catch (e: Exception) {
                Log.e("PrepDj", "prep_dj_ask_failed: ${e.message}")
                if (askToken === token) askError = e.message ?: ""
            } finally {
                if (askToken === token) asking = null
            }
        }
    }

    fun cancelAsk() {
        askJob?.cancel()
        askJob = null
        askToken = null
        asking = null
    }

    fun play(plan: PrepDjPlan, from: Int) {
        scope.launch {
            val songs = module.songRepository.fetchSongsByIds(plan.tracks.map { it.songId })
            val byId = songs.associateBy { it.id }
            // id の順を保つ。Song に無い曲 (マスタに無い id) は落とすので、押した曲の位置は落とした後で数え直す。
            val ordered = plan.tracks.mapNotNull { byId[it.songId] }
            val startId = plan.tracks.getOrNull(from)?.songId
            val startAt = ordered.indexOfFirst { it.id == startId }.coerceAtLeast(0)
            playFailed = !PlaylistPlayback.play(module.lyricsPlayback, ordered, startAt)
        }
    }

    fun save(plan: PrepDjPlan) {
        scope.launch {
            savedNote = try {
                val created = module.playlistRepository.create(plan.title)
                module.playlistRepository.setSongIds(created.id, plan.tracks.map { it.songId })
                "プレイリスト「${plan.title}」に保存しました。"
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                "保存できませんでした。${e.message.orEmpty()}"
            }
        }
    }

    LaunchedEffect(showId) { load() }
    DisposableEffect(Unit) { onDispose { askJob?.cancel() } }

    fun close() {
        askJob?.cancel()
        onDismiss()
    }

    ModalBottomSheet(
        onDismissRequest = ::close,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg,
    ) {
        ImasFormBackdrop {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                val title = (phase as? PrepDjPhase.Loaded)?.plan?.heading ?: "予習 DJ"
                ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = ::close), title = title)
                Column(
                    Modifier.padding(horizontal = DS.Space.screen),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                ) {
                    when (val p = phase) {
                        PrepDjPhase.Loading -> ImasInlineLoading()
                        PrepDjPhase.Unavailable -> ImasEmptyState(
                            icon = Icons.Filled.MusicNote,
                            title = "この公演の流れは組めません",
                            message = "セトリが無く、予測もできない公演です",
                        )
                        is PrepDjPhase.Failed -> ImasEmptyState(
                            kind = ImasEmptyStateKind.FAILED,
                            title = "読み込めませんでした",
                            message = p.message,
                            actionTitle = "もう一度",
                            onAction = { scope.launch { load() } },
                        )
                        is PrepDjPhase.Loaded -> {
                            val plan = p.plan
                            Header(
                                plan = plan,
                                playFailed = playFailed,
                                unplayable = unplayableCount(plan, module.lyricsPlayback.fullPlaysWithoutAppleMusicId),
                                nowTalk = nowTalk(plan, isPlaying, loadedSongId),
                                savedNote = savedNote,
                                onPlay = { play(plan, 0) },
                                onSave = { save(plan) },
                            )
                            DjSection(
                                canUsePlan = session.canUsePlan,
                                plan = plan,
                                order = order,
                                onOrderChange = { order = it },
                                asking = asking,
                                askError = askError,
                                onAsk = ::ask,
                                onCancel = ::cancelAsk,
                            )
                            TrackSections(plan, loadedSongId, isPlaying, onPlay = { index -> play(plan, index) })
                            if (plan.byModel) {
                                ImasNote("語りは ChatGPT が書いています。事実と違うことがあります。", icon = Icons.Filled.Info)
                            }
                        }
                    }
                }
            }
        }
    }
}

/** Apple Music で鳴らせない曲の数。Spotify は曲名で探すので、鳴らしてみるまで分からない (0)。 */
private fun unplayableCount(plan: PrepDjPlan, fullPlaysWithoutAppleMusicId: Boolean): Int =
    if (fullPlaysWithoutAppleMusicId) 0 else plan.tracks.count { it.appleMusicId.isNullOrEmpty() }

/** いま流れている曲の語り (この流れの曲で、語りがあるときだけ)。 */
private fun nowTalk(plan: PrepDjPlan, isPlaying: Boolean, loadedSongId: String?): String? {
    if (!isPlaying || loadedSongId == null) return null
    return plan.tracks.firstOrNull { it.songId == loadedSongId }?.talk?.takeIf { it.isNotEmpty() }
}

@Composable
private fun Header(
    plan: PrepDjPlan,
    playFailed: Boolean,
    unplayable: Int,
    nowTalk: String?,
    savedNote: String?,
    onPlay: () -> Unit,
    onSave: () -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
        ImasText(plan.title, role = ImasTextRole.CARD_TITLE)
        ImasNote(plan.summary, icon = Icons.Filled.MusicNote)
        if (plan.note.isNotEmpty()) ImasNote(plan.note, icon = Icons.Filled.Warning)
        ImasButton(
            title = "流す",
            onClick = onPlay,
            icon = Icons.Filled.PlayArrow,
            role = ImasButtonRole.PRIMARY,
            size = ImasButtonSize.LARGE,
            fillsWidth = true,
        )
        if (playFailed) ImasNote("プレイリストの再生には Apple Music の契約が要ります。", icon = Icons.Filled.MusicNote)
        if (unplayable > 0) ImasNote("Apple Music に無い $unplayable 曲は飛ばします。", icon = Icons.Filled.SkipNext)
        if (nowTalk != null) ImasNote(nowTalk, icon = Icons.Filled.GraphicEq)
        ImasButton(
            title = "プレイリストに保存",
            onClick = onSave,
            icon = Icons.Filled.AddBox,
            role = ImasButtonRole.SECONDARY,
            size = ImasButtonSize.SMALL,
        )
        if (savedNote != null) ImasNote(savedNote, icon = Icons.Filled.Check)
    }
}

@Composable
private fun DjSection(
    canUsePlan: Boolean,
    plan: PrepDjPlan,
    order: String,
    onOrderChange: (String) -> Unit,
    asking: String?,
    askError: String?,
    onAsk: () -> Unit,
    onCancel: () -> Unit,
) {
    val maxChars = remember { prepDjMaxOrderChars().toInt() }
    val examples = remember { prepDjOrderExamples() }
    ImasSection("DJ に頼む", style = ImasSectionHeaderStyle.SMALL) {
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            when {
                !canUsePlan -> ImasNote(
                    "マイページで ChatGPT とつなぐと、注文どおりに組み直して 1 曲ごとの語りが付きます。",
                    icon = Icons.Filled.GraphicEq,
                )
                asking != null -> Column(
                    Modifier.fillMaxWidth(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
                ) {
                    ImasInlineLoading(tint = DS.sys)
                    ImasText(asking, role = ImasTextRole.NOTE)
                    ImasButton(title = "やめる", onClick = onCancel, icon = Icons.Filled.Close, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL)
                }
                else -> {
                    ImasSearchField(
                        prompt = "注文 (無くても頼めます)",
                        text = order,
                        onTextChange = { onOrderChange(it.take(maxChars)) },
                        onSubmit = onAsk,
                    )
                    ImasChipRow(contentPadding = DS.Space.rowH) {
                        examples.forEach { example ->
                            ImasFilterChip(label = example, selected = order == example, onClick = { onOrderChange(example) })
                        }
                    }
                    ImasButton(
                        title = if (plan.byModel) "組み直してもらう" else "語りを付けてもらう",
                        onClick = onAsk,
                        icon = Icons.Filled.GraphicEq,
                        role = ImasButtonRole.SECONDARY,
                        fillsWidth = true,
                    )
                    if (askError != null) ImasNotice(kind = ImasNoticeKind.ERROR, message = askError)
                }
            }
        }
    }
}

private data class Group(val label: String, val tracks: MutableList<Pair<Int, PrepDjTrack>>)

/** 塊の頭の印 (コアの `startsPart`) で切るだけ。 */
private fun groups(tracks: List<PrepDjTrack>): List<Group> {
    val out = mutableListOf<Group>()
    tracks.forEachIndexed { index, track ->
        if (track.startsPart || out.isEmpty()) out.add(Group(track.partLabel, mutableListOf()))
        out.last().tracks.add(index to track)
    }
    return out
}

@Composable
private fun TrackSections(plan: PrepDjPlan, loadedSongId: String?, isPlaying: Boolean, onPlay: (Int) -> Unit) {
    groups(plan.tracks).forEach { group ->
        ImasSection(group.label, count = "${group.tracks.size}曲", style = ImasSectionHeaderStyle.SMALL) {
            ImasCardList {
                group.tracks.forEach { (index, track) ->
                    ImasSongRow(
                        title = track.title,
                        subtitle = track.fact.ifEmpty { null },
                        artworkUrl = track.artworkUrl,
                        brand = track.brandId,
                        trailing = if (isPlaying && loadedSongId == track.songId) ImasRowTrailing.Value("再生中") else ImasRowTrailing.None,
                        density = ImasRowDensity.COMPACT,
                        onClick = { onPlay(index) },
                        detail = if (track.talk.isEmpty()) null else {
                            { ImasText(track.talk, role = ImasTextRole.NOTE) }
                        },
                    )
                }
            }
        }
    }
}
