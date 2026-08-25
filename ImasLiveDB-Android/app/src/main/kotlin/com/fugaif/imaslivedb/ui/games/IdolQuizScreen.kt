package com.fugaif.imaslivedb.ui.games

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lightbulb
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.hexToColor
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
import uniffi.imas_core.gameProgressBestRatePercent
import uniffi.imas_core.idolQuizAnswer
import uniffi.imas_core.idolQuizHintState
import uniffi.imas_core.idolQuizSession
import uniffi.imas_core.idolQuizSessionResult

// =============================================================================
// アイドル当てクイズ。iOS IdolQuizView の移植。
// シルエット + 曖昧なプロフィール1項目から出題し、開くヒントを選ぶ戦略性を持つ。
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
    val opened: Set<UInt> = emptySet(),
    /** いまの獲得点・公開済み事実・残りヒント。コアが返す。 */
    val hintState: IdolQuizHintState? = null,
    val tally: QuizTally = QuizTally(asked = 0u, correct = 0u, points = 0u),
    val isLastQuestion: Boolean = false,
    val history: List<QuizHistoryItem> = emptyList(),
    val result: QuizSessionResult? = null,
    val isNewBest: Boolean = false,
    val bestRatePercent: Int = 0,
    /** CV 枠を出してよいか (母集団に現任 CV が 1 人でも居るか)。判定は [hasVoiceActorData]。 */
    val showVoiceActorFact: Boolean = true
) {
    val question: Question? get() = questions.getOrNull(index)
}

class IdolQuizViewModel(app: Application, private val selectedBrandIds: Set<String>) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val progressStore = AppModule.from(app).gameProgressStore
    private val snapshots = AppModule.from(app).snapshotStoreProvider

    private val _uiState = MutableStateFlow(IdolQuizUiState())
    val uiState: StateFlow<IdolQuizUiState> = _uiState.asStateFlow()

    /** 出題生成に渡した並び。コアが返す index はこの配列を指す。 */
    private var idols: List<Idol> = emptyList()

    /** [idols] と同じ並びの射影。再挑戦でも作り直さない (CV の再取得を避けるため)。 */
    private var refs: List<IdolQuizIdolRef> = emptyList()

    init {
        viewModelScope.launch {
            idols = idolRepository.fetchIdols()
            // 現任 CV は画面につき 1 回だけ引く (問題ごとに FFI を呼ばない)。
            refs = idolQuizRefs(idols, fetchIdolCastNames(snapshots))
            _uiState.value = withHintState(
                IdolQuizUiState(
                    isLoading = false,
                    questions = makeSession(),
                    showVoiceActorFact = hasVoiceActorData(refs)
                )
            )
        }
    }

    /** 1 ゲーム分 (全 [QUIZ_SESSION_LENGTH] 問) をまとめて生成する。候補不足なら空。 */
    private fun makeSession(): List<Question> = idolQuizSession(
        idols = refs,
        selectedBrandIds = selectedBrandIds.toList(),
        // シードの調達だけがラッパの責務 (抽選そのものはコアの SplitMix64)。
        seed = Random.Default.nextLong().toULong()
    ).map { q ->
        Question(
            answer = idols[q.answer.toInt()],
            choices = q.choices.map { idols[it.toInt()] },
            facts = q.facts
        )
    }

    /** 開示状態を引き直す。ヒント開封・解答・次問のたびに 1 回だけ呼ぶ。 */
    private fun withHintState(state: IdolQuizUiState): IdolQuizUiState {
        val q = state.question ?: return state.copy(hintState = null)
        return state.copy(
            hintState = idolQuizHintState(q.facts, state.opened.toList(), state.selectedId != null)
        )
    }

    fun openHint(factIndex: UInt) {
        val s = _uiState.value
        if (s.selectedId != null) return
        _uiState.value = withHintState(s.copy(opened = s.opened + factIndex))
    }

    fun pick(idol: Idol) {
        val s = _uiState.value
        val q = s.question ?: return
        if (s.selectedId != null) return
        val outcome = idolQuizAnswer(
            facts = q.facts,
            openedFactIndices = s.opened.toList(),
            pickedIdolId = idol.id,
            answerIdolId = q.answer.id,
            before = s.tally
        )
        val history = s.history + QuizHistoryItem(
            id = "${outcome.tally.asked}-${q.answer.id}",
            index = outcome.tally.asked.toInt(),
            subjectTitle = "プロフィール問題",
            subjectSubtitle = q.facts.firstOrNull()?.let { "${it.label}: ${it.value}" },
            answer = q.answer, picked = idol,
            earnedPoints = outcome.earnedPoints.toInt(),
            revealedHints = outcome.revealedHints.toInt()
        )
        _uiState.value = withHintState(
            s.copy(
                selectedId = idol.id,
                tally = outcome.tally,
                isLastQuestion = outcome.isLastQuestion,
                history = history
            )
        )
    }

    fun nextQuestion() {
        val s = _uiState.value
        _uiState.value = withHintState(s.copy(index = s.index + 1, selectedId = null, opened = emptySet()))
    }

    fun finish() {
        val s = _uiState.value
        val result = idolQuizSessionResult(s.tally)
        // 保存 → 保存後の記録から自己ベスト率を読む、の順で組む (更新判定は保存側の担当)。
        val update = progressStore.recordResult(
            GameKind.idolQuiz, score = result.points.toInt(), outOf = result.outOf.toInt()
        )
        _uiState.value = s.copy(
            result = result,
            isNewBest = update.isNewBest,
            // まだ記録が無ければ今回の率で代用する。
            bestRatePercent = gameProgressBestRatePercent(update.record) ?: result.ratePercent.toInt()
        )
    }

    fun restart() {
        // 母集団は変わらないので CV 枠の可否も据え置く (引き直すと FFI が増えるだけ)。
        val showVoiceActorFact = _uiState.value.showVoiceActorFact
        _uiState.value = withHintState(
            IdolQuizUiState(
                isLoading = false,
                questions = makeSession(),
                showVoiceActorFact = showVoiceActorFact
            )
        )
    }

    class Factory(private val app: Application, private val selectedBrandIds: Set<String>) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolQuizViewModel(app, selectedBrandIds) as T
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolQuizScreen(
    selectedBrandIds: Set<String>,
    onBack: () -> Unit,
    viewModel: IdolQuizViewModel = viewModel(
        factory = IdolQuizViewModel.Factory(
            LocalContext.current.applicationContext as Application, selectedBrandIds
        )
    )
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val question = state.question
    val hintState = state.hintState
    val result = state.result

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("アイドル当てクイズ", fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            when {
                state.isLoading -> Box(Modifier.fillMaxWidth().padding(top = 60.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                result != null -> QuizResultView(
                    result = result, kind = GameKind.idolQuiz,
                    isNewBest = state.isNewBest, bestRate = state.bestRatePercent,
                    history = state.history, onReplay = { viewModel.restart() }
                )
                question != null && hintState != null -> {
                    QuizProgressHeader(
                        current = minOf(state.tally.asked.toInt() + if (state.selectedId != null) 0 else 1, QUIZ_SESSION_LENGTH),
                        total = QUIZ_SESSION_LENGTH, points = state.tally.points.toInt()
                    )
                    IdolPromptCard(
                        q = question, hintState = hintState,
                        answered = state.selectedId != null,
                        showVoiceActorFact = state.showVoiceActorFact
                    )
                    if (state.selectedId == null) {
                        IdolHintList(question, hintState, state.showVoiceActorFact, viewModel)
                    }
                    IdolChoiceGrid(choices = question.choices, answer = question.answer, selectedId = state.selectedId) { idol, _ ->
                        viewModel.pick(idol)
                    }
                    if (state.selectedId != null) {
                        QuizNextButton(isLastQuestion = state.isLastQuestion, onNext = { viewModel.nextQuestion() }, onFinish = { viewModel.finish() })
                    }
                }
                else -> ImasEmptyState(icon = Icons.Filled.PersonSearch, title = "出題できる候補が不足しています")
            }
        }
    }
}

/**
 * 伏せた CV 枠か。伏せるときは開けるヒントからも解答後の一覧からも落とす
 * (開けない枠を見せない / 全員を「声優未発表」だと偽らない)。理由は [hasVoiceActorData]。
 */
private fun IdolQuizFact.isHiddenVoiceActor(showVoiceActorFact: Boolean): Boolean =
    !showVoiceActorFact && kind == IdolQuizFactKind.VOICE_ACTOR

@Composable
private fun IdolPromptCard(
    q: Question,
    hintState: IdolQuizHintState,
    answered: Boolean,
    showVoiceActorFact: Boolean
) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            IdolSilhouette(q.answer, revealed = answered)
            Column {
                Text("このプロフィールは誰？", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                if (answered) {
                    Text(q.answer.name, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                } else {
                    IdolValueBadge(hintState.currentValue.toInt())
                }
            }
        }
        Column(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(DS.surface),
        ) {
            // 公開する事実とその順序はコアが決める (無料公開の 1 件 + 開封済み、解答後は全件)。
            val shownFactIndices = hintState.shownFactIndices
                .filterNot { q.facts[it.toInt()].isHiddenVoiceActor(showVoiceActorFact) }
            shownFactIndices.forEachIndexed { pos, idx ->
                if (pos > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(DS.sep).padding(start = 16.dp))
                val f = q.facts[idx.toInt()]
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(f.label, fontSize = 15.sp, color = DS.ink2, modifier = Modifier.weight(1f))
                    // 種別で分岐する (表示ラベルの文字列一致は文言を直した瞬間に壊れる)。
                    if (f.kind == IdolQuizFactKind.MEMBER_COLOR) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Box(Modifier.size(width = 28.dp, height = 18.dp).clip(RoundedCornerShape(5.dp)).background(hexToColor(f.value)))
                            Text(f.value.uppercase(), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = DS.ink)
                        }
                    } else {
                        Text(f.value, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = DS.ink)
                    }
                }
            }
        }
    }
}

@Composable
private fun IdolValueBadge(points: Int) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
        modifier = Modifier.clip(CircleShape).background(DS.success.copy(alpha = 0.14f)).padding(horizontal = 11.dp, vertical = 6.dp)
    ) {
        Text("正解で +${points}pt", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.success)
    }
}

@Composable
private fun IdolSilhouette(idol: Idol, revealed: Boolean) {
    if (revealed) {
        ImasAvatar(label = idol.name, seed = idol.color, brand = idol.brandId, size = 56.dp)
    } else {
        Box(
            modifier = Modifier.size(56.dp).clip(CircleShape).background(DS.fill),
            contentAlignment = Alignment.Center
        ) { Icon(Icons.Filled.Person, null, tint = DS.ink3, modifier = Modifier.size(30.dp)) }
    }
}

@Composable
private fun IdolHintList(
    q: Question,
    hintState: IdolQuizHintState,
    showVoiceActorFact: Boolean,
    viewModel: IdolQuizViewModel
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        // 未開封のヒントと「開いた後の獲得点」はコアが返す。
        val hints = hintState.hints
            .filterNot { q.facts[it.factIndex.toInt()].isHiddenVoiceActor(showVoiceActorFact) }
        hints.forEach { hint ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(DS.surface)
                    .clickable { viewModel.openHint(hint.factIndex) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(DS.warning.copy(alpha = 0.14f)),
                    contentAlignment = Alignment.Center
                ) { Icon(Icons.Filled.Lightbulb, null, tint = DS.warning, modifier = Modifier.size(16.dp)) }
                Column(Modifier.weight(1f)) {
                    Text("ヒント: ${hint.label}を見る", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                    Text("開いた後は正解で +${hint.nextValue}pt", fontSize = 12.sp, color = DS.ink3)
                }
                Icon(Icons.Filled.ExpandMore, null, tint = DS.ink3, modifier = Modifier.size(13.dp))
            }
        }
    }
}
