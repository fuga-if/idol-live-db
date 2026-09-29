package com.fugaif.imaslivedb.ui.games

import android.app.Application
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.animateContentSize
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material3.Text
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.games.QuizStagePlay
import com.fugaif.imaslivedb.data.games.QuizSuspended
import com.fugaif.imaslivedb.data.games.longestStreak
import com.fugaif.imaslivedb.data.games.setlistCaption
import com.fugaif.imaslivedb.data.games.streak
import com.fugaif.imaslivedb.data.games.streakBrokeAt
import com.fugaif.imaslivedb.di.AppModule
import kotlin.random.Random
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.QuizSessionResult
import uniffi.imas_core.QuizTally
import uniffi.imas_core.SetlistQuizHintKind
import uniffi.imas_core.SetlistQuizHintState
import uniffi.imas_core.SetlistQuizLine
import uniffi.imas_core.SetlistQuizQuestion
import uniffi.imas_core.setlistQuizAnswer
import uniffi.imas_core.setlistQuizHintState
import uniffi.imas_core.setlistQuizSessionResult
import uniffi.imas_core.setlistSectionLabel

// =============================================================================
// セトリ当てクイズ。iOS SetlistQuizView の移植。
// 公演のセトリの 1 曲を伏せ、そこに入る曲を 4 択で当てる。最初は伏せた曲の前後 2 曲ずつだけ見せ、
// ヒント (前後をもっと見る / 歌唱メンバー / 2択) を開くほど獲得点が下がる。
// 見た目は QuizStage.kt の「ステージ + チケット」。
//
// 公演の選び方・伏せる曲・誤答の選び方・見せる範囲・採点は imas-core の
// `domain/setlist_quiz.rs` にあり、iOS と同じ実装を共有する。この画面は描画とシード調達だけ。
// =============================================================================

data class SetlistQuizUiState(
    val isLoading: Boolean = true,
    val questions: List<SetlistQuizQuestion> = emptyList(),
    val index: Int = 0,
    /** この問題で開いたヒント (開いた順)。点数はコアがここから算出する。 */
    val opened: List<SetlistQuizHintKind> = emptyList(),
    /** 見せる範囲・次のヒント・いまの獲得点。コアが返す。 */
    val hintState: SetlistQuizHintState? = null,
    val answered: Boolean = false,
    val tally: QuizTally = QuizTally(asked = 0u, correct = 0u, points = 0u),
    val isLastQuestion: Boolean = false,
    /** 各問の記録 (ペンライト・連続正解・見直す)。 */
    val plays: List<QuizStagePlay> = emptyList(),
    /** 直前の問題の判定 (解答後に出す大きなカード)。 */
    val verdict: QuizVerdict? = null,
    val scoreBefore: Int = 0,
    val result: QuizSessionResult? = null,
    val isNewBest: Boolean = false,
    val previousBest: Int? = null
) {
    val question: SetlistQuizQuestion? get() = questions.getOrNull(index)
}

class SetlistQuizViewModel(
    app: Application,
    private val selectedBrandIds: Set<String>,
    /** つづきから。最初の 1 回だけ使う (「もう一度」は新しいセッション)。 */
    private var resume: QuizSuspended? = null
) : AndroidViewModel(app) {
    private val snapshots = AppModule.from(app).snapshotStoreProvider
    private val progressStore = AppModule.from(app).gameProgressStore
    private val resumeStore = AppModule.from(app).quizResumeStore

    private val _uiState = MutableStateFlow(SetlistQuizUiState())
    val uiState: StateFlow<SetlistQuizUiState> = _uiState.asStateFlow()

    /** このセッションの出題シード。 */
    private var seed: ULong = 0u

    init {
        startSession()
    }

    /** 1 ゲーム分の出題をコアに一括生成させる。候補不足・読み込み失敗なら空。 */
    private suspend fun makeSession(seed: ULong): List<SetlistQuizQuestion> {
        val brandIds = selectedBrandIds.toList()
        return runCatching {
            snapshots.query { store -> store.setlistQuizSession(brandIds, seed) }
        }.getOrDefault(emptyList())
    }

    private fun withHintState(state: SetlistQuizUiState): SetlistQuizUiState {
        val q = state.question ?: return state.copy(hintState = null)
        return state.copy(hintState = setlistQuizHintState(q, state.opened, state.answered))
    }

    fun openHint(kind: SetlistQuizHintKind) {
        val s = _uiState.value
        if (s.question == null || s.answered || s.opened.contains(kind)) return
        if (s.hintState?.hints?.none { it.kind == kind } != false) return
        _uiState.value = withHintState(s.copy(opened = s.opened + kind))
    }

    fun pick(songId: String) {
        val s = _uiState.value
        val q = s.question ?: return
        if (s.answered) return
        val outcome = setlistQuizAnswer(q, s.opened, songId, s.tally)
        val picked = if (outcome.isCorrect) null else q.choices.firstOrNull { it.songId == songId }?.title
        val number = s.plays.size + 1
        val slot = q.lines.getOrNull(q.blankIndex.toInt())?.number?.toInt() ?: 0
        _uiState.value = withHintState(
            s.copy(
                answered = true,
                tally = outcome.tally,
                isLastQuestion = outcome.isLastQuestion,
                scoreBefore = s.tally.points.toInt(),
                plays = s.plays + QuizStagePlay(
                    number = number, isCorrect = outcome.isCorrect,
                    answerName = q.answer.title, answerHex = null, pickedName = picked
                ),
                verdict = QuizVerdict(
                    isCorrect = outcome.isCorrect, number = number,
                    answerName = q.answer.title, answerHex = null,
                    earned = outcome.earnedPoints.toInt(), base = s.hintState?.baseValue?.toInt() ?: 0,
                    hints = outcome.revealedHints.toInt(), pickedName = picked,
                    detail = "${q.eventName} ${q.showName} · M${twoDigits(slot)}",
                    artworkUrl = q.answerArtworkUrl?.takeIf { it.isNotEmpty() }
                )
            )
        )
        saveProgress()
    }

    /** 1 問答えるたびに途中経過を残す (× で閉じても「つづきから」で戻れる)。 */
    private fun saveProgress() {
        val s = _uiState.value
        resumeStore.save(
            QuizSuspended(
                kind = GameKind.setlistQuiz, seed = seed, brandIds = selectedBrandIds.toList(),
                nextIndex = s.index + 1, asked = s.tally.asked.toInt(), correct = s.tally.correct.toInt(),
                points = s.tally.points.toInt(), plays = s.plays, total = QUIZ_SESSION_LENGTH
            )
        )
    }

    fun nextQuestion() {
        val s = _uiState.value
        _uiState.value = withHintState(
            s.copy(index = s.index + 1, opened = emptyList(), answered = false, verdict = null)
        )
    }

    fun finish() {
        val s = _uiState.value
        val result = setlistQuizSessionResult(s.tally)
        val previousBest = progressStore.previousBestScore(GameKind.setlistQuiz)
        // 保存と「自己ベスト更新！」の判定は進捗ストア (コアの game_progress) が 1 回で返す。
        val update = progressStore.recordResult(
            GameKind.setlistQuiz, score = result.points.toInt(), outOf = result.outOf.toInt()
        )
        resumeStore.clear(GameKind.setlistQuiz)
        _uiState.value = s.copy(result = result, verdict = null, isNewBest = update.isNewBest, previousBest = previousBest)
    }

    fun restart() = startSession()

    private fun startSession() {
        // つづきからは保存したシードで同じ出題を作り直し、答えた所まで進める。
        val saved = resume
        resume = null
        if (saved != null) {
            seed = saved.seed
        } else {
            // シードの調達だけがラッパの責務 (抽選そのものはコアの SplitMix64)。
            seed = Random.Default.nextLong().toULong()
            resumeStore.clear(GameKind.setlistQuiz)
        }
        viewModelScope.launch {
            val questions = makeSession(seed)
            _uiState.value = withHintState(
                SetlistQuizUiState(
                    isLoading = false, questions = questions,
                    index = saved?.nextIndex ?: 0,
                    tally = saved?.tally ?: QuizTally(asked = 0u, correct = 0u, points = 0u),
                    plays = saved?.plays.orEmpty()
                )
            )
            // 最後の問題まで答えてから閉じていたら、そのまま結果へ。
            if (saved != null && saved.nextIndex >= questions.size && questions.isNotEmpty()) finish()
        }
    }

    class Factory(
        private val app: Application,
        private val selectedBrandIds: Set<String>,
        private val resume: QuizSuspended? = null
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            SetlistQuizViewModel(app, selectedBrandIds, resume) as T
    }
}

@Composable
fun SetlistQuizScreen(
    selectedBrandIds: Set<String>,
    onBack: () -> Unit,
    resume: QuizSuspended? = null,
    viewModel: SetlistQuizViewModel = viewModel(
        factory = SetlistQuizViewModel.Factory(
            LocalContext.current.applicationContext as Application, selectedBrandIds, resume
        )
    )
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val question = state.question
    val hintState = state.hintState
    val result = state.result
    val verdict = state.verdict
    val header = when {
        result != null -> QuizStageHeader.Result(result.questions.toInt())
        state.isLoading || question == null -> QuizStageHeader.None
        else -> QuizStageHeader.Question(
            current = minOf(state.plays.size + if (verdict == null) 1 else 0, QUIZ_SESSION_LENGTH),
            total = QUIZ_SESSION_LENGTH, points = state.tally.points.toInt()
        )
    }

    QuizStageScaffold(
        title = "セトリ当て",
        header = header,
        onClose = onBack,
        scrollKey = state.plays.size to (verdict == null),
        trailing = {
            if (result != null) {
                // 背景には答えの曲のジャケットを敷く。
                QuizStageShareButton(
                    cardTitle = "セトリ当て", shareName = "セトリ当てクイズ", result = result,
                    plays = state.plays, isNewBest = state.isNewBest, fileNamePrefix = "setlist_quiz",
                    artworkUrls = state.questions.take(state.plays.size).mapNotNull { it.answerArtworkUrl }
                )
            }
        }
    ) {
        when {
            state.isLoading -> QuizStageLoading()
            result != null -> QuizStageResultView(
                result = result, isNewBest = state.isNewBest, previousBest = state.previousBest,
                slots = state.plays.penlights(total = result.questions.toInt(), answering = false),
                longestStreak = state.plays.longestStreak, misses = state.plays.misses,
                onReplay = { viewModel.restart() }, onClose = onBack
            )
            question != null && hintState != null -> {
                QuizStageProgress(
                    slots = state.plays.penlights(total = QUIZ_SESSION_LENGTH, answering = verdict == null),
                    caption = state.plays.setlistCaption(QUIZ_SESSION_LENGTH),
                    streak = state.plays.streak, streakBrokeAt = state.plays.streakBrokeAt
                )
                if (verdict != null) {
                    QuizVerdictCard(verdict)
                    QuizVerdictStats(before = state.scoreBefore, after = state.tally.points.toInt(), streak = state.plays.streak)
                    if (!verdict.isCorrect) QuizVerdictFootnote()
                    QuizStageNextButton(
                        isLastQuestion = state.isLastQuestion,
                        onNext = { viewModel.nextQuestion() }, onFinish = { viewModel.finish() }
                    )
                } else {
                    SetlistTicket(question, hintState, state.opened) { viewModel.openHint(it) }
                    val eliminated = hintState.eliminated.mapNotNull { question.choices.getOrNull(it.toInt())?.songId }.toSet()
                    QuizStageChoiceGrid(
                        choices = question.choices.map { QuizStageChoice(it.songId, it.title) },
                        columns = 1, eliminated = eliminated
                    ) { viewModel.pick(it.id) }
                }
            }
            else -> QuizStageEmpty(Icons.Filled.FormatListNumbered, "出題できる公演がありません")
        }
    }
}

// MARK: - チケット

@Composable
private fun SetlistTicket(
    q: SetlistQuizQuestion,
    hint: SetlistQuizHintState,
    opened: List<SetlistQuizHintKind>,
    onOpen: (SetlistQuizHintKind) -> Unit
) {
    QuizTicket {
        QuizTicketTitleBlock(
            label = "SETLIST", question = "空欄に入る曲は？",
            value = hint.currentValue.toInt(), base = hint.baseValue.toInt()
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                QSFitText(q.eventName, QS.text(20, FontWeight.Black), QS.paperInk, maxLines = 2, minScale = 0.7f)
                Text(
                    listOfNotNull(q.showName, q.date.replace("-", "."), q.venue).filter { it.isNotEmpty() }.joinToString(" · "),
                    style = QS.text(12, FontWeight.Bold), color = QS.paperSub, maxLines = 2, overflow = TextOverflow.Ellipsis
                )
            }
        }
        SetlistLines(q, hint)
        AnimatedVisibility(
            visible = hint.showPerformers && q.performers.isNotEmpty(),
            enter = fadeIn() + expandVertically()
        ) { SetlistPerformers(q) }
        val offered = hint.hints.map { it.kind }.toSet()
        // タイルの並び (開いたものも同じ位置に残す)。
        val kinds = listOf(SetlistQuizHintKind.WIDER, SetlistQuizHintKind.PERFORMERS, SetlistQuizHintKind.FIFTY_FIFTY)
            .filter { it in opened || it in offered }
        if (kinds.isNotEmpty()) {
            QuizTicketNotch()
            QuizTicketHintTiles(
                tiles = kinds.map { kind ->
                    val option = hint.hints.firstOrNull { it.kind == kind }
                    QuizHintTileSpec(
                        key = kind.name, title = kind.title(),
                        phase = if (option != null) QuizHintPhase.Available(option.cost.toInt()) { onOpen(kind) }
                        else QuizHintPhase.Open(kind.openedValue(q))
                    )
                }
            )
        }
    }
}

/** 見せる範囲のセトリ。隠れている分は「⋮ 前に N 曲」と畳む。 */
@Composable
private fun SetlistLines(q: SetlistQuizQuestion, hint: SetlistQuizHintState) {
    val from = hint.visibleFrom.toInt()
    val to = hint.visibleTo.toInt()
    val visible = if (from in q.lines.indices && to in q.lines.indices && from <= to) q.lines.subList(from, to + 1) else emptyList()
    Column(Modifier.fillMaxWidth().animateContentSize().padding(start = 18.dp, end = 18.dp, bottom = 12.dp)) {
        if (hint.hiddenBefore > 0u) HiddenRow("前に ${hint.hiddenBefore} 曲")
        visible.forEachIndexed { offset, line ->
            val i = offset + from
            val label = setlistSectionLabel(line.section)
            val previous = if (i > 0) setlistSectionLabel(q.lines[i - 1].section) else null
            if (label != null && (i == 0 || previous != label)) {
                Text(
                    label, style = QS.mono(11, 1.2f), color = QS.paperSub,
                    modifier = Modifier.padding(top = 8.dp, bottom = 2.dp)
                )
            }
            LineRow(line, reveal = hint.revealAnswer)
        }
        if (hint.hiddenAfter > 0u) HiddenRow("後に ${hint.hiddenAfter} 曲")
    }
}

@Composable
private fun HiddenRow(text: String) {
    Row(
        modifier = Modifier.heightIn(min = 30.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text("⋮", style = QS.text(16, FontWeight.Black), color = QS.paperMuted, modifier = Modifier.width(34.dp))
        Text(text, style = QS.text(12, FontWeight.Bold), color = QS.paperMuted)
    }
}

@Composable
private fun LineRow(line: SetlistQuizLine, reveal: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 34.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Text(
            "M${twoDigits(line.number.toInt())}", style = QS.mono(12),
            color = if (line.isBlank) QS.stamp else QS.paperSub, modifier = Modifier.width(34.dp)
        )
        if (line.isBlank) {
            Box(
                modifier = Modifier
                    .weight(1f)
                    .padding(vertical = 2.dp)
                    .dashedBorder(QS.stamp, 2.dp, 10.dp, dashed = !reveal)
                    .padding(horizontal = 12.dp, vertical = 6.dp)
                    .semantics { contentDescription = if (reveal) line.songTitle else "空欄" }
            ) {
                QSFitText(
                    if (reveal) line.songTitle else "？？？", QS.text(16, FontWeight.Black),
                    if (reveal) QS.paperInk else QS.stamp, minScale = 0.7f
                )
            }
        } else {
            QSFitText(line.songTitle, QS.text(15, FontWeight.Bold), QS.paperInk, minScale = 0.7f, modifier = Modifier.weight(1f))
        }
    }
}

@Composable
private fun SetlistPerformers(q: SetlistQuizQuestion) {
    Column(
        verticalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier
            .padding(start = 18.dp, end = 18.dp, bottom = 12.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(14.dp))
            .background(QS.paperTile)
            .padding(12.dp)
    ) {
        Text("歌唱メンバー", style = QS.text(11, FontWeight.Bold), color = QS.paperSub)
        Text(q.performers.joinToString("、") { it.name }, style = QS.text(14, FontWeight.Bold), color = QS.paperInk)
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            q.performers.take(16).forEachIndexed { i, p ->
                Box(Modifier.size(width = 8.dp, height = 20.dp).clip(RoundedCornerShape(4.dp)).background(qsColor(p.color, QS.penlight(i))))
            }
        }
    }
}

// MARK: - ヒント

private fun SetlistQuizHintKind.title(): String = when (this) {
    SetlistQuizHintKind.WIDER -> "前後をもっと見る"
    SetlistQuizHintKind.PERFORMERS -> "歌唱メンバー"
    SetlistQuizHintKind.FIFTY_FIFTY -> "2択にする"
}

private fun SetlistQuizHintKind.openedValue(q: SetlistQuizQuestion): String = when (this) {
    SetlistQuizHintKind.WIDER -> "全${q.lines.size}曲"
    SetlistQuizHintKind.PERFORMERS -> "${q.performers.size}人"
    SetlistQuizHintKind.FIFTY_FIFTY -> "2曲に"
}
