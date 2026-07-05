package com.fugaif.imaslivedb.ui.introdon

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

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
            val pool = songRepository.fetchIntroDonSongs(settings.selectedBrandIds)
            if (pool.size < 4) {
                _uiState.value = _uiState.value.copy(errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。")
                return@launch
            }
            val questions = buildIntroDonQuestions(pool, settings.questionCount)
            _uiState.value = IntroDonPartyUiState(phase = PartyPhase.PLAYING, questions = questions)
            playCurrentQuestion()
        }
    }

    private fun playCurrentQuestion() {
        playJob?.cancel()
        val q = _uiState.value.currentQuestion ?: return
        val url = q.previewUrl
        AudioPreviewManager.stop()
        if (url.isNullOrEmpty()) return
        AudioPreviewManager.togglePreview(url, q.title)
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

        IconButton(onClick = { showExitDialog = true }, modifier = Modifier.padding(8.dp)) {
            Icon(Icons.Filled.Close, "終了", tint = DS.ink2)
        }
    }

    if (showExitDialog) {
        AlertDialog(
            onDismissRequest = { showExitDialog = false },
            title = { Text("対戦を終了しますか？") },
            confirmButton = { TextButton(onClick = { showExitDialog = false; onExit() }) { Text("終了") } },
            dismissButton = { TextButton(onClick = { showExitDialog = false }) { Text("キャンセル") } }
        )
    }
}

@Composable
private fun LoadingOverlay(errorMessage: String?, onExit: () -> Unit) {
    Column(Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        if (errorMessage != null) {
            Text(errorMessage, color = DS.danger, fontSize = 14.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
            Spacer(Modifier.height(16.dp))
            TextButton(onClick = onExit) { Text("戻る") }
        } else {
            CircularProgressIndicator(color = DS.ink2)
            Spacer(Modifier.height(16.dp))
            Text("問題を生成中...", color = DS.ink2, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
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
        else -> if (buzzable) color else DS.surface
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
                state.phase == PartyPhase.BUZZED -> Text("相手が回答中…", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
                state.phase == PartyPhase.REVEALED -> RevealHalfContent(index, state)
                else -> BuzzContent(player, eliminated)
            }
        }
    }
}

@Composable
private fun BuzzContent(player: PartyPlayer, eliminated: Boolean) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (eliminated) {
            Icon(Icons.Filled.Cancel, null, tint = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.35f), modifier = Modifier.size(30.dp))
            Text("OUT", fontSize = 16.sp, fontWeight = FontWeight.Black, color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.4f))
        } else {
            Text(player.name, fontSize = 40.sp, fontWeight = FontWeight.Black, color = androidx.compose.ui.graphics.Color.White)
            Text("タップで早押し！", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = androidx.compose.ui.graphics.Color.White.copy(alpha = 0.85f))
        }
    }
}

@Composable
private fun AnswerChoices(index: Int, state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    val q = state.currentQuestion ?: return
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(horizontal = 20.dp)) {
        Text("${partyPlayers[index].name} 回答中", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.ink2)
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.height(120.dp)
        ) {
            items(q.choices) { title ->
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(DS.surface)
                        .clickable { viewModel.submitAnswer(index, title) }
                        .padding(horizontal = 6.dp, vertical = 14.dp),
                    contentAlignment = Alignment.Center
                ) {
                    Text(title, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = DS.ink, textAlign = TextAlign.Center, maxLines = 2)
                }
            }
        }
    }
}

@Composable
private fun RevealHalfContent(index: Int, state: IntroDonPartyUiState) {
    if (state.lastCorrect && state.lastAnswerer == index) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(Icons.Filled.CheckCircle, null, tint = DS.success, modifier = Modifier.size(28.dp))
            Text("正解！ +1", fontSize = 16.sp, fontWeight = FontWeight.Black, color = DS.success)
        }
    } else {
        val q = state.currentQuestion ?: return
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.padding(horizontal = 16.dp)) {
            Text("正解", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
            Text(q.title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

@Composable
private fun CenterStrip(state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    Column(
        modifier = Modifier.fillMaxWidth().height(132.dp).background(DS.surface).padding(horizontal = 12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            ScoreChip(0, state)
            Text("${(state.currentIndex + 1).coerceAtMost(state.totalRounds)} / ${state.totalRounds}", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
            ScoreChip(1, state)
        }
        Spacer(Modifier.height(8.dp))
        when (state.phase) {
            PartyPhase.REVEALED -> {
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(10.dp))
                        .background(introDonAccent())
                        .clickable { viewModel.nextRound() }
                        .padding(horizontal = 22.dp, vertical = 10.dp)
                ) {
                    val isLast = state.currentIndex + 1 >= state.totalRounds
                    Text(if (isLast) "結果を見る" else "次のラウンドへ", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = androidx.compose.ui.graphics.Color.White)
                }
            }
            PartyPhase.BUZZED -> Text("早押し成立！回答してください", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = introDonAccent())
            else -> Row(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalAlignment = Alignment.CenterVertically) {
                PlayButton(state, viewModel)
                Box(
                    modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(DS.fill).clickable { viewModel.giveUp() }.padding(horizontal = 14.dp, vertical = 9.dp)
                ) { Text("わからない", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3) }
            }
        }
    }
}

@Composable
private fun PlayButton(state: IntroDonPartyUiState, viewModel: IntroDonPartyViewModel) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .clip(CircleShape)
                .background(if (state.isPlayingIntro) introDonAccent() else DS.fill)
                .clickable { viewModel.replayIntro() },
            contentAlignment = Alignment.Center
        ) {
            Icon(
                if (state.isPlayingIntro) Icons.Filled.MusicNote else Icons.Filled.PlayArrow, null,
                tint = if (state.isPlayingIntro) DS.ink else introDonAccent(), modifier = Modifier.size(15.dp)
            )
        }
        Text("タップでもう一度", fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
    }
}

@Composable
private fun ScoreChip(index: Int, state: IntroDonPartyUiState) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Box(Modifier.size(10.dp).clip(CircleShape).background(hexToColor(partyPlayers[index].colorHex)))
        Text(partyPlayers[index].name, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = DS.ink2)
        Text("${state.scores[index]}", fontSize = 18.sp, fontWeight = FontWeight.Black, color = DS.ink)
    }
}

@Composable
private fun FinishedOverlay(state: IntroDonPartyUiState, onReplay: () -> Unit, onExit: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().padding(horizontal = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        val winner = state.winner
        if (winner != null) {
            Text("${partyPlayers[winner].name} の勝ち！", fontSize = 28.sp, fontWeight = FontWeight.Black, color = hexToColor(partyPlayers[winner].colorHex))
        } else {
            Text("引き分け", fontSize = 28.sp, fontWeight = FontWeight.Black, color = DS.ink)
        }
        Spacer(Modifier.height(20.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(24.dp), verticalAlignment = Alignment.Bottom) {
            FinalScore(0, state)
            Text("vs", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
            FinalScore(1, state)
        }
        Spacer(Modifier.height(24.dp))
        IntroDonActionButton(title = "もう一度") { onReplay() }
        Spacer(Modifier.height(10.dp))
        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.surface).clickable(onClick = onExit).padding(vertical = 13.dp),
            horizontalArrangement = Arrangement.Center
        ) { Text("退出", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2) }
    }
}

@Composable
private fun FinalScore(index: Int, state: IntroDonPartyUiState) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(partyPlayers[index].name, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = hexToColor(partyPlayers[index].colorHex))
        Text("${state.scores[index]}", fontSize = 44.sp, fontWeight = FontWeight.Black, color = DS.ink)
    }
}
