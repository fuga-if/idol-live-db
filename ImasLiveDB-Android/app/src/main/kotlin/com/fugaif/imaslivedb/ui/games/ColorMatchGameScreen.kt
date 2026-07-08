package com.fugaif.imaslivedb.ui.games

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.QuestionMark
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.games.GameKind
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasAvatar
import com.fugaif.imaslivedb.ui.components.ImasSegmented
import com.fugaif.imaslivedb.ui.theme.ColorMath
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.hexToColor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.random.Random

// =============================================================================
// メンバーカラー合わせ。iOS ColorMatchGameView の移植。
// ドラッグ&ドロップの代わりに「色チップをタップで選択 → メンバー行をタップで割当」方式のみ提供
// (iOS 側もタップ割当を併存させているため、機能的な等価性は保たれる)。
// =============================================================================

private val LEVEL_LABELS = listOf("やさしい", "ふつう", "むずい")
private val LEVEL_COUNTS = listOf(4, 5, 6)
private val QUESTION_COUNT_OPTIONS = listOf(5, 10)

data class ColorMatchUiState(
    val isLoading: Boolean = true,
    val brands: List<Brand> = emptyList(),
    val brandPools: List<Pair<Brand, List<Idol>>> = emptyList(),
    val allColored: List<Idol> = emptyList(),
    val selectedBrandIds: Set<String> = emptySet(),
    val difficulty: Int = 1,
    val questionCount: Int = 5,
    val inGame: Boolean = false,
    val sessionDone: Boolean = false,
    val roundIndex: Int = 0,
    val totalCorrect: Int = 0,
    val totalAnswered: Int = 0,
    val members: List<Idol> = emptyList(),
    val palette: List<String> = emptyList(),
    val assignments: Map<String, String> = emptyMap(),
    val selectedHex: String? = null,
    val judged: Boolean = false
) {
    val effectivePool: List<Idol>
        get() = if (selectedBrandIds.isEmpty()) {
            allColored
        } else {
            uniqueByColor(brandPools.filter { selectedBrandIds.contains(it.first.id) }.flatMap { it.second })
        }
    val isCrossBrand: Boolean get() = selectedBrandIds.size != 1
}

private fun uniqueByColor(idols: List<Idol>): List<Idol> {
    val seen = HashSet<String>()
    val result = mutableListOf<Idol>()
    for (idol in idols) {
        val hex = ColorMath.normalizedHex(idol.color ?: "") ?: continue
        if (!seen.add(hex)) continue
        result.add(idol)
    }
    return result
}

private fun colorDistance(a: String?, b: String?): Double {
    if (a == null || b == null) return Double.MAX_VALUE
    if (ColorMath.normalizedHex(a) == null || ColorMath.normalizedHex(b) == null) return Double.MAX_VALUE
    val x = ColorMath.hexToRgb(a)
    val y = ColorMath.hexToRgb(b)
    val rmean = (x.r + y.r) / 2
    val dr = x.r - y.r
    val dg = x.g - y.g
    val db = x.b - y.b
    return ((2 + rmean / 256) * dr * dr) + (4 * dg * dg) + ((2 + (255 - rmean) / 256) * db * db)
}

class ColorMatchViewModel(app: Application) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val brandDao = AppModule.from(app).database.brandDao()
    private val progressStore = AppModule.from(app).gameProgressStore

    private val _uiState = MutableStateFlow(ColorMatchUiState())
    val uiState: StateFlow<ColorMatchUiState> = _uiState.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val all = idolRepository.fetchIdols()
            val allBrands = brandDao.fetchBrands()
            val brandById = allBrands.associateBy { it.id }
            val brands = allBrands.filter { it.id != "other" }
            val colored = all.filter { it.brandId != "other" && !it.color.isNullOrEmpty() }
            val allColored = uniqueByColor(colored)
            val byBrand = colored.groupBy { it.brandId }
            val brandPools = byBrand.mapNotNull { (brandId, list) ->
                val brand = brandById[brandId] ?: return@mapNotNull null
                val uniq = uniqueByColor(list.sortedBy { it.sortOrder })
                if (uniq.size >= 4) brand to uniq else null
            }.sortedBy { it.first.sortOrder }
            _uiState.value = _uiState.value.copy(
                isLoading = false, brands = brands, brandPools = brandPools, allColored = allColored
            )
        }
    }

    fun toggleBrand(id: String) {
        val current = _uiState.value.selectedBrandIds
        _uiState.value = _uiState.value.copy(
            selectedBrandIds = if (current.contains(id)) current - id else current + id
        )
    }

    fun clearBrands() { _uiState.value = _uiState.value.copy(selectedBrandIds = emptySet()) }
    fun setDifficulty(d: Int) { _uiState.value = _uiState.value.copy(difficulty = d) }
    fun setQuestionCount(n: Int) { _uiState.value = _uiState.value.copy(questionCount = n) }

    fun startSession() {
        val pool = _uiState.value.effectivePool
        if (pool.size < 2) return
        _uiState.value = _uiState.value.copy(
            roundIndex = 0, totalCorrect = 0, totalAnswered = 0, sessionDone = false, inGame = true
        )
        startRound(pool)
    }

    fun resetToSetup() {
        _uiState.value = _uiState.value.copy(inGame = false, sessionDone = false)
    }

    private fun startRound(scopePool: List<Idol>) {
        val s = _uiState.value
        val n = minOf(LEVEL_COUNTS[s.difficulty], scopePool.size)
        if (n < 2 || scopePool.isEmpty()) {
            _uiState.value = s.copy(members = emptyList(), palette = emptyList(), judged = false, assignments = emptyMap(), selectedHex = null)
            return
        }
        val anchor = scopePool[Random.nextInt(scopePool.size)]
        val rest = scopePool.filter { it.id != anchor.id }
        val chosen: List<Idol> = when (s.difficulty) {
            2 -> listOf(anchor) + rest.sortedBy { colorDistance(anchor.color, it.color) }.take(n - 1)
            0 -> {
                val result = mutableListOf(anchor)
                var left = rest
                while (result.size < n && left.isNotEmpty()) {
                    val best = left.maxByOrNull { candidate -> result.minOf { colorDistance(candidate.color, it.color) } }!!
                    result.add(best)
                    left = left.filter { it.id != best.id }
                }
                result
            }
            else -> listOf(anchor) + rest.shuffled().take(n - 1)
        }
        val members = chosen.shuffled()
        val palette = members.map { it.color ?: "" }.shuffled()
        _uiState.value = s.copy(members = members, palette = palette, assignments = emptyMap(), selectedHex = null, judged = false)
    }

    fun selectHex(hex: String) {
        val s = _uiState.value
        if (s.judged) return
        _uiState.value = s.copy(selectedHex = if (s.selectedHex == hex) null else hex)
    }

    fun onMemberTap(idolId: String) {
        val s = _uiState.value
        if (s.judged) return
        if (s.assignments.containsKey(idolId)) {
            _uiState.value = s.copy(assignments = s.assignments - idolId)
        } else {
            val hex = s.selectedHex ?: return
            val cleared = s.assignments.filterValues { it != hex }
            _uiState.value = s.copy(assignments = cleared + (idolId to hex), selectedHex = null)
        }
    }

    fun judge() {
        val s = _uiState.value
        val correctCount = scoreCount(s)
        _uiState.value = s.copy(
            judged = true,
            totalCorrect = s.totalCorrect + correctCount,
            totalAnswered = s.totalAnswered + s.members.size
        )
    }

    private fun scoreCount(s: ColorMatchUiState): Int =
        s.members.count { idol -> s.assignments[idol.id]?.let { sameColor(it, idol.color) } == true }

    private fun sameColor(a: String, b: String?): Boolean {
        if (b == null) return false
        return ColorMath.normalizedHex(a) == ColorMath.normalizedHex(b)
    }

    fun advance() {
        val s = _uiState.value
        if (s.roundIndex + 1 < s.questionCount) {
            _uiState.value = s.copy(roundIndex = s.roundIndex + 1)
            startRound(s.effectivePool)
        } else {
            _uiState.value = s.copy(sessionDone = true)
            progressStore.recordResult(GameKind.colorMatch, score = s.totalCorrect, outOf = s.totalAnswered)
        }
    }

    fun scoreCountPublic(): Int = scoreCount(_uiState.value)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ColorMatchGameScreen(onBack: () -> Unit, viewModel: ColorMatchViewModel = viewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

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
            when {
                state.isLoading -> Box(Modifier.fillMaxWidth().padding(top = 60.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
                state.sessionDone -> ColorMatchResult(state, onReplay = { viewModel.startSession() }, onChangeSetup = { viewModel.resetToSetup() })
                !state.inGame -> ColorMatchSetup(state, viewModel)
                else -> ColorMatchPlay(state, viewModel)
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
    val canStart = state.effectivePool.size >= 2
    QuizPrimaryButton(title = "はじめる（全${state.questionCount}問）") { if (canStart) viewModel.startSession() }
}

@Composable
private fun ColorMatchPlay(state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(
                    if (state.judged) "答え合わせ" else "色をタップして選択、メンバーをタップで割当",
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink
                )
                Text(
                    "第${state.roundIndex + 1}問 / 全${state.questionCount}問 ・ ${LEVEL_LABELS[state.difficulty]}",
                    fontSize = 12.sp, color = DS.ink3
                )
            }
            Text(
                "やめる", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2,
                modifier = Modifier.clickable { viewModel.resetToSetup() }
            )
        }
    }

    ColorMatchPaletteRow(state, viewModel)
    ColorMatchMemberList(state, viewModel)

    if (state.judged) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            Text("${viewModel.scoreCountPublic()} / ${state.members.size} 正解", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            QuizPrimaryButton(
                title = if (state.roundIndex + 1 < state.questionCount) "次へ（第${state.roundIndex + 2}問）" else "結果を見る"
            ) { viewModel.advance() }
        }
    } else {
        val ready = state.assignments.size == state.members.size
        val accent = com.fugaif.imaslivedb.ui.theme.ImasTheme.derive(null, null, dark = true)
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(14.dp))
                .background(if (ready) accent.accent else DS.fill)
                .clickable(enabled = ready) { viewModel.judge() }
                .padding(vertical = 15.dp),
            contentAlignment = Alignment.Center
        ) {
            Text("判定する", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = if (ready) accent.onAccent else DS.ink3)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ColorMatchPaletteRow(state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        state.palette.forEach { hex ->
            val used = state.assignments.values.contains(hex)
            val isSelected = state.selectedHex == hex
            Box(
                modifier = Modifier
                    .size(46.dp)
                    .clip(CircleShape)
                    .background(hexToColor(hex))
                    .border(if (isSelected) 3.dp else 1.dp, if (isSelected) DS.ink else Color.White.copy(alpha = 0.5f), CircleShape)
                    .clickable { viewModel.selectHex(hex) },
                contentAlignment = Alignment.Center
            ) {
                if (used) Icon(Icons.Filled.Check, null, tint = Color.White, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
private fun ColorMatchMemberList(state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.surface),
        verticalArrangement = Arrangement.spacedBy(0.dp)
    ) {
        state.members.forEachIndexed { idx, idol ->
            if (idx > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(DS.sep).padding(start = 16.dp))
            ColorMatchMemberRow(idol, state, viewModel)
        }
    }
}

@Composable
private fun ColorMatchMemberRow(idol: Idol, state: ColorMatchUiState, viewModel: ColorMatchViewModel) {
    val assigned = state.assignments[idol.id]
    val correct = state.judged && assigned != null && ColorMath.normalizedHex(assigned) == ColorMath.normalizedHex(idol.color ?: "")
    val ring = when {
        state.judged -> if (correct) DS.success else DS.danger
        else -> Color.White.copy(alpha = 0.4f)
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { viewModel.onMemberTap(idol.id) }
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        ImasAvatar(label = idol.name, seed = null, size = 44.dp)
        Column(Modifier.weight(1f)) {
            Text(idol.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            if (state.isCrossBrand) {
                state.brandPools.firstOrNull { it.first.id == idol.brandId }?.let {
                    Text(it.first.shortName, fontSize = 12.sp, color = DS.ink3)
                }
            }
            if (state.judged) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(if (correct) "メンバーカラー" else "正解", fontSize = 12.sp, color = DS.ink3)
                    Box(Modifier.size(12.dp).clip(CircleShape).background(hexToColor(idol.color ?: "")).border(0.5.dp, DS.sep, CircleShape))
                    Text("#${ColorMath.normalizedHex(idol.color ?: "")?.uppercase() ?: "??????"}", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = DS.ink2)
                }
            }
        }
        Box(
            modifier = Modifier.size(40.dp).clip(CircleShape).background(assigned?.let { hexToColor(it) } ?: DS.fill)
                .border(2.5.dp, ring, CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (assigned == null && !state.judged) Icon(Icons.Filled.QuestionMark, null, tint = DS.ink3, modifier = Modifier.size(14.dp))
        }
        if (state.judged) {
            Icon(
                if (correct) Icons.Filled.Verified else Icons.Filled.Close,
                null, tint = if (correct) DS.success else DS.danger, modifier = Modifier.size(20.dp)
            )
        }
    }
}

@Composable
private fun ColorMatchResult(state: ColorMatchUiState, onReplay: () -> Unit, onChangeSetup: () -> Unit) {
    val rate = if (state.totalAnswered > 0) Math.round((state.totalCorrect.toDouble() / state.totalAnswered) * 100).toInt() else 0
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxWidth().padding(top = 30.dp)) {
        Icon(
            if (rate >= 80) Icons.Filled.EmojiEvents else Icons.Filled.Verified,
            null, tint = if (rate >= 80) DS.favorite else com.fugaif.imaslivedb.ui.theme.ImasTheme.derive(null, null, dark = true).accent,
            modifier = Modifier.size(52.dp)
        )
        Text("正答率 $rate%", fontSize = 34.sp, fontWeight = FontWeight.Bold, color = DS.ink)
        Text("${state.totalCorrect} / ${state.totalAnswered} 正解（全${state.questionCount}問）", fontSize = 15.sp, color = DS.ink2)
        Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
            QuizPrimaryButton(title = "もう一度", onClick = onReplay)
            Box(
                modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.fill)
                    .clickable(onClick = onChangeSetup).padding(vertical = 15.dp),
                contentAlignment = Alignment.Center
            ) { Text("設定を変える", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = DS.ink) }
        }
    }
}
