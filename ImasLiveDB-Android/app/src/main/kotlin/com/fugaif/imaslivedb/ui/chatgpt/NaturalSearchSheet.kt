package com.fugaif.imaslivedb.ui.chatgpt

import android.util.Log
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
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
import com.fugaif.imaslivedb.data.model.EventWithDateRange
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.PlaylistPlayback
import com.fugaif.imaslivedb.ui.components.ImasSongRow
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasEventRow
import com.fugaif.imaslivedb.ui.designsystem.ImasFormBackdrop
import com.fugaif.imaslivedb.ui.designsystem.ImasIconTileTone
import com.fugaif.imaslivedb.ui.designsystem.ImasIdolRow
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNavRow
import com.fugaif.imaslivedb.ui.designsystem.ImasNote
import com.fugaif.imaslivedb.ui.designsystem.ImasRowTrailing
import com.fugaif.imaslivedb.ui.designsystem.ImasSearchField
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbar
import com.fugaif.imaslivedb.ui.designsystem.ImasSheetToolbarKind
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import uniffi.imas_core.NaturalSearchAnswer
import uniffi.imas_core.naturalSearchAccepts
import uniffi.imas_core.naturalSearchExamples

/** 結果の行から開く先 (アプリの本体の詳細画面。開く経路は AppNavigation が拾う)。 */
/** SHOW / UNIT は文で探すの結果には出ず、チャットの「開く」だけが使う。 */
enum class NaturalSearchKind { SONG, IDOL, EVENT, SHOW, UNIT }

data class NaturalSearchTarget(val kind: NaturalSearchKind, val id: String)

/**
 * 結果の行を押したときの「詳細を開いて」の依頼。iOS はシートの中に詳細を積むが、Android のシートは
 * ナビゲーションの外にあるので、シートを閉じて本体の側で開く (`CrossTabSearch` と同じ受け渡し)。
 */
object NaturalSearchOpen {
    private var _pending by mutableStateOf<NaturalSearchTarget?>(null)
    val pending: NaturalSearchTarget? get() = _pending

    fun request(kind: NaturalSearchKind, id: String) {
        _pending = NaturalSearchTarget(kind, id)
    }

    fun consume() {
        _pending = null
    }
}

/**
 * チャットの「画面を開く」(P名刺・収支など) の依頼。[NaturalSearchOpen] と同じ受け渡しで、
 * 本体のナビがプロデュースのタブの中で開く。iOS はシートの中に積む。
 */
object AssistantScreenOpen {
    private var _pending by mutableStateOf<com.fugaif.imaslivedb.data.chatgpt.AssistantScreen?>(null)
    val pending: com.fugaif.imaslivedb.data.chatgpt.AssistantScreen? get() = _pending

    fun request(screen: com.fugaif.imaslivedb.data.chatgpt.AssistantScreen) {
        _pending = screen
    }

    fun consume() {
        _pending = null
    }
}

private sealed interface Phase {
    data object Idle : Phase
    data class Running(val label: String) : Phase
    data class Done(val results: Results) : Phase
    data class Failed(val message: String) : Phase
}

/** 実体化まで済んだ結果。並びはコアが返した id の順。 */
private data class Results(
    val interpretation: String,
    val songs: List<Song>,
    val idols: List<Idol>,
    val events: List<EventWithDateRange>,
    val unreadable: Boolean,
) {
    val isEmpty: Boolean get() = songs.isEmpty() && idols.isEmpty() && events.isEmpty()
}

/**
 * 文で探す。利用者の ChatGPT プランでモデルに DB を引かせ、当たったものをいつもの行で出す。iOS `NaturalSearchSheet`。
 *
 * 文章の答えは出さない (会話にしない)。出すのはコアが「DB に実在する」と確かめた id の曲・アイドル・ライブだけで、
 * 行を押せばいつもの詳細へ進む。
 *
 * @param onOpen 行を押したとき。既定は [NaturalSearchOpen] へ依頼してシートを閉じる。
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NaturalSearchSheet(
    initialQuery: String,
    onDismiss: () -> Unit,
    onOpen: (NaturalSearchKind, String) -> Unit = { kind, id -> NaturalSearchOpen.request(kind, id) },
) {
    val context = LocalContext.current
    val module = remember { AppModule.from(context) }
    val session by module.chatGptPlanService.state.collectAsState()
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(initialQuery) }
    var phase by remember { mutableStateOf<Phase>(Phase.Idle) }
    var runJob by remember { mutableStateOf<Job?>(null) }
    var playFailed by remember { mutableStateOf(false) }

    fun run() {
        val query = text
        if (!session.canUsePlan || !naturalSearchAccepts(query)) return
        runJob?.cancel()
        phase = Phase.Running("探しています…")
        runJob = scope.launch {
            try {
                val answer = module.naturalSearchRunner.run(query) { label -> phase = Phase.Running(label) }
                val results = materialize(module, answer)
                phase = Phase.Done(results)
            } catch (e: CancellationException) {
                // やめた・打ち直した。表示は呼んだ側が切り替えている。
                throw e
            } catch (e: Exception) {
                Log.e("NaturalSearch", "natural_search_failed: ${e.message}")
                phase = Phase.Failed(e.message ?: "")
            }
        }
    }

    fun cancel() {
        runJob?.cancel()
        runJob = null
        phase = Phase.Idle
    }

    LaunchedEffect(Unit) { if (session.canUsePlan && naturalSearchAccepts(initialQuery)) run() }
    DisposableEffect(Unit) { onDispose { runJob?.cancel() } }

    fun close() {
        runJob?.cancel()
        onDismiss()
    }

    ModalBottomSheet(
        onDismissRequest = { close() },
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = DS.bg,
    ) {
        ImasFormBackdrop {
            Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(bottom = DS.Space.section)) {
                ImasSheetToolbar(ImasSheetToolbarKind.Read(onClose = { close() }), title = "文で探す")
                Column(
                    Modifier.padding(horizontal = DS.Space.screen),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                ) {
                    ImasSearchField(prompt = "文で探す", text = text, onTextChange = { text = it }, onSubmit = { run() })
                    Content(
                        canUsePlan = session.canUsePlan,
                        phase = phase,
                        onExample = { example -> text = example; run() },
                        onCancel = { cancel() },
                        onRetry = { run() },
                        onOpen = { kind, id -> close(); onOpen(kind, id) },
                        playFailed = playFailed,
                        onPlayAll = { songs ->
                            scope.launch { playFailed = !PlaylistPlayback.play(module.lyricsPlayback, songs) }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun Content(
    canUsePlan: Boolean,
    phase: Phase,
    onExample: (String) -> Unit,
    onCancel: () -> Unit,
    onRetry: () -> Unit,
    onOpen: (NaturalSearchKind, String) -> Unit,
    playFailed: Boolean,
    onPlayAll: (List<Song>) -> Unit,
) {
    if (!canUsePlan) {
        ImasEmptyState(
            icon = Icons.Filled.Search,
            title = "ChatGPT とつなぐと使えます",
            message = "マイページの「ChatGPT とつなぐ」から、ChatGPT Plus / Pro のアカウントでログインしてください",
        )
        return
    }
    when (phase) {
        Phase.Idle -> Examples(onExample)
        is Phase.Running -> Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
        ) {
            ImasInlineLoading(tint = DS.sys)
            ImasText(phase.label, role = ImasTextRole.NOTE)
            ImasButton(title = "やめる", onClick = onCancel, icon = Icons.Filled.Close, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL)
        }
        is Phase.Done -> ResultSections(phase.results, onOpen, playFailed, onPlayAll)
        is Phase.Failed -> ImasEmptyState(
            kind = ImasEmptyStateKind.FAILED,
            title = "探せませんでした",
            message = phase.message,
            actionTitle = "もう一度",
            onAction = onRetry,
        )
    }
}

@Composable
private fun Examples(onExample: (String) -> Unit) {
    val examples = remember { naturalSearchExamples() }
    ImasSection("たとえば", style = ImasSectionHeaderStyle.SMALL) {
        ImasCardList {
            examples.forEach { example ->
                ImasNavRow(title = example, icon = Icons.Filled.Search, iconTone = ImasIconTileTone.NEUTRAL, onClick = { onExample(example) })
            }
        }
    }
}

@Composable
private fun ResultSections(
    results: Results,
    onOpen: (NaturalSearchKind, String) -> Unit,
    playFailed: Boolean,
    onPlayAll: (List<Song>) -> Unit,
) {
    if (results.interpretation.isNotEmpty()) ImasNote(results.interpretation, icon = Icons.Filled.Search)
    if (results.isEmpty) {
        ImasEmptyState(
            kind = ImasEmptyStateKind.NO_RESULTS,
            title = if (results.unreadable) "うまく探せませんでした" else "見つかりませんでした",
            message = "言い方を変えるか、文を短くして試してください",
        )
    }
    if (results.songs.isNotEmpty()) {
        // 当たった曲はそのまま続けて流せる (並びはコアが返した順)。
        ImasSection(
            "曲",
            count = "${results.songs.size}曲",
            actionTitle = "続けて流す",
            actionIcon = Icons.Filled.PlayArrow,
            onAction = { onPlayAll(results.songs) },
        ) {
            if (playFailed) {
                ImasNote("プレイリストの再生には Apple Music の契約が要ります。", modifier = Modifier.padding(bottom = DS.Space.header))
            }
            ImasCardList {
                results.songs.forEach { song ->
                    ImasSongRow(song = song, trailing = ImasRowTrailing.Chevron, onClick = { onOpen(NaturalSearchKind.SONG, song.id) })
                }
            }
        }
    }
    if (results.idols.isNotEmpty()) {
        ImasSection("アイドル", count = "${results.idols.size}人") {
            ImasCardList {
                results.idols.forEach { idol ->
                    ImasIdolRow(idol = idol, trailing = ImasRowTrailing.Chevron, onClick = { onOpen(NaturalSearchKind.IDOL, idol.id) })
                }
            }
        }
    }
    if (results.events.isNotEmpty()) {
        ImasSection("ライブ", count = "${results.events.size}件") {
            ImasCardList {
                results.events.forEach { item ->
                    ImasEventRow(
                        event = item.event,
                        date = item.firstDate,
                        subtitle = item.dateRange,
                        showsChevron = true,
                        onClick = { onOpen(NaturalSearchKind.EVENT, item.event.id) },
                    )
                }
            }
        }
    }
}

/** id 列を行に出す実体にする。並びは id 列のまま。 */
private suspend fun materialize(module: AppModule, answer: NaturalSearchAnswer): Results = coroutineScope {
    val songs = async { module.songRepository.fetchSongsByIds(answer.songIds) }
    val idols = async { module.idolRepository.fetchIdolsByIds(answer.idolIds) }
    val events = async { module.eventRepository.fetchEventsWithDateByIds(answer.eventIds) }
    Results(
        interpretation = answer.interpretation,
        songs = ordered(songs.await(), answer.songIds) { it.id },
        idols = ordered(idols.await(), answer.idolIds) { it.id },
        events = ordered(events.await(), answer.eventIds) { it.event.id },
        unreadable = answer.unreadable,
    )
}

/** 読み取りの口が返した並びに依らず、id 列の順に並べる。 */
private fun <T> ordered(items: List<T>, ids: List<String>, id: (T) -> String): List<T> {
    val byId = items.associateBy(id)
    return ids.mapNotNull { byId[it] }
}
