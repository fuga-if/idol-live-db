package com.fugaif.imaslivedb.ui.games

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
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
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import kotlin.random.Random
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.IdolQuizFact
import uniffi.imas_core.IdolQuizFactKind
import uniffi.imas_core.IdolQuizHintState
import uniffi.imas_core.IdolQuizIdolRef
import uniffi.imas_core.QuizSessionResult
import uniffi.imas_core.QuizTally
import uniffi.imas_core.idolQuizAnswer
import uniffi.imas_core.idolQuizHintState
import uniffi.imas_core.idolQuizSession
import uniffi.imas_core.idolQuizSessionResult

// =============================================================================
// アイドル当てクイズ。iOS IdolQuizView の移植。
// 曖昧なプロフィールから出題し、並んだヒントのどれから開けるかをユーザが選ぶ (戦略性)。
// ヒントを 1 つ開くごとに獲得点が下がる。見た目は QuizStage.kt の「ステージ + チケット」。
//
// 出題の生成規則・事実の並び・採点 (素点とヒントの開封コスト)・グレード判定は
// imas-core の `domain::quiz_generation` にあり、iOS と同じ実装を共有する。
// ここに残すのは Compose の描画と「乱数シードの調達」「現任 CV の調達」
// 「index → Idol の解決」だけ。
// 1 セッション分の出題は開始操作 1 回でまとめて生成する (問題ごとに FFI を呼ばない)。
// =============================================================================

/** コアが返した 1 問を、画面が描ける形 (Idol 実体) に解決したもの。 */
data class Question(val answer: Idol, val choices: List<Idol>, val facts: List<IdolQuizFact>)

data class IdolQuizUiState(
    val isLoading: Boolean = true,
    val questions: List<Question> = emptyList(),
    val index: Int = 0,
    val selectedId: String? = null,
    /** 開いたヒントの facts インデックス (開いた順)。 */
    val opened: List<UInt> = emptyList(),
    /** いまの獲得点・公開済み事実・残りヒント。コアが返す。 */
    val hintState: IdolQuizHintState? = null,
    /** ヒントを開く前の獲得点 (出題ごとに記録。メーターの「100」側)。 */
    val baseValue: Int = 0,
    val tally: QuizTally = QuizTally(asked = 0u, correct = 0u, points = 0u),
    val isLastQuestion: Boolean = false,
    /** 各問の記録 (ペンライト・連続正解・見直す)。 */
    val plays: List<QuizStagePlay> = emptyList(),
    /** 直前の問題の判定 (解答後に出す大きなカード)。 */
    val verdict: QuizVerdict? = null,
    val scoreBefore: Int = 0,
    val result: QuizSessionResult? = null,
    val isNewBest: Boolean = false,
    val previousBest: Int? = null,
    /** CV 枠を出してよいか (母集団に現任 CV が 1 人でも居るか)。判定は [hasVoiceActorData]。 */
    val showVoiceActorFact: Boolean = true
) {
    val question: Question? get() = questions.getOrNull(index)
}

class IdolQuizViewModel(
    app: Application,
    private val selectedBrandIds: Set<String>,
    /** つづきから。最初の 1 回だけ使う (「もう一度」は新しいセッション)。 */
    private var resume: QuizSuspended? = null
) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val progressStore = AppModule.from(app).gameProgressStore
    private val resumeStore = AppModule.from(app).quizResumeStore
    private val snapshots = AppModule.from(app).snapshotStoreProvider

    private val _uiState = MutableStateFlow(IdolQuizUiState())
    val uiState: StateFlow<IdolQuizUiState> = _uiState.asStateFlow()

    /** 出題生成に渡した並び。コアが返す index はこの配列を指す。 */
    private var idols: List<Idol> = emptyList()

    /** [idols] と同じ並びの射影。再挑戦でも作り直さない (CV の再取得を避けるため)。 */
    private var refs: List<IdolQuizIdolRef> = emptyList()

    /** このセッションの出題シード。 */
    private var seed: ULong = 0u

    init {
        viewModelScope.launch {
            idols = idolRepository.fetchIdols()
            // 現任 CV は画面につき 1 回だけ引く (問題ごとに FFI を呼ばない)。
            refs = idolQuizRefs(idols, fetchIdolCastNames(snapshots))
            startSession(showVoiceActorFact = hasVoiceActorData(refs))
        }
    }

    /** 1 ゲーム分 (全 [QUIZ_SESSION_LENGTH] 問) をまとめて生成する。候補不足なら空。 */
    private fun makeSession(seed: ULong): List<Question> = idolQuizSession(
        idols = refs,
        selectedBrandIds = selectedBrandIds.toList(),
        seed = seed
    ).map { q ->
        Question(
            answer = idols[q.answer.toInt()],
            choices = q.choices.map { idols[it.toInt()] },
            facts = q.facts
        )
    }

    private fun startSession(showVoiceActorFact: Boolean) {
        // つづきからは保存したシードで同じ出題を作り直し、答えた所まで進める。
        val saved = resume
        resume = null
        if (saved != null) {
            seed = saved.seed
        } else {
            // シードの調達だけがラッパの責務 (抽選そのものはコアの SplitMix64)。
            seed = Random.Default.nextLong().toULong()
            resumeStore.clear(GameKind.idolQuiz)
        }
        val questions = makeSession(seed)
        val state = withHintState(
            IdolQuizUiState(
                isLoading = false, questions = questions, showVoiceActorFact = showVoiceActorFact,
                index = saved?.nextIndex ?: 0,
                tally = saved?.tally ?: QuizTally(asked = 0u, correct = 0u, points = 0u),
                plays = saved?.plays.orEmpty()
            )
        )
        _uiState.value = state.copy(baseValue = state.hintState?.currentValue?.toInt() ?: 0)
        // 最後の問題まで答えてから閉じていたら、そのまま結果へ。
        if (saved != null && state.index >= questions.size && questions.isNotEmpty()) finish()
    }

    /** 1 問答えるたびに途中経過を残す (× で閉じても「つづきから」で戻れる)。 */
    private fun saveProgress() {
        val s = _uiState.value
        resumeStore.save(
            QuizSuspended(
                kind = GameKind.idolQuiz, seed = seed, brandIds = selectedBrandIds.toList(),
                nextIndex = s.index + 1, asked = s.tally.asked.toInt(), correct = s.tally.correct.toInt(),
                points = s.tally.points.toInt(), plays = s.plays, total = QUIZ_SESSION_LENGTH
            )
        )
    }

    /** 開示状態を引き直す。ヒント開封・解答・次問のたびに 1 回だけ呼ぶ。 */
    private fun withHintState(state: IdolQuizUiState): IdolQuizUiState {
        val q = state.question ?: return state.copy(hintState = null)
        return state.copy(hintState = idolQuizHintState(q.facts, state.opened, state.selectedId != null))
    }

    fun openHint(factIndex: UInt) {
        val s = _uiState.value
        if (s.selectedId != null || factIndex in s.opened) return
        _uiState.value = withHintState(s.copy(opened = s.opened + factIndex))
    }

    fun pick(idolId: String) {
        val s = _uiState.value
        val q = s.question ?: return
        if (s.selectedId != null) return
        val idol = q.choices.firstOrNull { it.id == idolId } ?: return
        // 正誤判定・獲得点・積み上げはコアがまとめて返す (加点式なので不正解でも減点しない)。
        val outcome = idolQuizAnswer(
            facts = q.facts,
            openedFactIndices = s.opened,
            pickedIdolId = idol.id,
            answerIdolId = q.answer.id,
            before = s.tally
        )
        val answered = withHintState(s.copy(selectedId = idol.id))
        val number = s.plays.size + 1
        // 解答後は全部の事実が公開されるので、正解の補足としてプロフィールを 1 行で添える。
        val summary = answered.hintState?.shownFactIndices.orEmpty()
            .map { q.facts[it.toInt()] }
            .filter { it.kind != IdolQuizFactKind.MEMBER_COLOR && !it.isHiddenVoiceActor(s.showVoiceActorFact) }
            .take(4).joinToString(" · ") { it.value }
        val picked = if (outcome.isCorrect) null else idol.name
        _uiState.value = answered.copy(
            tally = outcome.tally,
            isLastQuestion = outcome.isLastQuestion,
            scoreBefore = s.tally.points.toInt(),
            plays = s.plays + QuizStagePlay(
                number = number, isCorrect = outcome.isCorrect,
                answerName = q.answer.name, answerHex = q.answer.color, pickedName = picked
            ),
            verdict = QuizVerdict(
                isCorrect = outcome.isCorrect, number = number,
                answerName = q.answer.name, answerHex = q.answer.color,
                earned = outcome.earnedPoints.toInt(), base = s.baseValue,
                hints = outcome.revealedHints.toInt(), pickedName = picked, detail = summary
            )
        )
        saveProgress()
    }

    fun nextQuestion() {
        val s = _uiState.value
        val next = withHintState(s.copy(index = s.index + 1, selectedId = null, opened = emptyList(), verdict = null))
        _uiState.value = next.copy(baseValue = next.hintState?.currentValue?.toInt() ?: 0)
    }

    fun finish() {
        val s = _uiState.value
        val result = idolQuizSessionResult(s.tally)
        val previousBest = progressStore.previousBestScore(GameKind.idolQuiz)
        // 保存と「自己ベスト更新！」の判定は進捗ストア (コアの game_progress) が 1 回で返す。
        val update = progressStore.recordResult(
            GameKind.idolQuiz, score = result.points.toInt(), outOf = result.outOf.toInt()
        )
        resumeStore.clear(GameKind.idolQuiz)
        _uiState.value = s.copy(result = result, verdict = null, isNewBest = update.isNewBest, previousBest = previousBest)
    }

    fun restart() {
        // 母集団は変わらないので CV 枠の可否も据え置く (引き直すと FFI が増えるだけ)。
        startSession(_uiState.value.showVoiceActorFact)
    }

    class Factory(
        private val app: Application,
        private val selectedBrandIds: Set<String>,
        private val resume: QuizSuspended? = null
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolQuizViewModel(app, selectedBrandIds, resume) as T
    }
}

@Composable
fun IdolQuizScreen(
    selectedBrandIds: Set<String>,
    onBack: () -> Unit,
    resume: QuizSuspended? = null,
    viewModel: IdolQuizViewModel = viewModel(
        factory = IdolQuizViewModel.Factory(
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
        title = "アイドル当て",
        header = header,
        onClose = onBack,
        scrollKey = state.plays.size to (verdict == null),
        trailing = {
            if (result != null) {
                QuizStageShareButton(
                    cardTitle = "アイドル当て", shareName = "アイドル当てクイズ", result = result,
                    plays = state.plays, isNewBest = state.isNewBest, fileNamePrefix = "idol_quiz"
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
                    val value = hintState.currentValue.toInt()
                    QuizValueMeter(
                        value = value, base = state.baseValue,
                        note = if (state.opened.isEmpty()) "ヒントを開くと減ります"
                        else "ヒント ${state.opened.size} 枚で −${state.baseValue - value}"
                    )
                    IdolTicket(question, hintState, state.opened, state.showVoiceActorFact) { viewModel.openHint(it) }
                    QuizStageChoiceGrid(choices = question.choices.map { QuizStageChoice(it.id, it.name) }) {
                        viewModel.pick(it.id)
                    }
                }
            }
            else -> QuizStageEmpty(Icons.Filled.PersonSearch, "出題できる候補が不足しています")
        }
    }
}

/**
 * 伏せた CV 枠か。伏せるときは開けるヒントからも解答後の一覧からも落とす
 * (開けない枠を見せない / 全員を「声優未発表」だと偽らない)。理由は [hasVoiceActorData]。
 */
private fun IdolQuizFact.isHiddenVoiceActor(showVoiceActorFact: Boolean): Boolean =
    !showVoiceActorFact && kind == IdolQuizFactKind.VOICE_ACTOR

/** チケット: 最初から見えている事実のタイル + 切り取り線 + ヒントの行。 */
@Composable
private fun IdolTicket(
    q: Question,
    hint: IdolQuizHintState,
    opened: List<UInt>,
    showVoiceActorFact: Boolean,
    onOpen: (UInt) -> Unit
) {
    // 最初から見えている事実 = 公開済みのうち、ヒントで開いたもの以外。
    val free = hint.shownFactIndices
        .filter { it !in opened && !q.facts[it.toInt()].isHiddenVoiceActor(showVoiceActorFact) }
    // 未開封のヒントと「開いた後の獲得点」はコアが返す。
    val hints = hint.hints.filterNot { q.facts[it.factIndex.toInt()].isHiddenVoiceActor(showVoiceActorFact) }
    val hintTotal = opened.size + hints.size
    QuizTicket {
        QuizTicketHeading(label = "PROFILE", question = "このアイドルはだれ？")
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, bottom = 12.dp)
        ) {
            free.chunked(2).forEach { row ->
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min)
                ) {
                    row.forEach { idx ->
                        val f = q.facts[idx.toInt()]
                        QuizTicketFactTile(f.label, f.value, Modifier.weight(1f).fillMaxHeight())
                    }
                    if (row.size < 2) Spacer(Modifier.weight(1f))
                }
            }
        }
        if (hintTotal > 0) {
            QuizTicketNotch()
            QuizTicketHintHeader(opened = opened.size, total = hintTotal)
            // 開いた順 → 未開封 の順に並べる。CV 枠はコアが常設しているので、
            // ラベルの有無で声優未発表キャラがバレることはない。
            opened.forEachIndexed { pos, idx ->
                val f = q.facts[idx.toInt()]
                QuizTicketHintRow(
                    number = pos + 1, label = f.label, cost = f.cost.toInt(), isOpen = true,
                    isNew = pos == opened.size - 1, isFirst = pos == 0, onOpen = {}
                ) {
                    // 色そのものが答えになる項目だけ色チップで見せる (文言ではなく種別で分岐)。
                    if (f.kind == IdolQuizFactKind.MEMBER_COLOR) QuizTicketColorValue(f.value) else QuizTicketHintValue(f.value)
                }
            }
            hints.forEachIndexed { pos, option ->
                QuizTicketHintRow(
                    number = opened.size + pos + 1, label = option.label,
                    cost = hint.currentValue.toInt() - option.nextValue.toInt(),
                    isOpen = false, isFirst = opened.isEmpty() && pos == 0,
                    onOpen = { onOpen(option.factIndex) }
                ) {}
            }
            Spacer(Modifier.height(6.dp))
        }
    }
}
