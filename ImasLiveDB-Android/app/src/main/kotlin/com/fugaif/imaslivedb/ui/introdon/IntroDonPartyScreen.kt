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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
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
import com.fugaif.imaslivedb.ui.designsystem.ImasMetric
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasNumeralSize
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import com.fugaif.imaslivedb.ui.theme.ImasTheme
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

    Box(Modifier.fillMaxSize().background(DS.bg)) {
        when (state.phase) {
            PartyPhase.LOADING -> LoadingOverlay(state.errorMessage, onExit)
            PartyPhase.FINISHED -> FinishedOverlay(state, onReplay = { viewModel.generateQuestions() }, onExit = onExit)
            else -> SplitLayout(state, viewModel)
        }

        IconButton(onClick = { showExitDialog = true }, modifier = Modifier.padding(DS.Space.gapTight)) {
            Icon(Icons.Filled.Close, "終了", tint = DS.ink2)
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
        state.phase == PartyPhase.BUZZED -> DS.bg
        state.phase == PartyPhase.REVEALED -> if (state.lastCorrect && state.lastAnswerer == index) DS.success.copy(alpha = 0.22f) else DS.surface
        // 押せない側 (脱落・出題前) は iOS と同じく、モードに関係なく暗い面にする。上に載る「OUT」と
        // プレイヤー名は白抜きなので、ライトの紙の面だと消える。DS で常に暗いのは電光掲示板の板。
        else -> if (buzzable) color else DS.board
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
                state.phase == PartyPhase.BUZZED -> ImasText("相手が回答中…", ImasTextRole.ROW_LABEL, color = DS.ink3)
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
            // 脱落時の地は常に暗い DS.board (iOS と同じ)。文字はその板の専用インク。
            Icon(Icons.Filled.Cancel, null, tint = DS.boardDim, modifier = Modifier.size(bigIconSize))
            ImasText("OUT", ImasTextRole.CARD_TITLE, color = DS.boardDim)
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
            ImasText("正解", ImasTextRole.META, color = DS.ink3)
            ImasText(q.title, ImasTextRole.ROW_LABEL, color = DS.ink, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

@Composable
private fun CenterStrip(state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    Column(
        modifier = Modifier.fillMaxWidth().height(DS.Size.touch * 3).background(DS.surface).padding(horizontal = DS.Space.rowGap),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
            ScoreChip(0, state)
            ImasText("${(state.currentIndex + 1).coerceAtMost(state.totalRounds)} / ${state.totalRounds}", ImasTextRole.META, color = DS.ink3)
            ScoreChip(1, state)
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
                color = DS.ink,
                modifier = Modifier.padding(top = DS.Space.gap)
            )
            else -> Row(
                horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = DS.Space.gap)
            ) {
                PlayButton(state, viewModel)
                ImasButton(title = "わからない", onClick = { viewModel.giveUp() }, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.SMALL)
            }
        }
    }
}

@Composable
private fun PlayButton(state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    val glyphSize = with(LocalDensity.current) { 15.sp.toDp() }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
        Box(
            modifier = Modifier
                .size(DS.Size.touch)
                .background(if (state.isPlayingIntro) DS.ink else DS.fill, CircleShape)
                .imasPress(onClick = { viewModel.replayIntro() }),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (state.isPlayingIntro) Icons.Filled.MusicNote else Icons.Filled.PlayArrow, null,
                tint = if (state.isPlayingIntro) DS.bg else DS.ink,
                modifier = Modifier.size(glyphSize)
            )
        }
        ImasText("タップでもう一度", ImasTextRole.META)
    }
}

@Composable
private fun ScoreChip(index: Int, state: IntroDonPartyUiState) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        Box(Modifier.size(DS.Space.gapLoose).background(hexToColor(partyPlayers[index].colorHex), CircleShape))
        ImasText(partyPlayers[index].name, ImasTextRole.SECTION_LABEL)
        ImasMetric(value = "${state.scores[index]}", size = ImasNumeralSize.MEDIUM, emphasized = true)
    }
}

@Composable
private fun FinishedOverlay(state: IntroDonPartyUiState, onReplay: () -> Unit, onExit: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = DS.Space.section),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(DS.Space.section, Alignment.CenterVertically)
    ) {
        val winner = state.winner
        if (winner != null) {
            ImasText("${partyPlayers[winner].name} の勝ち！", ImasTextRole.HERO_TITLE, color = hexToColor(partyPlayers[winner].colorHex))
        } else {
            ImasText("引き分け", ImasTextRole.HERO_TITLE)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(DS.Space.gapLoose), verticalAlignment = Alignment.Bottom) {
            FinalScore(0, state)
            ImasText("vs", ImasTextRole.ROW_SUBTITLE, color = DS.ink3)
            FinalScore(1, state)
        }
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap), modifier = Modifier.fillMaxWidth()) {
            ImasButton(title = "もう一度", onClick = onReplay, role = ImasButtonRole.PRIMARY, size = ImasButtonSize.LARGE, fillsWidth = true)
            ImasButton(title = "退出", onClick = onExit, role = ImasButtonRole.SECONDARY, size = ImasButtonSize.LARGE, fillsWidth = true)
        }
    }
}

@Composable
private fun FinalScore(index: Int, state: IntroDonPartyUiState) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(DS.Space.gapTight)) {
        ImasText(partyPlayers[index].name, ImasTextRole.ROW_SUBTITLE, color = hexToColor(partyPlayers[index].colorHex))
        ImasMetric(value = "${state.scores[index]}", size = ImasNumeralSize.LARGE, emphasized = true)
    }
}
