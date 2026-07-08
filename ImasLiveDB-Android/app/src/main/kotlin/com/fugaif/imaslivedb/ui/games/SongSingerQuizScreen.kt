package com.fugaif.imaslivedb.ui.games

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.PlayCircle
import androidx.compose.material.icons.filled.Photo
import androidx.compose.material.icons.filled.QuestionMark
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
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
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.repository.IdolRepository
import com.fugaif.imaslivedb.data.repository.SongRepository
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.player.AudioPreviewManager
import com.fugaif.imaslivedb.ui.components.ArtworkImage
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasEmptyState
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// =============================================================================
// ソロ曲クイズ (ヒント式段階採点)。iOS SongSingerQuizView の移植。
// 最初は「曲名だけ」で出題し、ヒントを開くほど手がかりが増える代わりに獲得点が下がる:
// 曲名だけで正解=3pt / ジャケットを見る=2pt / プレビュー再生=1pt。
// =============================================================================

private const val SESSION_LENGTH = 10

data class SongQuestion(val song: Song, val answer: Idol, val choices: List<Idol>)

/** ソロ曲 (song_type='solo') と原唱歌手の対応 (原唱が単独の曲のみ、外部/対象外ブランドを除く)。 */
suspend fun resolveSoloSingerPairs(
    idolRepository: IdolRepository,
    songRepository: SongRepository,
    selectedBrandIds: Set<String>
): List<Pair<Song, Idol>> {
    val rows = songRepository.fetchSoloOriginalSingers()
    val singleSingerBySong = rows.groupBy { it.songId }.filterValues { it.size == 1 }.mapValues { it.value.first().idolId }
    if (singleSingerBySong.isEmpty()) return emptyList()

    val idolById = idolRepository.fetchIdols().associateBy { it.id }
    val songIds = singleSingerBySong.keys.toList()
    val songById = songRepository.fetchSongsByIds(songIds).associateBy { it.id }

    return singleSingerBySong.mapNotNull { (songId, idolId) ->
        val song = songById[songId] ?: return@mapNotNull null
        val singer = idolById[idolId] ?: return@mapNotNull null
        if (singer.brandId == "other") return@mapNotNull null
        if (selectedBrandIds.isNotEmpty() && !selectedBrandIds.contains(singer.brandId)) return@mapNotNull null
        song to singer
    }
}

data class SongSingerQuizUiState(
    val isLoading: Boolean = true,
    val pool: List<Pair<Song, Idol>> = emptyList(),
    val idolPool: List<Idol> = emptyList(),
    val question: SongQuestion? = null,
    val selectedId: String? = null,
    val revealed: Int = 0,
    val points: Int = 0,
    val correct: Int = 0,
    val asked: Int = 0,
    val history: List<QuizHistoryItem> = emptyList(),
    val sessionDone: Boolean = false,
    val isNewBest: Boolean = false
)

class SongSingerQuizViewModel(app: Application, private val selectedBrandIds: Set<String>) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val songRepository = AppModule.from(app).songRepository
    private val progressStore = AppModule.from(app).gameProgressStore

    private val _uiState = MutableStateFlow(SongSingerQuizUiState())
    val uiState: StateFlow<SongSingerQuizUiState> = _uiState.asStateFlow()

    private var seenSongIds: Set<String> = emptySet()

    init {
        viewModelScope.launch {
            val pool = resolveSoloSingerPairs(idolRepository, songRepository, selectedBrandIds)
            val idolPool = pool.map { it.second }.distinctBy { it.id }
            _uiState.value = _uiState.value.copy(
                isLoading = false, pool = pool, idolPool = idolPool, question = makeQuestion(pool, idolPool)
            )
        }
    }

    private fun makeQuestion(pool: List<Pair<Song, Idol>>, idolPool: List<Idol>): SongQuestion? {
        if (pool.size < 4) return null
        var candidates = pool.filter { !seenSongIds.contains(it.first.id) }
        if (candidates.isEmpty()) {
            seenSongIds = emptySet()
            candidates = pool
        }
        val entry = candidates.randomOrNull() ?: return null
        seenSongIds = seenSongIds + entry.first.id
        val answer = entry.second
        val choices = (quizDistractors(idolPool, answer) + answer).shuffled()
        return SongQuestion(entry.first, answer, choices)
    }

    fun revealArtwork() { _uiState.value = _uiState.value.copy(revealed = 1) }
    fun revealPreview() {
        val s = _uiState.value
        _uiState.value = s.copy(revealed = 2)
        s.question?.song?.previewUrl?.takeIf { it.isNotEmpty() }?.let {
            AudioPreviewManager.togglePreview(it, s.question.song.title)
        }
    }

    fun pick(idol: Idol) {
        val s = _uiState.value
        val q = s.question ?: return
        if (s.selectedId != null) return
        AudioPreviewManager.stop()
        val isCorrect = idol.id == q.answer.id
        val earned = if (isCorrect) QuizScoring.points(s.revealed) else 0
        val history = s.history + QuizHistoryItem(
            id = "${s.asked + 1}-${q.song.id}", index = s.asked + 1,
            subjectTitle = q.song.title, subjectSubtitle = q.song.cdTitle,
            answer = q.answer, picked = idol, earnedPoints = earned, revealedHints = s.revealed
        )
        _uiState.value = s.copy(
            selectedId = idol.id, asked = s.asked + 1,
            correct = s.correct + if (isCorrect) 1 else 0,
            points = s.points + earned, history = history
        )
    }

    fun nextQuestion() {
        AudioPreviewManager.stop()
        val s = _uiState.value
        _uiState.value = s.copy(selectedId = null, revealed = 0, question = makeQuestion(s.pool, s.idolPool))
    }

    fun finish() {
        val s = _uiState.value
        val outOf = QuizScoring.sessionMax(s.asked)
        val before = progressStore.record(GameKind.songSingerQuiz)
        val beforeRate = if (before.bestOutOf > 0) before.bestScore.toDouble() / before.bestOutOf else -1.0
        val newRate = if (outOf > 0) s.points.toDouble() / outOf else 0.0
        val isNewBest = before.hasPlayed && newRate > beforeRate
        _uiState.value = s.copy(sessionDone = true, isNewBest = isNewBest)
        progressStore.recordResult(GameKind.songSingerQuiz, score = s.points, outOf = outOf)
    }

    fun restart() {
        AudioPreviewManager.stop()
        val s = _uiState.value
        seenSongIds = emptySet()
        _uiState.value = SongSingerQuizUiState(
            isLoading = false, pool = s.pool, idolPool = s.idolPool, question = makeQuestion(s.pool, s.idolPool)
        )
    }

    class Factory(private val app: Application, private val selectedBrandIds: Set<String>) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            SongSingerQuizViewModel(app, selectedBrandIds) as T
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongSingerQuizScreen(
    selectedBrandIds: Set<String>,
    onBack: () -> Unit,
    viewModel: SongSingerQuizViewModel = viewModel(
        factory = SongSingerQuizViewModel.Factory(
            LocalContext.current.applicationContext as Application, selectedBrandIds
        )
    )
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    DisposableEffect(Unit) { onDispose { AudioPreviewManager.stop() } }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("ソロ曲クイズ", fontWeight = FontWeight.Bold) },
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
                state.sessionDone -> QuizResultView(
                    points = state.points, maxPoints = QuizScoring.sessionMax(state.asked),
                    correct = state.correct, questions = state.asked, kind = GameKind.songSingerQuiz,
                    isNewBest = state.isNewBest, history = state.history, onReplay = { viewModel.restart() }
                )
                state.question != null -> {
                    val q = state.question!!
                    QuizProgressHeader(
                        current = minOf(state.asked + if (state.selectedId != null) 0 else 1, SESSION_LENGTH),
                        total = SESSION_LENGTH, points = state.points
                    )
                    SongCard(q, state)
                    if (state.selectedId == null) SongHintArea(q, state, viewModel)
                    IdolChoiceGrid(choices = q.choices, answer = q.answer, selectedId = state.selectedId) { idol, _ ->
                        viewModel.pick(idol)
                    }
                    if (state.selectedId != null) {
                        QuizNextButton(isLastQuestion = state.asked >= SESSION_LENGTH, onNext = { viewModel.nextQuestion() }, onFinish = { viewModel.finish() })
                    }
                }
                else -> ImasEmptyState(icon = Icons.Filled.MusicNote, title = "出題できるソロ曲が不足しています")
            }
        }
    }
}

@Composable
private fun SongCard(q: SongQuestion, state: SongSingerQuizUiState) {
    val answered = state.selectedId != null
    val showArtwork = answered || state.revealed >= 1
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (!answered) QuizValueBadge(revealed = state.revealed)
        if (showArtwork) {
            ArtworkImage(
                url = q.song.artworkUrl, size = 132.dp,
                previewUrl = if (answered || state.revealed >= 2) q.song.previewUrl else null,
                songTitle = q.song.title
            )
        } else {
            Box(
                modifier = Modifier.size(132.dp).clip(RoundedCornerShape(16.dp)).background(DS.fill),
                contentAlignment = Alignment.Center
            ) { Icon(Icons.Filled.QuestionMark, null, tint = DS.ink3, modifier = Modifier.size(44.dp)) }
        }
        Text(q.song.title, fontSize = 20.sp, fontWeight = FontWeight.Bold, color = DS.ink, textAlign = TextAlign.Center)
        q.song.cdTitle?.takeIf { it.isNotEmpty() }?.let { Text(it, fontSize = 12.sp, color = DS.ink3) }
        if (answered) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ImasAvatar(label = q.answer.name, seed = q.answer.color, brand = q.answer.brandId, size = 28.dp)
                Text("正解: ${q.answer.name}", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            }
        }
    }
}

@Composable
private fun SongHintArea(q: SongQuestion, state: SongSingerQuizUiState, viewModel: SongSingerQuizViewModel) {
    val hasPreview = !q.song.previewUrl.isNullOrEmpty()
    when {
        state.revealed == 0 -> QuizHintButton(
            icon = Icons.Filled.Photo, title = "ヒント: ジャケットを見る", nextValue = QuizScoring.points(1)
        ) { viewModel.revealArtwork() }
        state.revealed == 1 && hasPreview -> QuizHintButton(
            icon = Icons.Filled.PlayCircle, title = "ヒント: プレビューを再生する", nextValue = QuizScoring.points(2)
        ) { viewModel.revealPreview() }
    }
}
