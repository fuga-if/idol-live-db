package com.fugaif.imaslivedb.ui.introdon

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Cancel
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Replay
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.AccessTime
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.WorkspacePremium
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
import androidx.compose.ui.graphics.Color
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
import coil3.compose.SubcomposeAsyncImage
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.share.IntroDonShareSheet
import com.fugaif.imaslivedb.ui.share.IntroShareLine
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

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
            val pool = songRepository.fetchIntroDonSongs(settings.selectedBrandIds)
            if (pool.size < 4) {
                _uiState.value = _uiState.value.copy(
                    phase = IntroDonPhase.LOADING,
                    errorMessage = "対象の曲が見つかりませんでした。ブランドを増やしてお試しください。"
                )
                return@launch
            }
            val count = if (isFast) pool.size else settings.questionCount
            val questions = buildIntroDonQuestions(pool, count)
            _uiState.value = IntroDonGameUiState(
                phase = IntroDonPhase.PLAYING,
                questions = questions,
                sessionStartMs = System.currentTimeMillis()
            )
            if (settings.mode == IntroDonMode.RUSH) startRushTimer()
            playCurrentQuestion()
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
        AudioPreviewManager.togglePreview(url, question.title)
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
        val newCombo = if (correct) s.combo + 1 else 0
        val records = s.records + IntroDonAnswerRecord(q.id, q.title, title, correct)
        val updated = s.copy(
            selectedTitle = title, isCorrect = correct,
            score = s.score + if (correct) 1 else 0,
            combo = newCombo, bestCombo = maxOf(s.bestCombo, newCombo),
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
        _uiState.value = s.copy(selectedTitle = null, isCorrect = false, combo = 0, records = records)
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

    Box(Modifier.fillMaxSize().background(DS.bg)) {
        Column(Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                IconButton(onClick = { showExitDialog = true }) {
                    Icon(Icons.Filled.Close, "終了", tint = DS.ink2)
                }
                Spacer(Modifier.width(0.dp))
            }

            when (state.phase) {
                IntroDonPhase.LOADING -> LoadingBody(state.errorMessage, onExit)
                IntroDonPhase.FINISHED -> IntroDonResultBody(settings, state, onReplay = { viewModel.restart() }, onExit = onExit)
                else -> GameBody(settings, state, viewModel)
            }
        }
    }

    if (showExitDialog) {
        AlertDialog(
            onDismissRequest = { showExitDialog = false },
            title = { Text("ゲームを終了しますか？") },
            confirmButton = { TextButton(onClick = { showExitDialog = false; onExit() }) { Text("終了") } },
            dismissButton = { TextButton(onClick = { showExitDialog = false }) { Text("キャンセル") } }
        )
    }
}

@Composable
private fun LoadingBody(errorMessage: String?, onExit: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
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
private fun GameBody(settings: IntroDonSettings, state: IntroDonGameUiState, viewModel: IntroDonGameViewModel) {
    val isRush = settings.mode == IntroDonMode.RUSH
    val isAllSongs = settings.mode == IntroDonMode.ALL_SONGS
    val isFast = settings.mode.isFast

    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        HeaderBar(settings, state)
        Spacer(Modifier.height(8.dp))
        val progress = if (isRush) {
            if (settings.rushTimeLimitSec > 0) state.rushRemainingMs.toFloat() / (settings.rushTimeLimitSec * 1000f) else 0f
        } else {
            if (state.totalCount > 0) state.currentIndex.toFloat() / state.totalCount else 0f
        }
        val progressColor = if (isRush && state.rushRemainingMs <= 10_000) DS.danger else introDonAccent()
        IntroDonProgressBar(progress = progress, color = progressColor)
        Spacer(Modifier.height(8.dp))

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
                color = if (urgent) DS.danger else introDonAccent()
            )
        } else {
            Pill(icon = null, text = "${state.currentIndex + 1} / ${state.totalCount}", color = DS.ink2, monochrome = true)
        }

        if (settings.mode == IntroDonMode.ALL_SONGS) {
            Spacer(Modifier.width(8.dp))
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

        Spacer(Modifier.weight(1f))

        if (state.combo >= 2) {
            val color = if (state.combo >= 8) DS.pick else if (state.combo >= 5) DS.favorite else introDonAccent()
            Pill(icon = Icons.Filled.LocalFireDepartment, text = "×${state.combo}", color = color)
            Spacer(Modifier.width(8.dp))
        }

        Pill(icon = Icons.Filled.CheckCircle, text = "${state.score}", color = DS.success)
    }
}

@Composable
private fun Pill(icon: androidx.compose.ui.graphics.vector.ImageVector?, text: String, color: Color, monochrome: Boolean = false) {
    Row(
        modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(if (monochrome) DS.surface else color.copy(alpha = 0.14f)).padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp)
    ) {
        if (icon != null) Icon(icon, null, tint = color, modifier = Modifier.size(12.dp))
        Text(text, fontSize = 14.sp, fontWeight = FontWeight.Black, color = if (monochrome) DS.ink2 else color)
    }
}

@Composable
private fun RoundBody(settings: IntroDonSettings, state: IntroDonGameUiState, viewModel: IntroDonGameViewModel, isFast: Boolean) {
    val showAnswer = isFast || state.phase == IntroDonPhase.ANSWERING
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(14.dp), modifier = Modifier.fillMaxWidth()) {
        IntroDonElapsedLabel(isRunning = state.isPlayingIntro, resetKey = state.playbackResetToken)

        if (isFast) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(
                    if (state.isPlayingIntro) Icons.Filled.MusicNote else Icons.Filled.MusicNote,
                    null, tint = DS.ink, modifier = Modifier.size(24.dp)
                )
                Text("曲名は？", fontSize = 13.sp, fontWeight = FontWeight.Black, letterSpacing = 2.sp, color = DS.ink2)
            }
        } else if (state.phase == IntroDonPhase.PLAYING) {
            IntroDonEqAnimation(isAnimating = state.isPlayingIntro)
        } else {
            Text("曲名を選んでください", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink2)
        }

        if (!isFast) {
            val canBuzz = state.phase == IntroDonPhase.PLAYING
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .clip(CircleShape)
                    .background(if (canBuzz) DS.ink else DS.surface)
                    .clickable(enabled = canBuzz) { viewModel.buzzToAnswer() },
                contentAlignment = Alignment.Center
            ) {
                Text("!", fontSize = 48.sp, fontWeight = FontWeight.Black, color = if (canBuzz) DS.bg else DS.ink3)
            }
            Text(
                if (state.phase == IntroDonPhase.PLAYING) "わかったらタップ" else "",
                fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2
            )
        }

        ControlsRow(state, viewModel)

        if (showAnswer) {
            state.currentQuestion?.let { q ->
                Column(
                    modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
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
    if (visible) IntroDonFlashOverlay(correct = correct)
}

@Composable
private fun ControlsRow(state: IntroDonGameUiState, viewModel: IntroDonGameViewModel) {
    var holding by remember { mutableStateOf(false) }
    Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
        ControlButton(icon = Icons.Filled.Replay, label = "もう一度") { viewModel.replayIntro() }

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(if (state.isPlayingIntro) introDonAccent() else DS.surface)
                    .clickable {
                        if (holding) return@clickable
                        viewModel.continueForDuration()
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    if (state.isPlayingIntro) Icons.Filled.MusicNote else Icons.Filled.PlayArrow,
                    null, tint = if (state.isPlayingIntro) DS.ink else introDonAccent(), modifier = Modifier.size(17.dp)
                )
            }
            Text(if (state.isPlayingIntro) "再生中" else "続きから", fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
        }

        ControlButton(icon = Icons.Filled.SkipNext, label = "次の曲") { viewModel.skipQuestion() }
    }
}

@Composable
private fun ControlButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(
            modifier = Modifier.size(46.dp).clip(CircleShape).background(DS.surface).clickable(onClick = onClick),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, tint = DS.ink2, modifier = Modifier.size(16.dp)) }
        Text(label, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, color = DS.ink3)
    }
}

@Composable
private fun RevealedBody(state: IntroDonGameUiState, viewModel: IntroDonGameViewModel) {
    val q = state.currentQuestion ?: return
    Column(
        modifier = Modifier.fillMaxWidth().verticalScroll(rememberScrollState()),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        state.isCorrect?.let { correct ->
            Icon(
                if (correct) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null,
                tint = if (correct) DS.success else DS.danger, modifier = Modifier.size(40.dp)
            )
        }

        if (q.artworkUrl != null) {
            SubcomposeAsyncImage(
                model = q.artworkUrl, contentDescription = q.title,
                modifier = Modifier.size(110.dp).clip(RoundedCornerShape(16.dp))
            )
        } else {
            Box(Modifier.size(110.dp).clip(RoundedCornerShape(16.dp)).background(DS.fill), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.MusicNote, null, tint = DS.ink3, modifier = Modifier.size(36.dp))
            }
        }

        Text(q.title, fontSize = 20.sp, fontWeight = FontWeight.Black, color = DS.ink, textAlign = TextAlign.Center)

        IntroDonAnswerReveal(choices = q.choices, correctTitle = q.title, selectedTitle = state.selectedTitle)

        val isLast = state.currentIndex + 1 >= state.totalCount
        IntroDonActionButton(title = if (isLast) "結果を見る" else "次の問題へ") { viewModel.nextQuestion() }
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
        modifier = Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Column(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(DS.surface).padding(28.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("${state.score}", fontSize = 52.sp, fontWeight = FontWeight.Black, color = DS.ink)
                Text("/ $answered", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink3)
            }
            Text("正答率 $percentage%", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink2)
            if (settings.mode == IntroDonMode.ALL_SONGS) {
                val secs = (state.elapsedMs / 1000).toInt()
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Icon(Icons.Filled.AccessTime, null, tint = DS.ink, modifier = Modifier.size(14.dp))
                    Text(String.format("%d:%02d", secs / 60, secs % 60), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                }
            }
            GradeBadge(percentage)
        }

        if (state.newBestTime) {
            BestBanner("ベストタイム更新！", "NEW TIME")
        } else if (state.isNewBest) {
            BestBanner("ベストスコア更新！", "NEW BEST")
        }

        if (settings.mode != IntroDonMode.ALL_SONGS) {
            IntroDonSectionLabel(text = "全問の結果")
            Column(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface),
            ) {
                state.records.forEachIndexed { index, record ->
                    if (index > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(DS.sep))
                    RecordRow(index, record)
                }
            }
        }

        IntroDonActionButton(title = "もう一度") { onReplay() }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(DS.surface)
                .clickable { showShareCard = true }
                .padding(vertical = 14.dp),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Filled.Share, null, tint = DS.ink, modifier = Modifier.size(15.dp))
            Text("結果をシェア", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink, modifier = Modifier.padding(start = 8.dp))
        }

        Row(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.surface).clickable(onClick = onExit).padding(vertical = 12.dp),
            horizontalArrangement = Arrangement.Center
        ) {
            Text("ホームに戻る", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
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
            shareText = shareText(settings, state, percentage, answered),
            onDismiss = { showShareCard = false }
        )
    }
}

@Composable
private fun GradeBadge(percentage: Int) {
    val (label, color) = when {
        percentage == 100 -> "パーフェクト! 🎵" to DS.favorite
        percentage >= 80 -> "すごい！" to DS.success
        percentage >= 60 -> "なかなか！" to introDonAccent()
        percentage >= 40 -> "もう少し！" to DS.warning
        else -> "練習あるのみ！" to DS.danger
    }
    Row(
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(color.copy(alpha = 0.12f)).padding(horizontal = 20.dp, vertical = 8.dp)
    ) {
        Text(label, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = color)
    }
}

@Composable
private fun BestBanner(text: String, tag: String) {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.favorite.copy(alpha = 0.10f)).padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(Icons.Filled.WorkspacePremium, null, tint = DS.favorite, modifier = Modifier.size(16.dp))
        Text(text, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink, modifier = Modifier.padding(start = 10.dp).weight(1f))
        Text(tag, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.5.sp, color = DS.favorite)
    }
}

@Composable
private fun RecordRow(index: Int, record: IntroDonAnswerRecord) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text("${index + 1}", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = DS.ink3, modifier = Modifier.width(22.dp))
        Icon(
            if (record.correct) Icons.Filled.CheckCircle else Icons.Filled.Cancel, null,
            tint = if (record.correct) DS.success else DS.danger, modifier = Modifier.size(16.dp)
        )
        Column(Modifier.weight(1f)) {
            Text(record.title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink, maxLines = 1)
            if (!record.correct) {
                Text(record.selectedTitle?.let { "回答: $it" } ?: "スキップ", fontSize = 11.sp, color = DS.ink3, maxLines = 1)
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

private fun shareText(settings: IntroDonSettings, state: IntroDonGameUiState, percentage: Int, answered: Int): String {
    val modeLabel = introDonModeLabel(settings)
    val base = if (settings.mode == IntroDonMode.ALL_SONGS) {
        val secs = (state.elapsedMs / 1000).toInt()
        "🎵イントロドン 全曲チャレンジ ${secs / 60}:${(secs % 60).toString().padStart(2, '0')}・正答率$percentage% (${state.score}/$answered)"
    } else {
        "🎵イントロドン($modeLabel)で ${state.score}/$answered 正解！(正答率$percentage%)"
    }
    val combo = if (state.bestCombo >= 2) " 最大${state.bestCombo}連続🔥" else ""
    return base + combo + "\n#イントロドン #アイマス"
}
