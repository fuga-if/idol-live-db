package com.fugaif.imaslivedb.ui.introdon

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
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasConfirmDestructive
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyState
import com.fugaif.imaslivedb.ui.designsystem.ImasEmptyStateKind
import com.fugaif.imaslivedb.ui.designsystem.ImasLoadingState
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePlaybackControl
import com.fugaif.imaslivedb.ui.designsystem.ImasStagePlaybackStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasStageScoreChip
import com.fugaif.imaslivedb.ui.designsystem.ImasStageVersusPlayer
import com.fugaif.imaslivedb.ui.designsystem.ImasStageVersusResult
import com.fugaif.imaslivedb.ui.navigation.BottomBarVisibility
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasAlwaysDark
import com.fugaif.imaslivedb.ui.theme.ImasDarkNavigationBar
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasTheme
import com.fugaif.imaslivedb.ui.theme.QS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import com.fugaif.imaslivedb.ui.theme.imasPress
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.IntroSessionKind
import uniffi.imas_core.introQuestionCount
import androidx.compose.foundation.layout.systemBarsPadding

// =============================================================================
// パーティ対戦 (1台2人・分割画面・早押し)。iOS IntroPartySession + IntroPartyGameView の移植。
// =============================================================================

enum class PartyPhase { LOADING, PLAYING, BUZZED, REVEALED, FINISHED }

private data class PartyPlayer(val name: String, val colorHex: String)

private val partyPlayers = listOf(PartyPlayer("1P", "3B82F6"), PartyPlayer("2P", "EC4899"))

data class IntroDonPartyUiState(
    val phase: PartyPhase = PartyPhase.LOADING,
    val questions: List<IntroDonQuestion> = emptyList(),
    val currentIndex: Int = 0,
    val scores: List<Int> = listOf(0, 0),
    val buzzedPlayer: Int? = null,
    val eliminatedThisRound: Set<Int> = emptySet(),
    val lastAnswerer: Int? = null,
    val lastCorrect: Boolean = false,
    val isPlayingIntro: Boolean = false,
    val errorMessage: String? = null
) {
    val currentQuestion: IntroDonQuestion? get() = questions.getOrNull(currentIndex)
    val totalRounds: Int get() = questions.size
    val winner: Int? get() = if (scores[0] == scores[1]) null else if (scores[0] > scores[1]) 0 else 1
}

class IntroDonPartyViewModel(app: Application, private val settings: IntroDonSettings) : AndroidViewModel(app) {
    private val songRepository = AppModule.from(app).songRepository

    private val _uiState = MutableStateFlow(IntroDonPartyUiState())
    val uiState: StateFlow<IntroDonPartyUiState> = _uiState.asStateFlow()

    private var playJob: Job? = null
    private var advanceJob: Job? = null

    init {
        viewModelScope.launch {
            AudioPreviewManager.playbackState.collect { st ->
                _uiState.value = _uiState.value.copy(isPlayingIntro = st.isPlaying)
            }
        }
        generateQuestions()
    }

    fun generateQuestions() {
        viewModelScope.launch {
            _uiState.value = IntroDonPartyUiState(phase = PartyPhase.LOADING)
            try {
                val pool = songRepository.fetchIntroDonSongs(settings.selectedBrandIds)
                // 始められるか (4 曲の門) と何問出すかはコア。
                val count = introQuestionCount(IntroSessionKind.STANDARD, pool.size.toUInt(), settings.questionCount.toUInt())
                if (count == null) {
                    _uiState.value = _uiState.value.copy(errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。")
                    return@launch
                }
                val questions = buildIntroDonQuestions(pool, count.toInt())
                _uiState.value = IntroDonPartyUiState(phase = PartyPhase.PLAYING, questions = questions)
                playCurrentQuestion()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // 失敗しても「問題を生成中…」のまま止まらないようにする。
                _uiState.value = _uiState.value.copy(errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。")
            }
        }
    }

    private fun playCurrentQuestion() {
        playJob?.cancel()
        val q = _uiState.value.currentQuestion ?: return
        val url = q.previewUrl
        AudioPreviewManager.stop()
        if (url.isNullOrEmpty()) return
        AudioPreviewManager.togglePreview(url, q.id)
        playJob = viewModelScope.launch {
            delay(settings.introDurationMs)
            // 再生が終わっても .playing のまま早押しを受け付ける (本家準拠)。停止のみ行う。
            AudioPreviewManager.stop()
        }
    }

    fun buzz(player: Int) {
        val s = _uiState.value
        if (s.phase != PartyPhase.PLAYING) return
        if (s.buzzedPlayer != null || s.eliminatedThisRound.contains(player)) return
        playJob?.cancel()
        AudioPreviewManager.stop()
        _uiState.value = s.copy(buzzedPlayer = player, phase = PartyPhase.BUZZED)
    }

    fun submitAnswer(player: Int, title: String) {
        val s = _uiState.value
        val q = s.currentQuestion ?: return
        if (s.phase != PartyPhase.BUZZED || s.buzzedPlayer != player) return
        if (title == q.title) {
            val scores = s.scores.toMutableList().also { it[player] = it[player] + 1 }
            _uiState.value = s.copy(scores = scores, lastAnswerer = player, lastCorrect = true, phase = PartyPhase.REVEALED)
            scheduleNext()
        } else {
            val eliminated = s.eliminatedThisRound + player
            if (eliminated.size >= partyPlayers.size) {
                _uiState.value = s.copy(eliminatedThisRound = eliminated, buzzedPlayer = null, lastAnswerer = player, lastCorrect = false, phase = PartyPhase.REVEALED)
                scheduleNext()
            } else {
                _uiState.value = s.copy(eliminatedThisRound = eliminated, buzzedPlayer = null, lastAnswerer = player, lastCorrect = false, phase = PartyPhase.PLAYING)
                playCurrentQuestion()
            }
        }
    }

    fun giveUp() {
        val s = _uiState.value
        if (s.phase != PartyPhase.PLAYING && s.phase != PartyPhase.BUZZED) return
        playJob?.cancel()
        AudioPreviewManager.stop()
        _uiState.value = s.copy(buzzedPlayer = null, lastAnswerer = null, lastCorrect = false, phase = PartyPhase.REVEALED)
        scheduleNext()
    }

    fun replayIntro() {
        playCurrentQuestion()
    }

    fun continueHeld() {
        playJob?.cancel()
        AudioPreviewManager.resume()
    }

    fun pauseHeld() {
        AudioPreviewManager.pause()
    }

    private fun scheduleNext() {
        advanceJob?.cancel()
        advanceJob = viewModelScope.launch {
            delay(3_000)
            nextRound()
        }
    }

    fun nextRound() {
        advanceJob?.cancel()
        val s = _uiState.value
        if (s.phase != PartyPhase.REVEALED) return
        val next = s.currentIndex + 1
        if (next >= s.questions.size) {
            playJob?.cancel()
            AudioPreviewManager.stop()
            _uiState.value = s.copy(phase = PartyPhase.FINISHED)
        } else {
            _uiState.value = s.copy(
                currentIndex = next, buzzedPlayer = null, eliminatedThisRound = emptySet(),
                lastAnswerer = null, lastCorrect = false, phase = PartyPhase.PLAYING
            )
            playCurrentQuestion()
        }
    }

    fun stopAndCleanup() {
        playJob?.cancel()
        advanceJob?.cancel()
        AudioPreviewManager.stop()
    }

    override fun onCleared() {
        stopAndCleanup()
        super.onCleared()
    }

    class Factory(private val app: Application, private val settings: IntroDonSettings) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IntroDonPartyViewModel(app, settings) as T
    }
}

@Composable
fun IntroDonPartyScreen(
    settings: IntroDonSettings,
    onExit: () -> Unit,
    viewModel: IntroDonPartyViewModel = viewModel(
        factory = IntroDonPartyViewModel.Factory(LocalContext.current.applicationContext as Application, settings)
    )
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    var showExitDialog by remember { mutableStateOf(false) }

    DisposableEffect(Unit) { onDispose { viewModel.stopAndCleanup() } }

    // 対戦中もソロ戦と同じく、ライト/ダークで反転しない暗いステージに固定する
    // (docs/DESIGN_SYSTEM.md §12。iOS `IntroPartyGameView` と同じ組み方)。
    BottomBarVisibility.Hide()
    ImasDarkNavigationBar()
    ImasAlwaysDark {
        // 地は画面の端まで敷き、中身はシステムバー (上のステータスバー・下のナビゲーションバー) を避ける。
        Box(Modifier.fillMaxSize().background(QS.bg).systemBarsPadding()) {
            when (state.phase) {
                PartyPhase.LOADING -> LoadingOverlay(state.errorMessage, onExit)
                PartyPhase.FINISHED -> FinishedOverlay(state, onReplay = { viewModel.generateQuestions() }, onExit = onExit)
                else -> SplitLayout(state, viewModel)
            }

            IconButton(onClick = { showExitDialog = true }, modifier = Modifier.padding(DS.Space.gapTight)) {
                Icon(Icons.Filled.Close, "終了", tint = QS.dim)
            }
        }

        ImasConfirmDestructive(
            title = "対戦を終了しますか？",
            isPresented = showExitDialog,
            onDismiss = { showExitDialog = false },
            onConfirm = onExit,
            actionTitle = "終了"
        )
    }
}

@Composable
private fun LoadingOverlay(errorMessage: String?, onExit: () -> Unit) {
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
private fun SplitLayout(state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    Column(Modifier.fillMaxSize()) {
        PlayerHalf(index = 1, rotationDeg = 180f, state = state, viewModel = viewModel, modifier = Modifier.weight(1f).fillMaxWidth())
        CenterStrip(state, viewModel)
        PlayerHalf(index = 0, rotationDeg = 0f, state = state, viewModel = viewModel, modifier = Modifier.weight(1f).fillMaxWidth())
    }
}

@Composable
private fun PlayerHalf(index: Int, rotationDeg: Float, state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel, modifier: Modifier) {
    val player = partyPlayers[index]
    val color = hexToColor(player.colorHex)
    val eliminated = state.eliminatedThisRound.contains(index)
    val buzzable = state.phase == PartyPhase.PLAYING && !eliminated

    val bg = when {
        state.phase == PartyPhase.BUZZED && state.buzzedPlayer == index -> color.copy(alpha = 0.18f)
        state.phase == PartyPhase.BUZZED -> QS.bg
        state.phase == PartyPhase.REVEALED -> if (state.lastCorrect && state.lastAnswerer == index) DS.success.copy(alpha = 0.22f) else QS.panel
        // 押せない側 (脱落・出題前) は iOS と同じく、常に暗いステージの面にする。上に載る「OUT」と
        // プレイヤー名は白抜きなので、紙の面だと消える。
        else -> if (buzzable) color else QS.raised
    }

    Box(
        modifier = modifier
            .background(bg)
            .clickable(enabled = buzzable) { viewModel.buzz(index) },
        contentAlignment = Alignment.Center
    ) {
        Box(Modifier.graphicsLayer(rotationZ = rotationDeg)) {
            when {
                state.phase == PartyPhase.BUZZED && state.buzzedPlayer == index -> AnswerChoices(index, state, viewModel)
                state.phase == PartyPhase.BUZZED -> ImasText("相手が回答中…", ImasTextRole.ROW_LABEL, color = QS.faint)
                state.phase == PartyPhase.REVEALED -> RevealHalfContent(index, state)
                else -> BuzzContent(player, color, eliminated)
            }
        }
    }
}

@Composable
private fun BuzzContent(player: PartyPlayer, backgroundColor: androidx.compose.ui.graphics.Color, eliminated: Boolean) {
    val bigIconSize = with(LocalDensity.current) { 30.sp.toDp() }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        if (eliminated) {
            // 脱落時の地は常に暗いステージの面 (iOS と同じ)。文字はその上の控えめなインク。
            Icon(Icons.Filled.Cancel, null, tint = QS.dim, modifier = Modifier.size(bigIconSize))
            ImasText("OUT", ImasTextRole.CARD_TITLE, color = QS.dim)
        } else {
            val onColor = ImasTheme.onColor(backgroundColor)
            ImasText(player.name, ImasTextRole.HERO_TITLE, color = onColor)
            ImasText("タップで早押し！", ImasTextRole.ROW_LABEL, color = onColor)
        }
    }
}

@Composable
private fun AnswerChoices(index: Int, state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    val q = state.currentQuestion ?: return
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
        modifier = Modifier.padding(horizontal = DS.Space.screen)
    ) {
        ImasText("${partyPlayers[index].name} 回答中", ImasTextRole.SECTION_LABEL)
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(DS.Space.gap),
            verticalArrangement = Arrangement.spacedBy(DS.Space.gap),
            modifier = Modifier.height(DS.Size.touch * 3)
        ) {
            items(q.choices) { title ->
                ImasCard(
                    modifier = Modifier.fillMaxWidth().imasPress(onClick = { viewModel.submitAnswer(index, title) }),
                    padding = DS.Space.gap
                ) {
                    ImasText(title, ImasTextRole.ROW_LABEL, textAlign = TextAlign.Center, maxLines = 2, modifier = Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun RevealHalfContent(index: Int, state: IntroDonPartyUiState) {
    if (state.lastCorrect && state.lastAnswerer == index) {
        val iconSize = with(LocalDensity.current) { 28.sp.toDp() }
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
            Icon(Icons.Filled.CheckCircle, null, tint = DS.success, modifier = Modifier.size(iconSize))
            ImasText("正解！ +1", ImasTextRole.CARD_TITLE, color = DS.success)
        }
    } else {
        val q = state.currentQuestion ?: return
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight),
            modifier = Modifier.padding(horizontal = DS.Space.rowH)
        ) {
            ImasText("正解", ImasTextRole.META, color = QS.faint)
            ImasText(q.title, ImasTextRole.ROW_LABEL, color = QS.ink, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

@Composable
private fun CenterStrip(state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    Column(
        modifier = Modifier.fillMaxWidth().height(DS.Size.touch * 3).background(QS.panel).padding(horizontal = DS.Space.rowGap),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
            ImasStageScoreChip(colorHex = partyPlayers[0].colorHex, name = partyPlayers[0].name, score = state.scores[0])
            ImasText("${(state.currentIndex + 1).coerceAtMost(state.totalRounds)} / ${state.totalRounds}", ImasTextRole.META, color = QS.faint)
            ImasStageScoreChip(colorHex = partyPlayers[1].colorHex, name = partyPlayers[1].name, score = state.scores[1])
        }
        when (state.phase) {
            PartyPhase.REVEALED -> {
                val isLast = state.currentIndex + 1 >= state.totalRounds
                ImasButton(
                    title = if (isLast) "結果を見る" else "次のラウンドへ",
                    onClick = { viewModel.nextRound() },
                    role = ImasButtonRole.PRIMARY,
                    size = ImasButtonSize.SMALL,
                    modifier = Modifier.padding(top = DS.Space.gap)
                )
            }
            PartyPhase.BUZZED -> ImasText(
                "早押し成立！回答してください",
                ImasTextRole.ROW_SUBTITLE,
                color = QS.ink,
                modifier = Modifier.padding(top = DS.Space.gap)
            )
            else -> Row(
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = DS.Space.gap)
            ) {
                // タップ = 頭から再生、長押し = 流し続ける (iOS `playButton` と同じ ImasStagePlaybackControl)。
                ImasStagePlaybackControl(
                    isPlaying = state.isPlayingIntro,
                    style = ImasStagePlaybackStyle.CIRCLE,
                    pausedLabel = "頭から再生",
                    accessibilityHintText = "タップで頭から再生します。長押しの間は流し続けます",
                    onTap = { viewModel.replayIntro() },
                    onHoldBegin = { viewModel.continueHeld() },
                    onHoldEnd = { viewModel.pauseHeld() }
                )
                ImasButton(title = "わからない", onClick = { viewModel.giveUp() }, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL)
            }
        }
    }
}

@Composable
private fun FinishedOverlay(state: IntroDonPartyUiState, onReplay: () -> Unit, onExit: () -> Unit) {
    val winner = state.winner
    ImasStageVersusResult(
        winnerColorHex = winner?.let { partyPlayers[it].colorHex },
        headline = winner?.let { "${partyPlayers[it].name} の勝ち！" } ?: "引き分け",
        players = ImasStageVersusPlayer(partyPlayers[0].name, partyPlayers[0].colorHex, state.scores[0]) to
            ImasStageVersusPlayer(partyPlayers[1].name, partyPlayers[1].colorHex, state.scores[1])
    ) {
        ImasButton(title = "もう一度", onClick = onReplay, role = ImasButtonRole.PRIMARY, size = ImasButtonSize.LARGE, fillsWidth = true)
        ImasButton(title = "退出", onClick = onExit, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.LARGE, fillsWidth = true)
    }
}
