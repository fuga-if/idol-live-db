package com.fugaif.imaslivedb.ui.introdon

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.WorkspacePremium
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.designsystem.ImasArtwork
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasCardList
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasStageCircleButton
import com.fugaif.imaslivedb.ui.designsystem.ImasStageEqualizer
import com.fugaif.imaslivedb.ui.designsystem.ImasStageIconTileButton
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePlaybackControl
import com.fugaif.imaslivedb.ui.designsystem.ImasStageProgressBar
import com.fugaif.imaslivedb.ui.designsystem.ImasStageRushFlash
import com.fugaif.imaslivedb.ui.navigation.BottomBarVisibility
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.share.IntroDonShareSheet
import com.fugaif.imaslivedb.ui.share.IntroShareLine
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasAlwaysDark
import com.fugaif.imaslivedb.ui.theme.ImasDarkNavigationBar
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.QS
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import uniffi.imas_core.IntroDonShareInput
import uniffi.imas_core.IntroDonShareMode
import uniffi.imas_core.IntroScore
import uniffi.imas_core.introQuestionCount
import uniffi.imas_core.introScoreAfterAnswer
import uniffi.imas_core.shareIntroDonText

// =============================================================================
// イントロドン本編 (ノーマル/ラッシュ/全曲チャレンジ)。iOS IntroGameView + IntroGameSession
// + IntroGameResultView の移植。パーティ対戦は IntroDonPartyScreen へ分離。
// =============================================================================

data class IntroDonGameUiState(
    val phase: IntroDonPhase = IntroDonPhase.LOADING,
    val questions: List<IntroDonQuestion> = emptyList(),
    val currentIndex: Int = 0,
    val score: Int = 0,
    val combo: Int = 0,
    val bestCombo: Int = 0,
    val records: List<IntroDonAnswerRecord> = emptyList(),
    val selectedTitle: String? = null,
    val isCorrect: Boolean? = null,
    val rushRemainingMs: Long = 0,
    val sessionStartMs: Long? = null,
    val elapsedMs: Long = 0,
    val isPlayingIntro: Boolean = false,
    val flashTick: Int = 0,
    val flashCorrect: Boolean = false,
    val playbackResetToken: Int = 0,
    val isNewBest: Boolean = false,
    val newBestTime: Boolean = false,
    val errorMessage: String? = null
) {
    val currentQuestion: IntroDonQuestion? get() = questions.getOrNull(currentIndex)
    val totalCount: Int get() = questions.size
}

/** コアに渡す今の点とコンボ。 */
private val IntroDonGameUiState.introScore: IntroScore
    get() = IntroScore(score.toUInt(), combo.toUInt(), bestCombo.toUInt())

class IntroDonGameViewModel(app: Application, private val settings: IntroDonSettings) : AndroidViewModel(app) {
    private val songRepository = AppModule.from(app).songRepository
    private val progressStore = AppModule.from(app).gameProgressStore
    private val bestStore = IntroDonBestStore(app)

    private val _uiState = MutableStateFlow(IntroDonGameUiState())
    val uiState: StateFlow<IntroDonGameUiState> = _uiState.asStateFlow()

    val isFast: Boolean get() = settings.mode.isFast

    private var playJob: Job? = null
    private var rushTimerJob: Job? = null
    private var revealAdvanceJob: Job? = null

    init {
        viewModelScope.launch {
            AudioPreviewManager.playbackState.collect { st ->
                _uiState.value = _uiState.value.copy(isPlayingIntro = st.isPlaying)
            }
        }
        generateQuestions()
    }

    private fun generateQuestions() {
        viewModelScope.launch {
            _uiState.value = IntroDonGameUiState(phase = IntroDonPhase.LOADING)
            try {
                val pool = songRepository.fetchIntroDonSongs(settings.selectedBrandIds)
                // 始められるか (4 曲の門) と何問出すかはコア。
                val count = introQuestionCount(settings.mode.sessionKind, pool.size.toUInt(), settings.questionCount.toUInt())
                if (count == null) {
                    _uiState.value = _uiState.value.copy(
                        phase = IntroDonPhase.LOADING,
                        errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。"
                    )
                    return@launch
                }
                val questions = buildIntroDonQuestions(pool, count.toInt())
                _uiState.value = IntroDonGameUiState(
                    phase = IntroDonPhase.PLAYING,
                    questions = questions,
                    sessionStartMs = System.currentTimeMillis()
                )
                if (settings.mode == IntroDonMode.RUSH) startRushTimer()
                playCurrentQuestion()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 失敗しても「問題を生成中…」のまま止まらないようにする。
                _uiState.value = _uiState.value.copy(
                    phase = IntroDonPhase.LOADING,
                    errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。"
                )
            }
        }
    }

    private fun startRushTimer() {
        val limitMs = settings.rushTimeLimitSec * 1000L
        val deadline = System.currentTimeMillis() + limitMs
        _uiState.value = _uiState.value.copy(rushRemainingMs = limitMs)
        rushTimerJob?.cancel()
        rushTimerJob = viewModelScope.launch {
            while (isActive) {
                val remaining = deadline - System.currentTimeMillis()
                _uiState.value = _uiState.value.copy(rushRemainingMs = remaining.coerceAtLeast(0))
                if (remaining <= 0) {
                    stopPlayback()
                    finalizeSession()
                    return@launch
                }
                delay(100)
            }
        }
    }

    private fun playCurrentQuestion() {
        playJob?.cancel()
        val question = _uiState.value.currentQuestion ?: return
        val url = question.previewUrl
        AudioPreviewManager.stop()
        if (url.isNullOrEmpty()) return
        AudioPreviewManager.togglePreview(url, question.id)
        if (isFast) return // 押すまで/次の問題まで流し続ける。自動停止しない。
        playJob = viewModelScope.launch {
            val started = withTimeoutOrNull(3_000) {
                while (isActive && !(AudioPreviewManager.playbackState.value.isPlaying && AudioPreviewManager.playbackState.value.nowPlayingUrl == url)) {
                    delay(30)
                }
                true
            }
            if (started != true) return@launch
            delay(settings.introDurationMs)
            if (!isActive) return@launch
            if (_uiState.value.phase == IntroDonPhase.PLAYING) {
                AudioPreviewManager.stop()
                _uiState.value = _uiState.value.copy(phase = IntroDonPhase.ANSWERING)
            }
        }
    }

    private fun stopPlayback() {
        playJob?.cancel()
        AudioPreviewManager.stop()
    }

    fun buzzToAnswer() {
        val s = _uiState.value
        if (s.phase != IntroDonPhase.PLAYING || settings.mode == IntroDonMode.RUSH) return
        stopPlayback()
        _uiState.value = s.copy(phase = IntroDonPhase.ANSWERING)
    }

    fun replayIntro() {
        _uiState.value = _uiState.value.copy(playbackResetToken = _uiState.value.playbackResetToken + 1)
        playCurrentQuestion()
    }

    fun continueHeld() {
        playJob?.cancel()
        AudioPreviewManager.resume()
    }

    fun pauseHeld() {
        AudioPreviewManager.pause()
    }

    fun continueForDuration() {
        playJob?.cancel()
        AudioPreviewManager.resume()
        playJob = viewModelScope.launch {
            delay(settings.introDurationMs)
            if (isActive) AudioPreviewManager.pause()
        }
    }

    fun submitAnswer(title: String) {
        val s = _uiState.value
        val q = s.currentQuestion ?: return
        if (s.phase != IntroDonPhase.PLAYING && s.phase != IntroDonPhase.ANSWERING) return
        stopPlayback()
        val correct = title == q.title
        // 点とコンボの数え方はコア。
        val next = introScoreAfterAnswer(s.introScore, correct)
        val records = s.records + IntroDonAnswerRecord(q.id, q.title, title, correct)
        val updated = s.copy(
            selectedTitle = title, isCorrect = correct,
            score = next.score.toInt(), combo = next.combo.toInt(), bestCombo = next.bestCombo.toInt(),
            records = records, flashTick = s.flashTick + 1, flashCorrect = correct
        )
        _uiState.value = updated
        if (isFast) advanceFast() else revealAndScheduleNext()
    }

    fun skipQuestion() {
        val s = _uiState.value
        val q = s.currentQuestion ?: return
        stopPlayback()
        val records = s.records + IntroDonAnswerRecord(q.id, q.title, null, false)
        val next = introScoreAfterAnswer(s.introScore, false)
        _uiState.value = s.copy(
            selectedTitle = null, isCorrect = false,
            score = next.score.toInt(), combo = next.combo.toInt(), bestCombo = next.bestCombo.toInt(),
            records = records
        )
        if (isFast) advanceFast() else _uiState.value = _uiState.value.copy(phase = IntroDonPhase.REVEALED)
    }

    private fun advanceFast() {
        val s = _uiState.value
        val next = if (settings.mode == IntroDonMode.RUSH) {
            if (s.questions.isEmpty()) 0 else (s.currentIndex + 1) % s.questions.size
        } else {
            s.currentIndex + 1
        }
        if (settings.mode == IntroDonMode.ALL_SONGS && next >= s.questions.size) {
            finalizeSession()
            return
        }
        _uiState.value = s.copy(currentIndex = next, selectedTitle = null, isCorrect = null, phase = IntroDonPhase.PLAYING)
        playCurrentQuestion()
    }

    private fun revealAndScheduleNext() {
        _uiState.value = _uiState.value.copy(phase = IntroDonPhase.REVEALED)
        revealAdvanceJob?.cancel()
        revealAdvanceJob = viewModelScope.launch {
            delay(5_000)
            if (isActive) nextQuestion()
        }
    }

    fun nextQuestion() {
        revealAdvanceJob?.cancel()
        val s = _uiState.value
        if (s.phase != IntroDonPhase.REVEALED) return
        val next = s.currentIndex + 1
        if (next >= s.questions.size) {
            finalizeSession()
        } else {
            _uiState.value = s.copy(
                currentIndex = next, selectedTitle = null, isCorrect = null,
                phase = IntroDonPhase.PLAYING, playbackResetToken = s.playbackResetToken + 1
            )
            playCurrentQuestion()
        }
    }

    private fun finalizeSession() {
        rushTimerJob?.cancel()
        val s = _uiState.value
        val elapsed = s.sessionStartMs?.let { System.currentTimeMillis() - it } ?: 0L
        val isNewBestScore = bestStore.submitScore(settings, s.score)
        val isNewBestTime = settings.mode == IntroDonMode.ALL_SONGS && bestStore.submitTime(settings, elapsed)
        _uiState.value = s.copy(phase = IntroDonPhase.FINISHED, elapsedMs = elapsed, isNewBest = isNewBestScore, newBestTime = isNewBestTime)
        if (s.records.isNotEmpty()) {
            progressStore.recordResult(GameKind.introDon, score = s.score, outOf = s.records.size)
        }
    }

    fun restart() {
        stopPlayback()
        rushTimerJob?.cancel()
        revealAdvanceJob?.cancel()
        generateQuestions()
    }

    fun onCleared_public() { // called from Composable DisposableEffect (onCleared() is protected)
        stopPlayback()
        rushTimerJob?.cancel()
        revealAdvanceJob?.cancel()
    }

    override fun onCleared() {
        stopPlayback()
        rushTimerJob?.cancel()
        revealAdvanceJob?.cancel()
        super.onCleared()
    }

    class Factory(private val app: Application, private val settings: IntroDonSettings) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IntroDonGameViewModel(app, settings) as T
    }
}

@Composable
fun IntroDonGameScreen(
    settings: IntroDonSettings,
    onExit: () -> Unit,
    viewModel: IntroDonGameViewModel = viewModel(
        factory = IntroDonGameViewModel.Factory(LocalContext.current.applicationContext as Application, settings)
    )
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var showExitDialog by remember { mutableStateOf(false) }

    DisposableEffect(Unit) { onDispose { viewModel.onCleared_public() } }

    // ゲーム中だけはライト/ダークで反転しない暗いステージに固定する (docs/DESIGN_SYSTEM.md §12)。
    // iOS の `.environment(\.colorScheme, .dark)` + `.toolbar(.hidden, for: .tabBar)` 相当
    // (QuizStageScaffold と同じ組み方)。
    BottomBarVisibility.Hide()
    ImasDarkNavigationBar()
    ImasAlwaysDark {
        Box(Modifier.fillMaxSize().background(QS.bg)) {
            Column(Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.screen, vertical = DS.Space.gap),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = { showExitDialog = true }) {
                        Icon(Icons.Filled.Close, "終了", tint = QS.dim)
                    }
                }

                when (state.phase) {
                    IntroDonPhase.LOADING -> LoadingBody(state.errorMessage, onExit)
                    IntroDonPhase.FINISHED -> IntroDonResultBody(settings, state, onReplay = { viewModel.restart() }, onExit = onExit)
                    else -> GameBody(settings, state, viewModel)
                }
            }
        }

        ImasConfirmDestructive(
            title = "ゲームを終了しますか？",
            isPresented = showExitDialog,
            onDismiss = { showExitDialog = false },
            onConfirm = onExit,
            actionTitle = "終了"
        )
    }
}

@Composable
private fun LoadingBody(errorMessage: String?, onExit: () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        if (errorMessage != null) {
            ImasEmptyState(
                kind = ImasEmptyStateKind.FAILED,
                title = errorMessage,
                actionTitle = "戻る",
                onAction = onExit
            )
        } else {
            ImasLoadingState(title = "問題を生成中...")
        }
    }
}

@Composable
private fun GameBody(settings: IntroDonSettings, state: IntroDonGameUiState, viewModel: IntroDonGameViewModel) {
    val isRush = settings.mode == IntroDonMode.RUSH
    val isFast = settings.mode.isFast

    Column(Modifier.fillMaxSize().padding(horizontal = DS.Space.gapLoose)) {
        HeaderBar(settings, state)
        ImasStageProgressBar(
            fraction = if (isRush) {
                if (settings.rushTimeLimitSec > 0) state.rushRemainingMs.toDouble() / (settings.rushTimeLimitSec * 1000.0) else 0.0
            } else {
                if (state.totalCount > 0) state.currentIndex.toDouble() / state.totalCount else 0.0
            },
            isUrgent = isRush && state.rushRemainingMs <= 10_000,
            modifier = Modifier.padding(vertical = DS.Space.gap)
        )

        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
            if (state.phase == IntroDonPhase.REVEALED) {
                RevealedBody(state, viewModel)
            } else {
                RoundBody(settings, state, viewModel, isFast)
            }
        }
    }
}

@Composable
private fun HeaderBar(settings: IntroDonSettings, state: IntroDonGameUiState) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (settings.mode == IntroDonMode.RUSH) {
            val urgent = state.rushRemainingMs <= 10_000
            val secs = ((state.rushRemainingMs + 999) / 1000).toInt()
            Pill(
                icon = Icons.Filled.Timer,
                text = String.format("%d:%02d", secs / 60, secs % 60),
                color = if (urgent) DS.danger else QS.ink
            )
        } else {
            Pill(icon = null, text = "${state.currentIndex + 1} / ${state.totalCount}", color = QS.dim, monochrome = true)
        }

        if (settings.mode == IntroDonMode.ALL_SONGS) {
            Row(modifier = Modifier.padding(start = DS.Space.gap)) {
                var liveMs by remember { mutableStateOf(0L) }
                LaunchedEffect(state.phase, state.sessionStartMs) {
                    val start = state.sessionStartMs ?: return@LaunchedEffect
                    while (state.phase != IntroDonPhase.FINISHED) {
                        liveMs = System.currentTimeMillis() - start
                        delay(100)
                    }
                }
                val secs = (liveMs / 1000).toInt()
                Pill(icon = Icons.Filled.AccessTime, text = String.format("%d:%02d", secs / 60, secs % 60), color = DS.favorite)
            }
        }

        Spacer(Modifier.weight(1f))

        if (state.combo >= 2) {
            val color = if (state.combo >= 8) DS.pick else if (state.combo >= 5) DS.favorite else QS.ink
            Pill(icon = Icons.Filled.LocalFireDepartment, text = "×${state.combo}", color = color, modifier = Modifier.padding(end = DS.Space.gap))
        }

        Pill(icon = Icons.Filled.CheckCircle, text = "${state.score}", color = DS.success)
    }
}

@Composable
private fun Pill(icon: ImageVector?, text: String, color: Color, modifier: Modifier = Modifier, monochrome: Boolean = false) {
    val shape = RoundedCornerShape(DS.rTag)
    val iconSize = with(LocalDensity.current) { 12.sp.toDp() }
    Row(
        modifier = modifier
            .background(if (monochrome) QS.panel else color.copy(alpha = 0.14f), shape)
            .padding(horizontal = DS.Space.gap, vertical = DS.Space.gapTight),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)
    ) {
        if (icon != null) Icon(icon, null, tint = color, modifier = Modifier.size(iconSize))
        ImasText(text, ImasTextRole.ROW_LABEL, color = if (monochrome) QS.dim else color)
    }
}

@Composable
private fun RoundBody(settings: IntroDonSettings, state: IntroDonGameUiState, viewModel: IntroDonGameViewModel, isFast: Boolean) {
    val showAnswer = isFast || state.phase == IntroDonPhase.ANSWERING
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), modifier = Modifier.fillMaxWidth()) {
        IntroDonElapsedLabel(isRunning = state.isPlayingIntro, resetKey = state.playbackResetToken)

        if (isFast) {
            val glyphSize = with(LocalDensity.current) { 24.sp.toDp() }
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
                Icon(Icons.Filled.MusicNote, null, tint = QS.ink, modifier = Modifier.size(glyphSize))
                ImasText("曲名は？", ImasTextRole.EYEBROW, color = QS.dim)
            }
        } else if (state.phase == IntroDonPhase.PLAYING) {
            ImasStageEqualizer(
                columns = 16,
                rows = 5,
                dotSize = with(LocalDensity.current) { 7.sp.toDp() },
                spacing = DS.sp1,
                color = QS.ink,
                isAnimating = state.isPlayingIntro,
                modifier = Modifier.padding(vertical = DS.Space.gap)
            )
        } else {
            ImasText("曲名を選んでください", ImasTextRole.ROW_LABEL, color = QS.dim)
        }

        if (!isFast) {
            val canBuzz = state.phase == IntroDonPhase.PLAYING
            ImasStageCircleButton(label = "!", size = DS.Size.touch * 3, onClick = viewModel::buzzToAnswer, isEnabled = canBuzz)
            ImasText(
                if (state.phase == IntroDonPhase.PLAYING) "わかったらタップ" else "",
                ImasTextRole.META,
                color = QS.dim
            )
        }

        ControlsRow(state, viewModel)

        if (showAnswer) {
            state.currentQuestion?.let { q ->
                Column(
                    modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
                ) {
                    q.choices.forEach { choice ->
                        IntroDonChoiceRow(title = choice) { viewModel.submitAnswer(choice) }
                    }
                }
            }
        }

        if (state.flashTick > 0) {
            FlashEffect(tick = state.flashTick, correct = state.flashCorrect)
        }
    }
}

@Composable
private fun FlashEffect(tick: Int, correct: Boolean) {
    var visible by remember(tick) { mutableStateOf(true) }
    LaunchedEffect(tick) {
        delay(350)
        visible = false
    }
    if (visible) ImasStageRushFlash(isCorrect = correct)
}

/**
 * もう一度 / 続きから (長押しで流し続ける) / 次の曲。iOS `controlsRow` と同じ 3 枚のタイルに揃える
 * (ステージの部品 `ImasStageIconTileButton` / `ImasStagePlaybackControl`)。
 */
@Composable
private fun ControlsRow(state: IntroDonGameUiState, viewModel: IntroDonGameViewModel) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(DS.sp2),
        verticalAlignment = Alignment.CenterVertically
    ) {
        ImasStageIconTileButton(
            icon = Icons.Filled.Replay, label = "もう一度",
            onClick = { viewModel.replayIntro() }, modifier = Modifier.weight(1f)
        )

        ImasStagePlaybackControl(
            isPlaying = state.isPlayingIntro,
            onTap = { viewModel.continueForDuration() },
            onHoldBegin = { viewModel.continueHeld() },
            onHoldEnd = { viewModel.pauseHeld() },
            modifier = Modifier.weight(1f)
        )

        ImasStageIconTileButton(
            icon = Icons.Filled.SkipNext, label = "次の曲",
            onClick = { viewModel.skipQuestion() }, modifier = Modifier.weight(1f)
        )
    }
}

@Composable
private fun RevealedBody(state: IntroDonGameUiState, viewModel: IntroDonGameViewModel) {
    val q = state.currentQuestion ?: return
    Column(
        modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
    ) {
        state.isCorrect?.let { correct ->
            val iconSize = with(LocalDensity.current) { 40.sp.toDp() }
            Icon(
                if (correct) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null,
                tint = if (correct) DS.success else DS.danger, modifier = Modifier.size(iconSize)
            )
        }

        ImasArtwork(title = q.title, brand = q.brandId, imageUrl = q.artworkUrl, size = 72.dp)

        ImasText(q.title, ImasTextRole.HERO_TITLE, textAlign = TextAlign.Center)

        IntroDonAnswerReveal(choices = q.choices, correctTitle = q.title, selectedTitle = state.selectedTitle)

        val isLast = state.currentIndex + 1 >= state.totalCount
        ImasButton(
            title = if (isLast) "結果を見る" else "次の問題へ",
            onClick = { viewModel.nextQuestion() },
            role = ImasButtonRole.PRIMARY,
            size = ImasButtonSize.LARGE,
            fillsWidth = true
        )
    }
}

// =============================================================================
// 結果 (iOS IntroGameResultView 相当。Android の他ゲームと同様、同画面に inline 表示)。
// =============================================================================

@Composable
private fun IntroDonResultBody(
    settings: IntroDonSettings,
    state: IntroDonGameUiState,
    onReplay: () -> Unit,
    onExit: () -> Unit
) {
    val answered = state.records.size
    val percentage = if (answered > 0) state.score * 100 / answered else 0
    // 結果カード (画像) のシェアシート。従来のテキストは画像に添える本文として残す。
    var showShareCard by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(DS.Space.gapLoose),
        verticalArrangement = Arrangement.spacedBy(DS.Space.section)
    ) {
        ImasCard {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(DS.Space.gap)
            ) {
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                    ImasMetric(value = "${state.score}", size = ImasNumeralSize.POSTER, emphasized = true)
                    ImasText("/ $answered", ImasTextRole.CARD_TITLE, color = QS.faint)
                }
                ImasText("正答率 $percentage%", ImasTextRole.ROW_LABEL, color = QS.dim)
                if (settings.mode == IntroDonMode.ALL_SONGS) {
                    val secs = (state.elapsedMs / 1000).toInt()
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
                        val iconSize = with(LocalDensity.current) { 14.sp.toDp() }
                        Icon(Icons.Filled.AccessTime, null, tint = QS.ink, modifier = Modifier.size(iconSize))
                        ImasText(String.format("%d:%02d", secs / 60, secs % 60), ImasTextRole.ROW_LABEL, color = QS.ink)
                    }
                }
                GradeBadge(percentage)
            }
        }

        if (state.newBestTime) {
            BestBanner("ベストタイム更新！", "NEW TIME")
        } else if (state.isNewBest) {
            BestBanner("ベストスコア更新！", "NEW BEST")
        }

        if (settings.mode != IntroDonMode.ALL_SONGS) {
            ImasSection(title = "全問の結果", style = ImasSectionHeaderStyle.SMALL) {
                ImasCardList(items = state.records.withIndex().toList(), key = { it.index }) { (index, record) ->
                    RecordRow(index, record)
                }
            }
        }

        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            ImasButton(title = "もう一度", onClick = onReplay, role = ImasButtonRole.PRIMARY, size = ImasButtonSize.LARGE, fillsWidth = true)
            ImasButton(
                title = "結果をシェア",
                onClick = { showShareCard = true },
                icon = Icons.Filled.Share,
                role = ImasButtonRole.SECONDARY,
                size = ImasButtonSize.LARGE,
                fillsWidth = true
            )
            ImasButton(title = "ホームに戻る", onClick = onExit, role = ImasButtonRole.PLAIN, size = ImasButtonSize.LARGE, fillsWidth = true)
        }
    }

    if (showShareCard) {
        val isAllSongs = settings.mode == IntroDonMode.ALL_SONGS
        val secs = (state.elapsedMs / 1000).toInt()
        IntroDonShareSheet(
            modeLabel = introDonModeLabel(settings),
            score = state.score,
            total = answered,
            percentage = percentage,
            // タイムを競うのは全曲チャレンジだけ。他モードは行ごと出さない。
            timeText = if (isAllSongs) String.format("%d:%02d", secs / 60, secs % 60) else null,
            bestCombo = state.bestCombo,
            // 全曲チャレンジは曲数が多すぎて内訳が無意味なのでサマリのみ。
            lines = if (isAllSongs) emptyList() else state.records.map { IntroShareLine(it.title, it.correct) },
            shareText = shareText(settings, state, answered),
            onDismiss = { showShareCard = false }
        )
    }
}

@Composable
private fun GradeBadge(percentage: Int) {
    val (label, color) = when {
        percentage == 100 -> "パーフェクト! 🎵" to DS.favorite
        percentage >= 80 -> "すごい！" to DS.success
        percentage >= 60 -> "なかなか！" to QS.ink
        percentage >= 40 -> "もう少し！" to DS.warning
        else -> "練習あるのみ！" to DS.danger
    }
    Row(
        modifier = Modifier
            .background(color.copy(alpha = 0.12f), RoundedCornerShape(DS.rSM))
            .padding(horizontal = DS.Space.section, vertical = DS.Space.gap)
    ) {
        ImasText(label, ImasTextRole.ROW_LABEL, color = color)
    }
}

@Composable
private fun BestBanner(text: String, tag: String) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(DS.favorite.copy(alpha = 0.10f), RoundedCornerShape(DS.rLG))
            .padding(horizontal = DS.Space.section, vertical = DS.Space.gapLoose),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val iconSize = with(LocalDensity.current) { 16.sp.toDp() }
        Icon(Icons.Filled.WorkspacePremium, null, tint = DS.favorite, modifier = Modifier.size(iconSize))
        ImasText(text, ImasTextRole.ROW_LABEL, color = QS.ink, modifier = Modifier.padding(start = DS.Space.gapLoose).weight(1f))
        ImasText(tag, ImasTextRole.BADGE, color = DS.favorite)
    }
}

@Composable
private fun RecordRow(index: Int, record: IntroDonAnswerRecord) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = DS.Space.rowH, vertical = DS.Space.gap),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)
    ) {
        ImasText("${index + 1}", ImasTextRole.META, color = QS.faint)
        val iconSize = with(LocalDensity.current) { 16.sp.toDp() }
        Icon(
            if (record.correct) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null,
            tint = if (record.correct) DS.success else DS.danger, modifier = Modifier.size(iconSize)
        )
        Column(Modifier.weight(1f)) {
            ImasText(record.title, ImasTextRole.ROW_LABEL, maxLines = 1)
            if (!record.correct) {
                ImasText(record.selectedTitle?.let { "回答: $it" } ?: "スキップ", ImasTextRole.META, color = QS.faint, maxLines = 1)
            }
        }
    }
}

/** シェア文とシェアカードで同じモード表記を使うための 1 箇所。 */
private fun introDonModeLabel(settings: IntroDonSettings): String = when (settings.mode) {
    IntroDonMode.ALL_SONGS -> "全曲チャレンジ"
    IntroDonMode.RUSH -> "ラッシュ ${settings.rushTimeLimitSec}秒"
    else -> "ノーマル"
}

/** 結果のシェア文。文面 (タイムの丸め・正答率・連続正解) はコアが作る (iOS と同じ)。 */
private fun shareText(settings: IntroDonSettings, state: IntroDonGameUiState, answered: Int): String =
    shareIntroDonText(
        IntroDonShareInput(
            mode = when (settings.mode) {
                IntroDonMode.NORMAL -> IntroDonShareMode.NORMAL
                IntroDonMode.RUSH -> IntroDonShareMode.RUSH
                IntroDonMode.ALL_SONGS -> IntroDonShareMode.ALL_SONGS
                IntroDonMode.PARTY -> IntroDonShareMode.PARTY
            },
            score = state.score,
            answered = answered,
            bestCombo = state.bestCombo,
            elapsedSeconds = state.elapsedMs / 1000.0,
            rushTimeLimitSeconds = settings.rushTimeLimitSec.toDouble()
        )
    )
