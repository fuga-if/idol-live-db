package com.fugaif.imaslivedb.ui.games

import android.app.Application
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.scaleIn
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
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
import com.fugaif.imaslivedb.data.model.SoloOriginalSingerRow
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import kotlin.random.Random
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.QuizSessionResult
import uniffi.imas_core.QuizTally
import uniffi.imas_core.SongQuizHintKind
import uniffi.imas_core.SongQuizOriginalArtistRow
import uniffi.imas_core.SongQuizSingerRef
import uniffi.imas_core.SongSingerQuizHintState
import uniffi.imas_core.songSingerQuizAnswer
import uniffi.imas_core.songSingerQuizHintState
import uniffi.imas_core.songSingerQuizSession
import uniffi.imas_core.songSingerQuizSessionResult

// =============================================================================
// ソロ曲クイズ (ヒント式段階採点)。iOS SongSingerQuizView の移植。
// 最初は「曲名だけ」で出題し、ヒントを開くほど手がかりが増える代わりに獲得点が下がる。
// 見た目は QuizStage.kt の「ステージ + チケット」。
//
// 母集団 (原唱が単独のソロ曲・外部ゲストや対象外ブランドの除外)、出題抽選、
// 開示段階ごとの点数はすべて imas-core の `domain::quiz_generation` が持つ。
// ここに残すのは Compose の描画・音声再生・シード調達・index → 実体の解決だけ。
// =============================================================================

/** コアが返した 1 問を、画面が描ける形 (Song / Idol 実体) に解決したもの。 */
data class SongQuestion(val song: Song, val answer: Idol, val choices: List<Idol>)

/** 4 択に使うアイドルの射影 (歌手当てなのでプロフィールは要らない)。 */
internal fun Idol.toSongQuizSingerRef(): SongQuizSingerRef =
    SongQuizSingerRef(id = id, brandId = brandId, isExternal = isExternal)

/** `song_artists(role='original')` のソロ曲ぶん 1 行。 */
internal fun SoloOriginalSingerRow.toSongQuizRow(): SongQuizOriginalArtistRow =
    SongQuizOriginalArtistRow(songId = songId, idolId = idolId)

data class SongSingerQuizUiState(
    val isLoading: Boolean = true,
    val questions: List<SongQuestion> = emptyList(),
    val index: Int = 0,
    val selectedId: String? = null,
    /** この問題で開いたヒント (開いた順)。点数はコアがここから算出する。 */
    val opened: List<SongQuizHintKind> = emptyList(),
    /** この問題で出せるヒント (タイルの並び順)。データが無いものは載らない。 */
    val available: List<SongQuizHintKind> = emptyList(),
    /** ブランド id → 短縮名 (ブランドヒントの表示用)。 */
    val brandNames: Map<String, String> = emptyMap(),
    /** 開示範囲・次のヒント・いまの獲得点。コアが返す。 */
    val hintState: SongSingerQuizHintState? = null,
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
    val question: SongQuestion? get() = questions.getOrNull(index)
}

class SongSingerQuizViewModel(
    app: Application,
    private val selectedBrandIds: Set<String>,
    /** つづきから。最初の 1 回だけ使う (「もう一度」は新しいセッション)。 */
    private var resume: QuizSuspended? = null
) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val songRepository = AppModule.from(app).songRepository
    private val progressStore = AppModule.from(app).gameProgressStore
    private val resumeStore = AppModule.from(app).quizResumeStore
    private val stats = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(SongSingerQuizUiState())
    val uiState: StateFlow<SongSingerQuizUiState> = _uiState.asStateFlow()

    /** 出題生成に渡した並び。コアが返す index はこの配列を指す。 */
    private var singers: List<Idol> = emptyList()
    private var rows: List<SoloOriginalSingerRow> = emptyList()
    private var brandNames: Map<String, String> = emptyMap()

    /** このセッションの出題シード。 */
    private var seed: ULong = 0u

    init {
        viewModelScope.launch {
            singers = idolRepository.fetchIdols()
            rows = songRepository.fetchSoloOriginalSingers()
            brandNames = stats.fetchBrands().associate { it.id to it.shortName }
            startSession()
        }
    }

    /** 1 ゲーム分 (全 [QUIZ_SESSION_LENGTH] 問) をまとめて生成する。候補不足なら空。 */
    private suspend fun makeSession(seed: ULong): List<SongQuestion> {
        val questions = songSingerQuizSession(
            rows = rows.map { it.toSongQuizRow() },
            singers = singers.map { it.toSongQuizSingerRef() },
            selectedBrandIds = selectedBrandIds.toList(),
            seed = seed
        )
        if (questions.isEmpty()) return emptyList()
        // 曲の実体は出題が決まってから 1 回でまとめて引く (問題ごとに DB を叩かない)。
        val songById = songRepository.fetchSongsByIds(questions.map { it.songId }.distinct()).associateBy { it.id }
        return questions.mapNotNull { q ->
            val song = songById[q.songId] ?: return@mapNotNull null
            SongQuestion(
                song = song,
                answer = singers[q.answer.toInt()],
                choices = q.choices.map { singers[it.toInt()] }
            )
        }
    }

    private suspend fun startSession() {
        // つづきからは保存したシードで同じ出題を作り直し、答えた所まで進める。
        val saved = resume
        resume = null
        if (saved != null) {
            seed = saved.seed
        } else {
            // シードの調達だけがラッパの責務 (抽選そのものはコアの SplitMix64)。
            seed = Random.Default.nextLong().toULong()
            resumeStore.clear(GameKind.songSingerQuiz)
        }
        val questions = makeSession(seed)
        _uiState.value = withHintState(
            SongSingerQuizUiState(
                isLoading = false, questions = questions, brandNames = brandNames,
                index = saved?.nextIndex ?: 0,
                tally = saved?.tally ?: QuizTally(asked = 0u, correct = 0u, points = 0u),
                plays = saved?.plays.orEmpty()
            )
        )
        // 最後の問題まで答えてから閉じていたら、そのまま結果へ。
        if (saved != null && saved.nextIndex >= questions.size && questions.isNotEmpty()) finish()
    }

    /** 1 問答えるたびに途中経過を残す (× で閉じても「つづきから」で戻れる)。 */
    private fun saveProgress() {
        val s = _uiState.value
        resumeStore.save(
            QuizSuspended(
                kind = GameKind.songSingerQuiz, seed = seed, brandIds = selectedBrandIds.toList(),
                nextIndex = s.index + 1, asked = s.tally.asked.toInt(), correct = s.tally.correct.toInt(),
                points = s.tally.points.toInt(), plays = s.plays, total = QUIZ_SESSION_LENGTH
            )
        )
    }

    /**
     * この問題で出せるヒント (iOS `availableHints` と同じ条件)。データが無いもの、
     * 選択肢が全員同じブランドのときのブランドは外す。
     */
    private fun availableHints(q: SongQuestion): List<SongQuizHintKind> = buildList {
        if (!q.song.cdTitle.isNullOrEmpty()) add(SongQuizHintKind.CD)
        if (brandNames[q.answer.brandId] != null && q.choices.map { it.brandId }.toSet().size > 1) {
            add(SongQuizHintKind.BRAND)
        }
        if (!q.answer.color.isNullOrEmpty()) add(SongQuizHintKind.COLOR)
        if (!q.song.artworkUrl.isNullOrEmpty()) add(SongQuizHintKind.ARTWORK)
        if (!q.song.previewUrl.isNullOrEmpty()) add(SongQuizHintKind.PREVIEW)
    }

    /** 開示状態を引き直す。ヒント開封・解答・次問のたびに 1 回だけ呼ぶ。 */
    private fun withHintState(state: SongSingerQuizUiState): SongSingerQuizUiState {
        val q = state.question ?: return state.copy(hintState = null, available = emptyList())
        val available = availableHints(q)
        return state.copy(
            available = available,
            hintState = songSingerQuizHintState(
                opened = state.opened,
                available = available,
                answered = state.selectedId != null
            )
        )
    }

    fun openHint(kind: SongQuizHintKind) {
        val s = _uiState.value
        val song = s.question?.song ?: return
        if (s.selectedId != null || s.opened.contains(kind)) return
        // 開けるか (試聴はジャケットの後) はコアが返すヒント一覧で決まる。
        val option = s.hintState?.hints?.firstOrNull { it.kind == kind } ?: return
        if (option.locked) return
        _uiState.value = withHintState(s.copy(opened = s.opened + kind))
        if (kind == SongQuizHintKind.PREVIEW) {
            song.previewUrl?.takeIf { it.isNotEmpty() }?.let {
                AudioPreviewManager.togglePreview(it, song.id)
            }
        }
    }

    fun pick(idolId: String) {
        val s = _uiState.value
        val q = s.question ?: return
        if (s.selectedId != null) return
        val idol = q.choices.firstOrNull { it.id == idolId } ?: return
        AudioPreviewManager.stop()
        // 正誤判定・獲得点 (開いたヒントで決まる)・積み上げはコアがまとめて返す。
        val outcome = songSingerQuizAnswer(
            opened = s.opened,
            pickedIdolId = idol.id,
            answerIdolId = q.answer.id,
            before = s.tally
        )
        val number = s.plays.size + 1
        val picked = if (outcome.isCorrect) null else idol.name
        _uiState.value = withHintState(
            s.copy(
                selectedId = idol.id,
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
                    earned = outcome.earnedPoints.toInt(), base = s.hintState?.baseValue?.toInt() ?: 0,
                    hints = outcome.revealedHints.toInt(), pickedName = picked,
                    detail = "「${q.song.title}」" + (q.song.cdTitle?.let { " · $it" } ?: "")
                )
            )
        )
        saveProgress()
    }

    fun nextQuestion() {
        AudioPreviewManager.stop()
        val s = _uiState.value
        _uiState.value = withHintState(
            s.copy(index = s.index + 1, selectedId = null, opened = emptyList(), verdict = null)
        )
    }

    fun finish() {
        val s = _uiState.value
        val result = songSingerQuizSessionResult(s.tally)
        val previousBest = progressStore.previousBestScore(GameKind.songSingerQuiz)
        // 保存と「自己ベスト更新！」の判定は進捗ストア (コアの game_progress) が 1 回で返す。
        val update = progressStore.recordResult(
            GameKind.songSingerQuiz, score = result.points.toInt(), outOf = result.outOf.toInt()
        )
        resumeStore.clear(GameKind.songSingerQuiz)
        _uiState.value = s.copy(result = result, verdict = null, isNewBest = update.isNewBest, previousBest = previousBest)
    }

    fun restart() {
        AudioPreviewManager.stop()
        viewModelScope.launch { startSession() }
    }

    class Factory(
        private val app: Application,
        private val selectedBrandIds: Set<String>,
        private val resume: QuizSuspended? = null
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            SongSingerQuizViewModel(app, selectedBrandIds, resume) as T
    }
}

@Composable
fun SongSingerQuizScreen(
    selectedBrandIds: Set<String>,
    onBack: () -> Unit,
    resume: QuizSuspended? = null,
    viewModel: SongSingerQuizViewModel = viewModel(
        factory = SongSingerQuizViewModel.Factory(
            LocalContext.current.applicationContext as Application, selectedBrandIds, resume
        )
    )
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    DisposableEffect(Unit) { onDispose { AudioPreviewManager.stop() } }
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
        title = "ソロ曲クイズ",
        header = header,
        onClose = onBack,
        scrollKey = state.plays.size to (verdict == null),
        trailing = {
            if (result != null) {
                // 背景には遊んだ曲のジャケットを敷く。
                QuizStageShareButton(
                    cardTitle = "ソロ曲クイズ", shareName = "ソロ曲クイズ", result = result,
                    plays = state.plays, isNewBest = state.isNewBest, fileNamePrefix = "song_quiz",
                    artworkUrls = state.questions.take(state.plays.size).mapNotNull { it.song.artworkUrl }
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
                    SongTicket(question, state.available, hintState, state.brandNames) { viewModel.openHint(it) }
                    QuizStageChoiceGrid(choices = question.choices.map { QuizStageChoice(it.id, it.name) }) {
                        viewModel.pick(it.id)
                    }
                }
            }
            else -> QuizStageEmpty(Icons.Filled.MusicNote, "出題できるソロ曲が不足しています")
        }
    }
}

/** 曲名を大きく載せ、ジャケットを開いたら横に出す。ヒントは 3 列のタイル。 */
@Composable
private fun SongTicket(
    q: SongQuestion,
    available: List<SongQuizHintKind>,
    hint: SongSingerQuizHintState,
    brandNames: Map<String, String>,
    onOpen: (SongQuizHintKind) -> Unit
) {
    QuizTicket {
        QuizTicketTitleBlock(
            label = "SOLO SONG", question = "この曲を歌っているのは？",
            value = hint.currentValue.toInt(), base = hint.baseValue.toInt()
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
                modifier = Modifier.padding(top = 6.dp)
            ) {
                AnimatedVisibility(visible = hint.showArtwork, enter = scaleIn(initialScale = 0.8f) + fadeIn()) {
                    ArtworkImage(
                        url = q.song.artworkUrl, size = 84.dp,
                        previewUrl = if (hint.canPreview) q.song.previewUrl else null,
                        songTitle = q.song.title, songId = q.song.id
                    )
                }
                QSFitText(
                    q.song.title, QS.text(if (hint.showArtwork) 30 else 40, FontWeight.Black), QS.paperInk,
                    maxLines = 3, minScale = 0.5f, modifier = Modifier.weight(1f)
                )
            }
        }
        if (available.isNotEmpty()) {
            QuizTicketNotch()
            QuizTicketHintTiles(
                columns = 3,
                tiles = available.mapNotNull { kind -> hintTile(kind, q, hint, brandNames) { onOpen(kind) } }
            )
        }
    }
}

private fun SongQuizHintKind.title(): String = when (this) {
    SongQuizHintKind.CD -> "収録CD"
    SongQuizHintKind.BRAND -> "ブランド"
    SongQuizHintKind.COLOR -> "イメージカラー"
    SongQuizHintKind.ARTWORK -> "ジャケット"
    SongQuizHintKind.PREVIEW -> "試聴"
}

/** 1 枚のタイル。開いたか・コスト・ロックはすべてコアの [SongSingerQuizHintState] が返す。 */
private fun hintTile(
    kind: SongQuizHintKind,
    q: SongQuestion,
    hint: SongSingerQuizHintState,
    brandNames: Map<String, String>,
    onOpen: () -> Unit
): QuizHintTileSpec? {
    val phase: QuizHintPhase = if (kind in hint.shown) {
        when (kind) {
            SongQuizHintKind.CD -> QuizHintPhase.Open(q.song.cdTitle ?: "—")
            SongQuizHintKind.BRAND -> QuizHintPhase.Open(brandNames[q.answer.brandId] ?: "—")
            SongQuizHintKind.COLOR -> QuizHintPhase.OpenSwatch(q.answer.color ?: "", q.answer.color ?: "")
            SongQuizHintKind.ARTWORK -> QuizHintPhase.Open("表示中")
            SongQuizHintKind.PREVIEW -> QuizHintPhase.Open("再生中")
        }
    } else {
        val option = hint.hints.firstOrNull { it.kind == kind } ?: return null
        if (option.locked) QuizHintPhase.Locked(option.cost.toInt())
        else QuizHintPhase.Available(option.cost.toInt(), onOpen)
    }
    return QuizHintTileSpec(key = kind.name, title = kind.title(), phase = phase)
}
