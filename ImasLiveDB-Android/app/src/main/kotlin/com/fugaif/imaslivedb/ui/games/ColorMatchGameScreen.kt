package com.fugaif.imaslivedb.ui.games

import android.app.Application
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.games.QuizStagePlay
import com.fugaif.imaslivedb.data.games.QuizSuspended
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.ViewModelProvider
import com.fugaif.imaslivedb.data.games.longestStreak
import com.fugaif.imaslivedb.data.games.setlistCaption
import com.fugaif.imaslivedb.data.games.streak
import com.fugaif.imaslivedb.data.games.streakBrokeAt
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import kotlin.random.Random
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.ColorMatchAssignment
import uniffi.imas_core.ColorMatchBrandRef
import uniffi.imas_core.ColorMatchDifficulty
import uniffi.imas_core.ColorMatchIdol
import uniffi.imas_core.ColorMatchIdolSource
import uniffi.imas_core.ColorMatchJudgement
import uniffi.imas_core.ColorMatchPools
import uniffi.imas_core.ColorMatchRound
import uniffi.imas_core.ColorQuizHintKind
import uniffi.imas_core.ColorQuizHintState
import uniffi.imas_core.ColorQuizQuestion
import uniffi.imas_core.QuizSessionResult
import uniffi.imas_core.QuizTally
import uniffi.imas_core.colorMatchBuildPools
import uniffi.imas_core.colorMatchEffectivePool
import uniffi.imas_core.colorMatchJudgeRound
import uniffi.imas_core.colorMatchStartGame
import uniffi.imas_core.colorQuizAnswer
import uniffi.imas_core.colorQuizHintState
import uniffi.imas_core.colorQuizSessionResult
import uniffi.imas_core.colorQuizStartGame
import uniffi.imas_core.quizAccuracyResult

// =============================================================================
// メンバーカラー合わせ。iOS ColorMatchGameView の移植。
// 遊び方は 2 つ: 4択 (名前 → イメージカラーを 4 色から選ぶ・ヒント式採点) と 並べる。
// 設定画面はアプリ本体の見た目のまま、遊び始めたら QuizStage.kt の「ステージ + チケット」に切り替える。
// 並べるはドラッグ&ドロップの代わりに「色チップをタップで選択 → メンバー行をタップで割当」方式のみ提供
// (iOS 側もタップ割当を併存させているため、機能的な等価性は保たれる)。
//
// 母集団の決定 (外部ゲスト・対象外ブランド・色の重複の除外)、難易度ごとの出題、
// 色の一致判定・正答率・グレードは imas-core の `domain::color_match` / `color_quiz` が持つ。
// ここに残すのは Compose の描画とシードの調達、id → Idol の解決だけ。
// =============================================================================

private val PLAY_MODE_LABELS = listOf("4択", "並べる")
private val LEVEL_LABELS = listOf("やさしい", "ふつう", "むずい")
private val QUESTION_COUNT_OPTIONS = listOf(5, 10)

/**
 * 「はじめる」を許す最小の母集団人数。コア `domain::color_match::MIN_POOL_SIZE` と同値だが、
 * 定数 1 個のために FFI 面を増やさないのでここに写している (増減はコアに追従させる)。
 */
private const val MIN_POOL_SIZE = 2

/** 4択は 4 色並べるので 4 人要る。 */
private const val MIN_CHOICE_POOL_SIZE = 4

/** UI の難易度セグメント (0/1/2) → コアの難易度。並び順で対応する。 */
private fun difficultyOf(segment: Int): ColorMatchDifficulty =
    ColorMatchDifficulty.entries.getOrElse(segment) { ColorMatchDifficulty.NORMAL }

data class ColorMatchUiState(
    val isLoading: Boolean = true,
    /** 出題ブランドとして選べるブランド (コアの selectable_brand_ids 順)。 */
    val brands: List<Brand> = emptyList(),
    /** 出題可能ブランド (4 人以上) の短縮名。ブランド跨ぎの行に添える。 */
    val brandShortNames: Map<String, String> = emptyMap(),
    /** 出題メンバー (id と色だけ) から名前などを引くための索引。 */
    val idolsById: Map<String, Idol> = emptyMap(),
    val selectedBrandIds: Set<String> = emptySet(),
    /** 現在の出題母集団の人数 (「はじめる」の可否判定に使う)。 */
    val poolSize: Int = 0,
    /** 遊び方: 0=4択 / 1=並べる。 */
    val playMode: Int = 0,
    val difficulty: Int = 1,
    val questionCount: Int = 5,
    val inGame: Boolean = false,
    val sessionDone: Boolean = false,
    val roundIndex: Int = 0,
    val totalCorrect: Int = 0,
    val totalAnswered: Int = 0,
    /** 1 ゲーム分の出題。開始操作 1 回でまとめて生成する。 */
    val rounds: List<ColorMatchRound> = emptyList(),
    val assignments: Map<String, String> = emptyMap(),
    val selectedHex: String? = null,
    /** 答え合わせ結果 (未判定は null)。行の正誤も正解色の表示文字列もここに入っている。 */
    val judgement: ColorMatchJudgement? = null,
    /** 各問の記録 (4択は正解、並べるは全員当てたらペンライト点灯)。 */
    val plays: List<QuizStagePlay> = emptyList(),
    // --- 4択 ---
    /** 1 ゲーム分の 4 択 (「はじめる」1 回でコアがまとめて生成)。 */
    val choiceQuestions: List<ColorQuizQuestion> = emptyList(),
    /** この問題で開いたヒント。 */
    val choiceOpened: List<ColorQuizHintKind> = emptyList(),
    /** いまの獲得点・色の系統・2択で消した色・まだ開けるヒント (コアが算出)。 */
    val choiceHint: ColorQuizHintState? = null,
    val choiceTally: QuizTally = QuizTally(asked = 0u, correct = 0u, points = 0u),
    /** 直前の問題の判定 (解答後に出す大きなカード)。null = 未解答。 */
    val choiceVerdict: QuizVerdict? = null,
    val choiceScoreBefore: Int = 0,
    /** セッション結果 (点・グレードはコア)。 */
    val sessionResult: QuizSessionResult? = null,
    val isNewBest: Boolean = false,
    val previousBest: Int? = null
) {
    val isChoiceMode: Boolean get() = playMode == 0
    val choiceQuestion: ColorQuizQuestion? get() = choiceQuestions.getOrNull(roundIndex)
    val round: ColorMatchRound? get() = rounds.getOrNull(roundIndex)
    val members: List<ColorMatchIdol> get() = round?.members ?: emptyList()
    val palette: List<String> get() = round?.palette ?: emptyList()
    val judged: Boolean get() = judgement != null
    val requiredPool: Int get() = if (isChoiceMode) MIN_CHOICE_POOL_SIZE else MIN_POOL_SIZE
    val canStart: Boolean get() = poolSize >= requiredPool
    /** ブランドが複数混ざるときだけ行にブランド名を添える (誰の色か絞りにくくなるため)。 */
    val isCrossBrand: Boolean get() = selectedBrandIds.size != 1
    val isLastRound: Boolean get() = roundIndex + 1 >= questionCount
}

class ColorMatchViewModel(
    app: Application,
    /** つづきから。最初の 1 回だけ使う (「もう一度」は新しいセッション)。 */
    private var resume: QuizSuspended? = null
) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val stats = AppModule.from(app).statsRepository
    private val progressStore = AppModule.from(app).gameProgressStore
    private val resumeStore = AppModule.from(app).quizResumeStore

    private val _uiState = MutableStateFlow(ColorMatchUiState())
    val uiState: StateFlow<ColorMatchUiState> = _uiState.asStateFlow()

    /** 画面ロード時に 1 回だけ組む母集団一式 (ブランド切替のたびに引き直す元)。 */
    private var pools: ColorMatchPools? = null
    private var pool: List<ColorMatchIdol> = emptyList()

    /** このセッションの出題シード。 */
    private var seed: ULong = 0u

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val all = idolRepository.fetchIdols()
            val allBrands = stats.fetchBrands()
            val built = colorMatchBuildPools(
                idols = all.map {
                    ColorMatchIdolSource(
                        id = it.id, brandId = it.brandId, color = it.color,
                        isExternal = it.isExternal, sortOrder = it.sortOrder
                    )
                },
                brands = allBrands.map { ColorMatchBrandRef(id = it.id, sortOrder = it.sortOrder) }
            )
            pools = built
            val brandById = allBrands.associateBy { it.id }
            _uiState.value = _uiState.value.copy(
                isLoading = false,
                brands = built.selectableBrandIds.mapNotNull { brandById[it] },
                // 短縮名を引けるのは「出題可能ブランド」だけ (原本と同じ範囲)。
                brandShortNames = built.brandPools.mapNotNull { p ->
                    brandById[p.brandId]?.let { p.brandId to it.shortName }
                }.toMap(),
                idolsById = all.associateBy { it.id }
            )
            refreshPool()
            // つづきからは読み込みが済んだらすぐ続きの問題へ。
            if (resume != null) startSession()
        }
    }

    /** 出題母集団を引き直す。ブランド選択が変わったときだけ呼ぶ (描画ごとに呼ばない)。 */
    private fun refreshPool() {
        val built = pools ?: return
        pool = colorMatchEffectivePool(built, _uiState.value.selectedBrandIds.toList())
        _uiState.value = _uiState.value.copy(poolSize = pool.size)
    }

    fun toggleBrand(id: String) {
        val current = _uiState.value.selectedBrandIds
        _uiState.value = _uiState.value.copy(
            selectedBrandIds = if (current.contains(id)) current - id else current + id
        )
        refreshPool()
    }

    fun clearBrands() {
        _uiState.value = _uiState.value.copy(selectedBrandIds = emptySet())
        refreshPool()
    }

    fun setPlayMode(m: Int) { _uiState.value = _uiState.value.copy(playMode = m) }
    fun setDifficulty(d: Int) { _uiState.value = _uiState.value.copy(difficulty = d) }
    fun setQuestionCount(n: Int) { _uiState.value = _uiState.value.copy(questionCount = n) }

    fun startSession() {
        // つづきからは保存した設定とシードで同じ出題を作り直し、答えた問題の次から始める。
        val saved = resume
        resume = null
        if (saved != null) {
            _uiState.value = _uiState.value.copy(
                playMode = if (saved.colorMode == "choice") 0 else 1,
                difficulty = saved.difficulty ?: _uiState.value.difficulty,
                questionCount = saved.total,
                selectedBrandIds = saved.brandIds.toSet()
            )
            refreshPool()
            seed = saved.seed
        } else {
            // 全問まとめて生成する (問題ごとに FFI を呼ばない)。シードの調達だけがここの責務。
            seed = Random.Default.nextLong().toULong()
            resumeStore.clear(GameKind.colorMatch)
        }
        val s = _uiState.value
        if (pool.size < s.requiredPool) return
        val reset = s.copy(
            roundIndex = saved?.nextIndex ?: 0,
            totalCorrect = if (saved != null && !s.isChoiceMode) saved.correct else 0,
            totalAnswered = if (saved != null && !s.isChoiceMode) saved.asked else 0,
            sessionDone = false, inGame = true,
            assignments = emptyMap(), selectedHex = null, judgement = null,
            choiceOpened = emptyList(), choiceVerdict = null,
            choiceTally = if (saved != null && s.isChoiceMode) saved.tally else QuizTally(asked = 0u, correct = 0u, points = 0u),
            plays = saved?.plays.orEmpty(), sessionResult = null, isNewBest = false, previousBest = null
        )
        _uiState.value = if (s.isChoiceMode) {
            val questions = colorQuizStartGame(
                pool = pool,
                difficulty = difficultyOf(s.difficulty),
                questionCount = s.questionCount.toUInt(),
                seed = seed
            )
            withChoiceHint(reset.copy(choiceQuestions = questions, rounds = emptyList()))
        } else {
            val rounds = colorMatchStartGame(
                pool = pool,
                difficulty = difficultyOf(s.difficulty),
                questionCount = s.questionCount.toUInt(),
                seed = seed
            )
            reset.copy(rounds = rounds, choiceQuestions = emptyList(), choiceHint = null)
        }
        // 最後の問題まで答えてから閉じていたら、そのまま結果へ。
        if (saved != null && saved.nextIndex >= s.questionCount) finishSession()
    }

    /** 1 問答えるたびに途中経過を残す (× で閉じても「つづきから」で戻れる)。 */
    private fun saveProgress() {
        val s = _uiState.value
        resumeStore.save(
            QuizSuspended(
                kind = GameKind.colorMatch, seed = seed, brandIds = s.selectedBrandIds.toList(),
                nextIndex = s.roundIndex + 1,
                // 並べるは当てた人数 / 答えた人数を積み上げとして持つ。
                asked = if (s.isChoiceMode) s.choiceTally.asked.toInt() else s.totalAnswered,
                correct = if (s.isChoiceMode) s.choiceTally.correct.toInt() else s.totalCorrect,
                points = if (s.isChoiceMode) s.choiceTally.points.toInt() else s.totalCorrect,
                plays = s.plays, total = s.questionCount,
                difficulty = s.difficulty, colorMode = if (s.isChoiceMode) "choice" else "match"
            )
        )
    }

    /** 4択のヒント状態を引き直す (出題が変わった / ヒントを開いた / 解答した とき)。 */
    private fun withChoiceHint(state: ColorMatchUiState): ColorMatchUiState {
        val q = state.choiceQuestion ?: return state.copy(choiceHint = null)
        return state.copy(
            choiceHint = colorQuizHintState(
                question = q, opened = state.choiceOpened, answered = state.choiceVerdict != null
            )
        )
    }

    fun openChoiceHint(kind: ColorQuizHintKind) {
        val s = _uiState.value
        if (s.choiceVerdict != null || s.choiceOpened.contains(kind)) return
        _uiState.value = withChoiceHint(s.copy(choiceOpened = s.choiceOpened + kind))
    }

    fun pickChoice(hex: String) {
        val s = _uiState.value
        val q = s.choiceQuestion ?: return
        if (s.choiceVerdict != null) return
        // 正誤・獲得点 (開いたヒントで決まる)・積み上げはコアがまとめて返す。
        val outcome = colorQuizAnswer(
            question = q, opened = s.choiceOpened, pickedHex = hex,
            before = s.choiceTally, questionCount = s.questionCount.toUInt()
        )
        val name = s.idolsById[q.answer.id]?.name ?: ""
        val number = s.plays.size + 1
        val family = colorQuizHintState(question = q, opened = s.choiceOpened, answered = true).familyLabel
        val picked = if (outcome.isCorrect) null else hex.uppercase()
        _uiState.value = withChoiceHint(
            s.copy(
                choiceTally = outcome.tally,
                choiceScoreBefore = s.choiceTally.points.toInt(),
                plays = s.plays + QuizStagePlay(
                    number = number, isCorrect = outcome.isCorrect,
                    answerName = name, answerHex = q.answer.color, pickedName = picked
                ),
                choiceVerdict = QuizVerdict(
                    isCorrect = outcome.isCorrect, number = number,
                    answerName = name, answerHex = q.answer.color,
                    earned = outcome.earnedPoints.toInt(), base = s.choiceHint?.baseValue?.toInt() ?: 0,
                    hints = outcome.revealedHints.toInt(), pickedName = picked,
                    detail = listOfNotNull(q.answer.color?.uppercase(), family).joinToString(" · ")
                )
            )
        )
        saveProgress()
    }

    /** × で閉じる (結果前は設定画面へ戻る)。 */
    fun resetToSetup() {
        _uiState.value = _uiState.value.copy(inGame = false, sessionDone = false, sessionResult = null)
    }

    fun selectHex(hex: String) {
        val s = _uiState.value
        if (s.judged) return
        _uiState.value = s.copy(selectedHex = if (s.selectedHex == hex) null else hex)
    }

    fun onMemberTap(idolId: String) {
        val s = _uiState.value
        if (s.judged) return
        val hex = s.selectedHex
        if (hex != null) {
            // 同じ色を別の人に付けていたら外してから付け替える。
            val cleared = s.assignments.filterValues { it != hex }
            _uiState.value = s.copy(assignments = cleared + (idolId to hex), selectedHex = null)
        } else if (s.assignments.containsKey(idolId)) {
            _uiState.value = s.copy(assignments = s.assignments - idolId)
        }
    }

    /** 1 問の答え合わせ。行の正誤・正解数・正解色の表示文字列はコアが一括で返す。 */
    fun judge() {
        val s = _uiState.value
        if (s.judged || s.assignments.size != s.members.size) return
        val judgement = colorMatchJudgeRound(
            members = s.members,
            assignments = s.assignments.map { (idolId, hex) -> ColorMatchAssignment(idolId = idolId, hex = hex) }
        )
        // 外したメンバーを「見直す」に並べる (全員当てた問題は並べない)。
        val missed = s.members.filterIndexed { i, _ -> judgement.correct.getOrNull(i) != true }
        val cleared = judgement.score == judgement.outOf
        val shown = if (cleared) s.members else missed
        _uiState.value = s.copy(
            judgement = judgement,
            totalCorrect = s.totalCorrect + judgement.score.toInt(),
            totalAnswered = s.totalAnswered + judgement.outOf.toInt(),
            plays = s.plays + QuizStagePlay(
                number = s.roundIndex + 1, isCorrect = cleared,
                answerName = shown.mapNotNull { s.idolsById[it.id]?.name }.joinToString("、"),
                answerHex = shown.firstOrNull()?.color,
                pickedName = null
            )
        )
        saveProgress()
    }

    fun advance() {
        val s = _uiState.value
        if (s.roundIndex + 1 < s.questionCount) {
            _uiState.value = withChoiceHint(
                s.copy(
                    roundIndex = s.roundIndex + 1,
                    assignments = emptyMap(), selectedHex = null, judgement = null,
                    choiceOpened = emptyList(), choiceVerdict = null
                )
            )
        } else {
            finishSession()
        }
    }

    private fun finishSession() {
        resumeStore.clear(GameKind.colorMatch)
        val s = _uiState.value
        val previousBest = progressStore.previousBestScore(GameKind.colorMatch)
        val result: QuizSessionResult
        if (s.isChoiceMode) {
            // 4択はヒント込みの点 / 満点を記録する (満点はコアが出題数から出す)。
            result = colorQuizSessionResult(tally = s.choiceTally, questionCount = s.questionCount.toUInt())
        } else {
            // 点 = 色を当てた人数、「n / N 正解」= 全員当てた問題数。グレードの閾値はコア。
            result = quizAccuracyResult(
                points = s.totalCorrect.toUInt(), outOf = s.totalAnswered.toUInt(),
                correct = s.plays.count { it.isCorrect }.toUInt(), questions = s.questionCount.toUInt()
            )
        }
        // 4択はヒント込みの点 / 満点、並べるは当てた人数 / 出題人数を記録する。
        val update = if (s.isChoiceMode) {
            progressStore.recordResult(GameKind.colorMatch, score = s.choiceTally.points.toInt(), outOf = result.outOf.toInt())
        } else {
            progressStore.recordResult(GameKind.colorMatch, score = s.totalCorrect, outOf = s.totalAnswered)
        }
        _uiState.value = s.copy(
            sessionDone = true,
            sessionResult = result,
            choiceVerdict = null,
            judgement = null,
            isNewBest = update.isNewBest,
            previousBest = previousBest
        )
    }

    class Factory(private val app: Application, private val resume: QuizSuspended? = null) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            ColorMatchViewModel(app, resume) as T
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ColorMatchGameScreen(
    onBack: () -> Unit,
    resume: QuizSuspended? = null,
    viewModel: ColorMatchViewModel = viewModel(
        factory = ColorMatchViewModel.Factory(LocalContext.current.applicationContext as Application, resume)
    )
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    if (state.inGame || state.sessionDone) {
        ColorMatchStage(state, viewModel, onBack)
        return
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("メンバーカラー合わせ", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            if (state.isLoading) {
                Box(Modifier.fillMaxWidth().padding(top = 60.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            } else {
                ColorMatchSetup(state, viewModel)
            }
        }
    }
}

@Composable
private fun ColorMatchSetup(state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    Text(
        "出題ブランドを選んで、似た色のメンバーの色を当てよう。",
        fontSize = 13.sp, color = DS.ink2
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("遊び方", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        ImasSegmented(labels = PLAY_MODE_LABELS, selection = state.playMode, onSelect = { viewModel.setPlayMode(it) })
        Text(
            if (state.isChoiceMode) "名前を見て、その子のイメージカラーを 4 色から選ぶ"
            else "何人かの名前に、色をタップで割り当てる",
            fontSize = 12.sp, color = DS.ink3
        )
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("難易度", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        ImasSegmented(labels = LEVEL_LABELS, selection = state.difficulty, onSelect = { viewModel.setDifficulty(it) })
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("問題数", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        val idx = QUESTION_COUNT_OPTIONS.indexOf(state.questionCount).coerceAtLeast(0)
        ImasSegmented(
            labels = QUESTION_COUNT_OPTIONS.map { "${it}問" }, selection = idx,
            onSelect = { viewModel.setQuestionCount(QUESTION_COUNT_OPTIONS[it]) }
        )
    }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("出題ブランド", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
        Text("未選択なら全ブランドから出題", fontSize = 12.sp, color = DS.ink3)
        GameBrandFilterGrid(
            brands = state.brands, selectedBrandIds = state.selectedBrandIds,
            onToggle = { viewModel.toggleBrand(it) }, onClearAll = { viewModel.clearBrands() }
        )
    }
    Box(Modifier.alpha(if (state.canStart) 1f else 0.5f)) {
        QuizPrimaryButton(title = "はじめる（全${state.questionCount}問）") { if (state.canStart) viewModel.startSession() }
    }
}

// MARK: - ゲーム (ステージ)

@Composable
private fun ColorMatchStage(state: ColorMatchUiState, viewModel: ColorMatchViewModel, onBack: () -> Unit) {
    val result = state.sessionResult
    val header = when {
        result != null -> QuizStageHeader.Result(result.questions.toInt())
        state.isChoiceMode -> QuizStageHeader.Question(
            current = minOf(state.plays.size + if (state.choiceVerdict == null) 1 else 0, state.questionCount),
            total = state.questionCount, points = state.choiceTally.points.toInt()
        )
        else -> QuizStageHeader.Question(
            current = minOf(state.plays.size + if (state.judged) 0 else 1, state.questionCount),
            total = state.questionCount, points = state.totalCorrect
        )
    }
    val answering = if (state.isChoiceMode) state.choiceVerdict == null else !state.judged

    QuizStageScaffold(
        title = "メンバーカラー",
        header = header,
        onClose = { if (result == null) viewModel.resetToSetup() else onBack() },
        scrollKey = state.plays.size to answering,
        trailing = {
            if (result != null) {
                QuizStageShareButton(
                    cardTitle = "メンバーカラー合わせ", shareName = "メンバーカラー合わせ", result = result,
                    plays = state.plays, isNewBest = state.isNewBest, fileNamePrefix = "color_match",
                    subtitle = "${if (state.isChoiceMode) "4択" else "並べる"} · ${LEVEL_LABELS[state.difficulty]}"
                )
            }
        }
    ) {
        when {
            result != null -> QuizStageResultView(
                result = result, isNewBest = state.isNewBest, previousBest = state.previousBest,
                slots = state.plays.penlights(total = state.questionCount, answering = false),
                longestStreak = state.plays.longestStreak, misses = state.plays.misses,
                onReplay = { viewModel.startSession() }, onClose = onBack
            )
            state.isChoiceMode -> ChoiceStage(state, viewModel)
            else -> {
                QuizStageProgress(
                    slots = state.plays.penlights(total = state.questionCount, answering = !state.judged),
                    caption = "全員当てると点灯 · ${LEVEL_LABELS[state.difficulty]}",
                    streak = state.plays.streak, streakBrokeAt = state.plays.streakBrokeAt
                )
                state.judgement?.let { RoundVerdict(it, state.roundIndex) }
                MatchTicket(state, viewModel)
                if (!state.judged) MatchPalette(state, viewModel)
                if (state.judged) {
                    QuizStageNextButton(
                        isLastQuestion = state.isLastRound,
                        onNext = { viewModel.advance() }, onFinish = { viewModel.advance() }
                    )
                } else {
                    val ready = state.members.isNotEmpty() && state.assignments.size == state.members.size
                    QuizStagePrimaryButton(
                        title = if (ready) "判定する" else "あと ${state.members.size - state.assignments.size} 人",
                        enabled = ready,
                        modifier = Modifier.padding(top = 4.dp)
                    ) { viewModel.judge() }
                }
            }
        }
    }
}

// MARK: - 4択

@Composable
private fun ChoiceStage(state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    QuizStageProgress(
        slots = state.plays.penlights(total = state.questionCount, answering = state.choiceVerdict == null),
        caption = state.plays.setlistCaption(state.questionCount),
        streak = state.plays.streak, streakBrokeAt = state.plays.streakBrokeAt
    )
    val verdict = state.choiceVerdict
    val q = state.choiceQuestion
    val hint = state.choiceHint
    if (verdict != null) {
        QuizVerdictCard(verdict)
        QuizVerdictStats(before = state.choiceScoreBefore, after = state.choiceTally.points.toInt(), streak = state.plays.streak)
        if (!verdict.isCorrect) QuizVerdictFootnote()
        QuizStageNextButton(
            isLastQuestion = state.isLastRound,
            onNext = { viewModel.advance() }, onFinish = { viewModel.advance() }
        )
    } else if (q != null && hint != null) {
        ChoiceTicket(state, q, hint, viewModel)
        ChoiceSwatches(q, hint) { viewModel.pickChoice(it) }
    }
}

@Composable
private fun ChoiceTicket(state: ColorMatchUiState, q: ColorQuizQuestion, hint: ColorQuizHintState, viewModel: ColorMatchViewModel) {
    val idol = state.idolsById[q.answer.id]
    QuizTicket {
        QuizTicketTitleBlock(
            label = "IMAGE COLOR", question = "この子のイメージカラーはどれ？",
            value = hint.currentValue.toInt(), base = hint.baseValue.toInt()
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.padding(top = 2.dp)
            ) {
                // 色はネタバレしないよう中立アバター (取り込んだ画像があれば画像)。
                ImasAvatar(label = idol?.shortName ?: "", seed = null, size = 56.dp, entityId = q.answer.id)
                Column(verticalArrangement = Arrangement.spacedBy(2.dp), modifier = Modifier.weight(1f)) {
                    if (state.isCrossBrand) {
                        idol?.brandId?.let { state.brandShortNames[it] }?.let {
                            Text(it, style = QS.text(12, FontWeight.Bold), color = QS.paperSub)
                        }
                    }
                    QSFitText(idol?.name ?: "", QS.text(34, FontWeight.Black), QS.paperInk, maxLines = 2, minScale = 0.5f)
                }
            }
        }
        QuizTicketNotch()
        val tiles = buildList {
            hint.familyLabel?.let { add(QuizHintTileSpec("family-open", "色の系統", QuizHintPhase.Open(it))) }
            hint.hints.forEach { option ->
                add(
                    QuizHintTileSpec(
                        key = option.kind.name,
                        title = if (option.kind == ColorQuizHintKind.FAMILY) "色の系統" else "2択にする",
                        phase = QuizHintPhase.Available(option.cost.toInt()) { viewModel.openChoiceHint(option.kind) }
                    )
                )
            }
            if (ColorQuizHintKind.FIFTY_FIFTY in state.choiceOpened) {
                add(QuizHintTileSpec("fifty-open", "2択にする", QuizHintPhase.Open("2色に")))
            }
        }
        QuizTicketHintTiles(tiles = tiles)
    }
}

private val SWATCH_LETTERS = listOf("A", "B", "C", "D", "E", "F", "G", "H")

/** 色の選択肢 (2×2)。2択ヒントで消した色は押せなくして薄くする。 */
@Composable
private fun ChoiceSwatches(q: ColorQuizQuestion, hint: ColorQuizHintState, onPick: (String) -> Unit) {
    val out = hint.eliminated.map { it.toInt() }.toSet()
    Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(top = 4.dp)) {
        q.choices.withIndex().chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEach { (i, hex) ->
                    val isOut = i in out
                    val alpha by animateFloatAsState(if (isOut) 0.18f else 1f, label = "swatch")
                    val letter = SWATCH_LETTERS[i % SWATCH_LETTERS.size]
                    Column(
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                        modifier = Modifier
                            .weight(1f)
                            .alpha(alpha)
                            .quizPress(enabled = !isOut) { onPick(hex) }
                            .clip(RoundedCornerShape(18.dp))
                            .background(QS.panel)
                            .border(1.dp, QS.line, RoundedCornerShape(18.dp))
                            .padding(8.dp)
                            .semantics { contentDescription = "色 $letter $hex" }
                    ) {
                        Box(
                            Modifier.fillMaxWidth().height(76.dp).clip(RoundedCornerShape(12.dp))
                                .background(qsColor(hex, QS.line)).border(1.dp, QS.line, RoundedCornerShape(12.dp))
                        )
                        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp)) {
                            Text(letter, style = QS.mono(11), color = QS.faint)
                            Spacer(Modifier.weight(1f))
                            Text(hex.uppercase(), style = QS.mono(11), color = QS.ink)
                        }
                    }
                }
                if (row.size < 2) Spacer(Modifier.weight(1f))
            }
        }
    }
}

// MARK: - 並べる

/** 答え合わせの一枚。全員当てたら生成りのカード、外したら暗いカード。 */
@Composable
private fun RoundVerdict(j: ColorMatchJudgement, roundIndex: Int) {
    val cleared = j.score == j.outOf
    val fg = if (cleared) QS.paperInk else QS.ink
    Row(
        verticalAlignment = Alignment.Bottom,
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(24.dp))
            .background(if (cleared) QS.paper else QS.panel)
            .then(if (cleared) Modifier else Modifier.border(1.dp, QS.line, RoundedCornerShape(24.dp)))
            .padding(horizontal = 22.dp, vertical = 18.dp)
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.weight(1f)) {
            Text(
                "Q.${twoDigits(roundIndex + 1)} — " + (if (cleared) "PERFECT" else "RESULT"),
                style = QS.mono(12, 1.4f), color = fg
            )
            QSFitText(
                if (cleared) "全員正解！" else "${j.score} / ${j.outOf} 正解",
                QS.text(if (cleared) 40 else 34, FontWeight.Black), fg
            )
        }
        Text("+${j.score}", style = QS.num(64, FontWeight.Black), color = fg)
    }
}

@Composable
private fun MatchTicket(state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    QuizTicket {
        QuizTicketHeading(
            label = "IMAGE COLOR",
            question = if (state.judged) "答え合わせ" else "だれのイメージカラー？"
        )
        Text(
            if (state.judged) "丸の中が選んだ色、名前の下が本人の色" else "色を選んでから、名前をタップで割り当て",
            style = QS.text(12, FontWeight.Bold), color = QS.paperSub,
            modifier = Modifier.padding(start = 18.dp, end = 18.dp, bottom = 8.dp)
        )
        QuizTicketNotch()
        state.members.forEachIndexed { idx, member -> MemberRow(member, idx, state, viewModel) }
        Spacer(Modifier.height(6.dp))
    }
}

@Composable
private fun MemberRow(member: ColorMatchIdol, position: Int, state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    val idol = state.idolsById[member.id]
    val assigned = state.assignments[member.id]
    // 行の正誤はコアの答え合わせ結果をそのまま使う (画面側で色を比べ直さない)。
    val correct = state.judgement?.correct?.getOrNull(position) == true
    val hexLabel = state.judgement?.correctHexLabels?.getOrNull(position)
    // 色を選んでいる間は、割り当て先の候補として丸を強調する (iOS のドロップ先のハイライト相当)。
    val isTarget = !state.judged && state.selectedHex != null
    val slotScale by animateFloatAsState(
        if (isTarget && assigned == null) 1.06f else 1f,
        spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMedium), label = "slot"
    )
    Column(Modifier.fillMaxWidth()) {
        if (position > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(QS.paperLine))
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 60.dp)
                .clickable(
                    interactionSource = remember { MutableInteractionSource() }, indication = null,
                    enabled = !state.judged
                ) { viewModel.onMemberTap(member.id) }
                .padding(horizontal = 18.dp, vertical = 8.dp)
        ) {
            // アイドル本人 (色はネタバレしないよう中立アバター: 取り込んだ画像があれば画像)
            ImasAvatar(label = idol?.shortName ?: "", seed = null, size = 40.dp, entityId = member.id)
            Column(verticalArrangement = Arrangement.spacedBy(1.dp), modifier = Modifier.weight(1f)) {
                if (state.isCrossBrand) {
                    idol?.brandId?.let { state.brandShortNames[it] }?.let {
                        Text(it, style = QS.text(11, FontWeight.Bold), color = QS.paperSub)
                    }
                }
                QSFitText(idol?.name ?: "", QS.text(17, FontWeight.Black), QS.paperInk, minScale = 0.7f)
                if (hexLabel != null) {
                    // 答え合わせでは本人のメンバーカラーを色見本 + HEX コードで明示する。
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier.padding(top = 2.dp)
                    ) {
                        Box(
                            Modifier.size(width = 28.dp, height = 12.dp).clip(RoundedCornerShape(3.dp))
                                .background(qsColor(member.color, QS.paperMuted))
                        )
                        Text(hexLabel, style = QS.mono(11), color = QS.paperSub)
                    }
                }
            }
            // 割り当てた色スロット (タップ対象)
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(44.dp)
                    .graphicsLayer { scaleX = slotScale; scaleY = slotScale }
                    .then(
                        if (assigned != null) Modifier.clip(CircleShape).background(qsColor(assigned, QS.paperMuted))
                        else Modifier.dashedBorder(if (isTarget) QS.paperInk else QS.paperMuted, 2.dp, 22.dp, dash = 4.dp, gap = 3.dp)
                    )
            ) {
                if (state.judged) {
                    Icon(
                        if (correct) Icons.Filled.Check else Icons.Filled.Close, contentDescription = if (correct) "正解" else "不正解",
                        tint = assigned?.let { ImasTheme.onColor(qsColor(it, QS.paperMuted)) } ?: QS.paperInk,
                        modifier = Modifier.size(20.dp)
                    )
                } else if (assigned == null) {
                    Text("?", style = QS.num(18), color = QS.paperSub)
                }
            }
        }
    }
}

/** 色チップ。色見本 + 記号 + HEX。タップで選んでから名前をタップすると割り当てる。 */
@Composable
private fun MatchPalette(state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        state.palette.withIndex().chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEach { (i, hex) ->
                    val used = hex in state.assignments.values
                    val selected = state.selectedHex == hex
                    val scale by animateFloatAsState(
                        if (selected) 1.03f else 1f,
                        spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMedium), label = "chip"
                    )
                    val letter = SWATCH_LETTERS[i % SWATCH_LETTERS.size]
                    val swatch = qsColor(hex, QS.line)
                    Column(
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                        modifier = Modifier
                            .weight(1f)
                            .graphicsLayer { scaleX = scale; scaleY = scale }
                            .alpha(if (used && !selected) 0.45f else 1f)
                            .clip(RoundedCornerShape(16.dp))
                            .background(QS.panel)
                            .border(if (selected) 2.5.dp else 1.dp, if (selected) QS.ink else QS.line, RoundedCornerShape(16.dp))
                            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                                viewModel.selectHex(hex)
                            }
                            .padding(6.dp)
                            .semantics { contentDescription = "色 $letter $hex" + if (selected) " 選択中" else "" }
                    ) {
                        Box(
                            contentAlignment = Alignment.Center,
                            modifier = Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(10.dp)).background(swatch)
                        ) {
                            if (used) Icon(Icons.Filled.Check, contentDescription = null, tint = ImasTheme.onColor(swatch), modifier = Modifier.size(18.dp))
                        }
                        Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp)) {
                            Text(letter, style = QS.mono(10), color = QS.faint)
                            Spacer(Modifier.weight(1f).width(2.dp))
                            Text(hex.uppercase(), style = QS.mono(10), color = QS.ink)
                        }
                    }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}
