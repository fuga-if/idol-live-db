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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// =============================================================================
// アイドル当てクイズ。iOS IdolQuizView の移植。
// シルエット + 曖昧なプロフィール1項目から出題し、開くヒントを選ぶ戦略性を持つ。
// 素点は 10pt、ヒントを開くごとに獲得点が下がる (メンバーカラーは -2pt)。
// 備考: Android の Idol モデルには声優 (CV) フィールドが無いため、CV ヒントは提供しない
// (iOS はここに声優未発表チェックを含むが、データが無いため割愛)。
// =============================================================================

private const val SESSION_LENGTH = 10
private const val BASE_POINTS = 10

data class Fact(val label: String, val value: String, val cost: Int)
data class Question(val answer: Idol, val choices: List<Idol>, val facts: List<Fact>)

data class IdolQuizUiState(
    val isLoading: Boolean = true,
    val pool: List<Idol> = emptyList(),
    val question: Question? = null,
    val selectedId: String? = null,
    val opened: Set<Int> = emptySet(),
    val points: Int = 0,
    val correct: Int = 0,
    val asked: Int = 0,
    val history: List<QuizHistoryItem> = emptyList(),
    val sessionDone: Boolean = false,
    val isNewBest: Boolean = false
)

class IdolQuizViewModel(app: Application, private val selectedBrandIds: Set<String>) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val progressStore = AppModule.from(app).gameProgressStore

    private val _uiState = MutableStateFlow(IdolQuizUiState())
    val uiState: StateFlow<IdolQuizUiState> = _uiState.asStateFlow()

    private var seenIds: Set<String> = emptySet()

    init {
        viewModelScope.launch {
            val all = idolRepository.fetchIdols()
            val pool = all.filter { idol ->
                val brandMatch = selectedBrandIds.isEmpty() || selectedBrandIds.contains(idol.brandId)
                idol.brandId != "other" && !idol.color.isNullOrEmpty() && facts(idol).size >= 3 && brandMatch
            }
            _uiState.value = _uiState.value.copy(isLoading = false, pool = pool, question = makeQuestion(pool))
        }
    }

    private fun facts(idol: Idol): List<Fact> {
        val f = mutableListOf<Fact>()
        idol.bloodType?.takeIf { it.isNotEmpty() }?.let { f.add(Fact("血液型", it, 1)) }
        idol.constellation?.takeIf { it.isNotEmpty() }?.let { f.add(Fact("星座", it, 1)) }
        idol.birthPlace?.takeIf { it.isNotEmpty() }?.let { f.add(Fact("出身", it, 1)) }
        idol.height?.let { f.add(Fact("身長", "${it.toInt()}cm", 1)) }
        idol.age?.let { f.add(Fact("年齢", "${it}歳", 1)) }
        idol.hobbies?.takeIf { it.isNotEmpty() }?.let { f.add(Fact("趣味", it, 1)) }
        idol.talents?.takeIf { it.isNotEmpty() }?.let { f.add(Fact("特技", it, 1)) }
        idol.birthday?.takeIf { it.isNotEmpty() }?.let { f.add(Fact("誕生日", formatBirthday(it), 1)) }
        idol.color?.takeIf { it.isNotEmpty() }?.let { f.add(Fact("メンバーカラー", it, 2)) }
        return f
    }

    private fun makeQuestion(pool: List<Idol>): Question? {
        if (pool.size < 4) return null
        var candidates = pool.filter { !seenIds.contains(it.id) }
        if (candidates.isEmpty()) {
            seenIds = emptySet()
            candidates = pool
        }
        val answer = candidates.randomOrNull() ?: return null
        seenIds = seenIds + answer.id
        val choices = (quizDistractors(pool, answer) + answer).shuffled()
        return Question(answer, choices, facts(answer))
    }

    fun currentValue(): Int {
        val q = _uiState.value.question ?: return BASE_POINTS
        val cost = _uiState.value.opened.sumOf { idx -> q.facts.getOrNull(idx)?.cost ?: 0 }
        return maxOf(1, BASE_POINTS - cost)
    }

    fun openHint(idx: Int) {
        _uiState.value = _uiState.value.copy(opened = _uiState.value.opened + idx)
    }

    fun pick(idol: Idol) {
        val s = _uiState.value
        val q = s.question ?: return
        if (s.selectedId != null) return
        val isCorrect = idol.id == q.answer.id
        val earned = if (isCorrect) currentValue() else 0
        val history = s.history + QuizHistoryItem(
            id = "${s.asked + 1}-${q.answer.id}",
            index = s.asked + 1,
            subjectTitle = "プロフィール問題",
            subjectSubtitle = q.facts.firstOrNull()?.let { "${it.label}: ${it.value}" },
            answer = q.answer, picked = idol, earnedPoints = earned, revealedHints = s.opened.size
        )
        _uiState.value = s.copy(
            selectedId = idol.id, asked = s.asked + 1,
            correct = s.correct + if (isCorrect) 1 else 0,
            points = s.points + earned,
            history = history
        )
    }

    fun nextQuestion() {
        val s = _uiState.value
        _uiState.value = s.copy(selectedId = null, opened = emptySet(), question = makeQuestion(s.pool))
    }

    fun finish() {
        val s = _uiState.value
        val outOf = s.asked * BASE_POINTS
        val before = progressStore.record(GameKind.idolQuiz)
        val beforeRate = if (before.bestOutOf > 0) before.bestScore.toDouble() / before.bestOutOf else -1.0
        val newRate = if (outOf > 0) s.points.toDouble() / outOf else 0.0
        val isNewBest = before.hasPlayed && newRate > beforeRate
        _uiState.value = s.copy(sessionDone = true, isNewBest = isNewBest)
        progressStore.recordResult(GameKind.idolQuiz, score = s.points, outOf = outOf)
    }

    fun restart() {
        val s = _uiState.value
        seenIds = emptySet()
        _uiState.value = IdolQuizUiState(isLoading = false, pool = s.pool, question = makeQuestion(s.pool))
    }

    class Factory(private val app: Application, private val selectedBrandIds: Set<String>) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : androidx.lifecycle.ViewModel> create(modelClass: Class<T>): T =
            IdolQuizViewModel(app, selectedBrandIds) as T
    }
}

private fun formatBirthday(b: String): String {
    val cleaned = b.removePrefix("--")
    val parts = cleaned.split("-")
    return if (parts.size == 2) "${parts[0]}月${parts[1]}日" else b
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
                state.sessionDone -> QuizResultView(
                    points = state.points, maxPoints = state.asked * BASE_POINTS,
                    correct = state.correct, questions = state.asked, kind = GameKind.idolQuiz,
                    isNewBest = state.isNewBest, history = state.history, onReplay = { viewModel.restart() }
                )
                question != null -> {
                    QuizProgressHeader(
                        current = minOf(state.asked + if (state.selectedId != null) 0 else 1, SESSION_LENGTH),
                        total = SESSION_LENGTH, points = state.points
                    )
                    IdolPromptCard(question, state, viewModel)
                    if (state.selectedId == null) IdolHintList(question, state, viewModel)
                    IdolChoiceGrid(choices = question.choices, answer = question.answer, selectedId = state.selectedId) { idol, _ ->
                        viewModel.pick(idol)
                    }
                    if (state.selectedId != null) {
                        QuizNextButton(isLastQuestion = state.asked >= SESSION_LENGTH, onNext = { viewModel.nextQuestion() }, onFinish = { viewModel.finish() })
                    }
                }
                else -> ImasEmptyState(icon = Icons.Filled.PersonSearch, title = "出題できる候補が不足しています")
            }
        }
    }
}

@Composable
private fun IdolPromptCard(q: Question, state: IdolQuizUiState, viewModel: IdolQuizViewModel) {
    val answered = state.selectedId != null
    val shownIndices = if (answered) q.facts.indices.toList() else (listOf(0) + state.opened.sorted()).distinct()
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
                    IdolValueBadge(viewModel.currentValue())
                }
            }
        }
        Column(
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(DS.surface),
        ) {
            shownIndices.forEachIndexed { pos, idx ->
                if (pos > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(DS.sep).padding(start = 16.dp))
                val f = q.facts[idx]
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(f.label, fontSize = 15.sp, color = DS.ink2, modifier = Modifier.weight(1f))
                    if (f.label == "メンバーカラー") {
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
private fun IdolHintList(q: Question, state: IdolQuizUiState, viewModel: IdolQuizViewModel) {
    val remaining = (1 until q.facts.size).filter { !state.opened.contains(it) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        remaining.forEach { idx ->
            val f = q.facts[idx]
            val nextValue = maxOf(1, viewModel.currentValue() - f.cost)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(DS.surface)
                    .clickable { viewModel.openHint(idx) }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Box(
                    Modifier.size(34.dp).clip(RoundedCornerShape(10.dp)).background(DS.warning.copy(alpha = 0.14f)),
                    contentAlignment = Alignment.Center
                ) { Icon(Icons.Filled.Lightbulb, null, tint = DS.warning, modifier = Modifier.size(16.dp)) }
                Column(Modifier.weight(1f)) {
                    Text("ヒント: ${f.label}を見る", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
                    Text("開いた後は正解で +${nextValue}pt", fontSize = 12.sp, color = DS.ink3)
                }
                Icon(Icons.Filled.ExpandMore, null, tint = DS.ink3, modifier = Modifier.size(13.dp))
            }
        }
    }
}
