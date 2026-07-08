package com.fugaif.imaslivedb.ui.introdon

import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.ListAlt
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.games.QuizSetupBrandSection
import com.fugaif.imaslivedb.ui.games.QuizSetupCountRow
import com.fugaif.imaslivedb.ui.games.QuizSetupInsufficientBanner
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * イントロドンの設定画面。iOS IntroGameSetupView の移植。
 * Android には Apple Music フル再生が無いため、iOS にある「再生方式(フル/プレビュー)」の
 * トグルは出さない (常にプレビュー)。同様に音声判定回答モードも省略 (常に4択)。
 */
private val questionCounts = listOf(5, 10, 20)
private val durations = listOf(
    Pair("0.2秒", 200L), Pair("2秒", 2_000L), Pair("5秒", 5_000L), Pair("10秒", 10_000L)
)
private val rushTimes = listOf(30, 60, 120)

data class IntroDonSetupUiState(
    val brands: List<Brand> = emptyList(),
    val mode: IntroDonMode = IntroDonMode.NORMAL,
    val selectedBrandIds: Set<String> = emptySet(),
    val questionCount: Int = 10,
    val introDurationMs: Long = 5_000L,
    val rushTimeLimitSec: Int = 60,
    val estimatedCount: Int = 0,
    val isEstimating: Boolean = true
) {
    val canStart: Boolean get() = isEstimating || estimatedCount >= 4

    fun toSettings(): IntroDonSettings = IntroDonSettings(
        mode = mode,
        questionCount = questionCount,
        introDurationMs = introDurationMs,
        rushTimeLimitSec = rushTimeLimitSec,
        selectedBrandIds = selectedBrandIds
    )
}

class IntroDonSetupViewModel(app: Application) : AndroidViewModel(app) {
    private val songRepository = AppModule.from(app).songRepository
    private val brandDao = AppModule.from(app).database.brandDao()

    private val _uiState = MutableStateFlow(IntroDonSetupUiState())
    val uiState: StateFlow<IntroDonSetupUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val brands = brandDao.fetchBrands()
            _uiState.value = _uiState.value.copy(brands = brands)
            estimatePool()
        }
    }

    fun setMode(mode: IntroDonMode) {
        _uiState.value = _uiState.value.copy(mode = mode)
    }

    fun setQuestionCount(n: Int) {
        _uiState.value = _uiState.value.copy(questionCount = n)
    }

    fun setIntroDuration(ms: Long) {
        _uiState.value = _uiState.value.copy(introDurationMs = ms)
    }

    fun setRushTimeLimit(sec: Int) {
        _uiState.value = _uiState.value.copy(rushTimeLimitSec = sec)
    }

    fun toggleBrand(id: String) {
        val current = _uiState.value.selectedBrandIds
        val updated = if (current.contains(id)) current - id else current + id
        _uiState.value = _uiState.value.copy(selectedBrandIds = updated)
        viewModelScope.launch { estimatePool() }
    }

    fun clearBrands() {
        _uiState.value = _uiState.value.copy(selectedBrandIds = emptySet())
        viewModelScope.launch { estimatePool() }
    }

    private suspend fun estimatePool() {
        _uiState.value = _uiState.value.copy(isEstimating = true)
        val pool = songRepository.fetchIntroDonSongs(_uiState.value.selectedBrandIds)
        _uiState.value = _uiState.value.copy(estimatedCount = pool.size, isEstimating = false)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IntroDonSetupScreen(
    onBack: () -> Unit,
    onStartGame: (IntroDonSettings) -> Unit,
    onStartParty: (IntroDonSettings) -> Unit,
    viewModel: IntroDonSetupViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("設定", fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                IntroDonSectionLabel(text = "モード")
                ModeSection(state.mode, viewModel::setMode)
            }

            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                IntroDonSectionLabel(text = "出題範囲", hint = "ブランドで絞る")
                QuizSetupBrandSection(
                    brands = state.brands, selectedBrandIds = state.selectedBrandIds,
                    onToggle = viewModel::toggleBrand, onClearAll = viewModel::clearBrands
                )
            }

            when (state.mode) {
                IntroDonMode.NORMAL, IntroDonMode.PARTY -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    IntroDonSectionLabel(text = "問題数")
                    CountSection(state.questionCount, viewModel::setQuestionCount)
                }
                IntroDonMode.RUSH -> Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    IntroDonSectionLabel(text = "制限時間")
                    RushTimeSection(state.rushTimeLimitSec, viewModel::setRushTimeLimit)
                }
                IntroDonMode.ALL_SONGS -> AllSongsNote()
            }

            if (state.mode == IntroDonMode.NORMAL || state.mode == IntroDonMode.PARTY) {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    IntroDonSectionLabel(text = "難易度 (イントロ再生時間)")
                    DurationSection(state.introDurationMs, viewModel::setIntroDuration)
                }
            }

            QuizSetupCountRow(isEstimating = state.isEstimating) {
                Text("出題候補: ${state.estimatedCount} 曲", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            }
            if (!state.isEstimating && state.estimatedCount < 4) {
                QuizSetupInsufficientBanner("出題するにはプレビュー付きの曲が最低 4 曲必要です。ブランドの選択を増やしてください。")
            }

            IntroDonActionButton(title = "スタート", enabled = state.canStart) {
                if (state.mode == IntroDonMode.PARTY) onStartParty(state.toSettings()) else onStartGame(state.toSettings())
            }

            Spacer(Modifier.height(8.dp))
        }
    }
}

@Composable
private fun ModeSection(selected: IntroDonMode, onSelect: (IntroDonMode) -> Unit) {
    val icons: Map<IntroDonMode, ImageVector> = mapOf(
        IntroDonMode.NORMAL to Icons.Filled.ListAlt,
        IntroDonMode.RUSH to Icons.Filled.Timer,
        IntroDonMode.ALL_SONGS to Icons.Filled.AllInclusive,
        IntroDonMode.PARTY to Icons.Filled.Group
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        IntroDonMode.entries.forEach { mode ->
            val isSelected = mode == selected
            val accent = introDonAccent()
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(14.dp))
                    .background(if (isSelected) accent else DS.surface)
                    .clickable { onSelect(mode) }
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Icon(
                    icons.getValue(mode), null,
                    tint = if (isSelected) androidx.compose.ui.graphics.Color.White else accent,
                    modifier = Modifier.size(20.dp)
                )
                Column(Modifier.weight(1f)) {
                    Text(mode.label, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = if (isSelected) androidx.compose.ui.graphics.Color.White else DS.ink)
                    Text(mode.icon, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = if (isSelected) androidx.compose.ui.graphics.Color.White.copy(alpha = 0.8f) else DS.ink3)
                }
                if (isSelected) Icon(Icons.Filled.CheckCircle, null, tint = androidx.compose.ui.graphics.Color.White, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun CountSection(selected: Int, onSelect: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        questionCounts.forEach { n ->
            SegmentButton(primary = "$n", secondary = "問", selected = selected == n, modifier = Modifier.weight(1f)) { onSelect(n) }
        }
    }
}

@Composable
private fun RushTimeSection(selectedSec: Int, onSelect: (Int) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
        rushTimes.forEach { sec ->
            SegmentButton(primary = "$sec", secondary = "秒", selected = selectedSec == sec, modifier = Modifier.weight(1f)) { onSelect(sec) }
        }
    }
}

@Composable
private fun DurationSection(selectedMs: Long, onSelect: (Long) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
            durations.forEach { (label, ms) ->
                SegmentButton(primary = label, secondary = if (ms < 1000) "超イントロ" else "再生", selected = selectedMs == ms, modifier = Modifier.weight(1f)) { onSelect(ms) }
            }
        }
        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(modifier = Modifier.fillMaxWidth()) {
                Text(
                    if (selectedMs < 1000) "超イントロ" else "再生時間",
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    color = if (selectedMs < 1000) DS.favorite else DS.ink2, modifier = Modifier.weight(1f)
                )
                Text(String.format("%.1f秒", selectedMs / 1000.0), fontSize = 14.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            }
            Slider(
                value = (selectedMs / 100).toFloat(),
                onValueChange = { onSelect((it.toLong().coerceIn(2, 100)) * 100) },
                valueRange = 2f..100f
            )
        }
    }
}

@Composable
private fun AllSongsNote() {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(DS.favorite.copy(alpha = 0.08f)).padding(14.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(Icons.Filled.AllInclusive, null, tint = DS.favorite, modifier = Modifier.size(16.dp))
        Text("選択した出題範囲の全曲を出し切るまで挑戦。タイムと正答率を競います。", fontSize = 12.sp, color = DS.ink2)
    }
}

@Composable
private fun SegmentButton(primary: String, secondary: String, selected: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val accent = introDonAccent()
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(if (selected) accent else DS.surface)
            .clickable(onClick = onClick)
            .padding(vertical = 16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp)
    ) {
        Text(primary, fontSize = 20.sp, fontWeight = FontWeight.Black, color = if (selected) androidx.compose.ui.graphics.Color.White else DS.ink)
        Text(secondary, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = if (selected) androidx.compose.ui.graphics.Color.White.copy(alpha = 0.85f) else DS.ink3)
    }
}
