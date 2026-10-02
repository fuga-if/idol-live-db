package com.fugaif.imaslivedb.ui.introdon

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AllInclusive
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.ListAlt
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.designsystem.ImasButton
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonRole
import com.fugaif.imaslivedb.ui.designsystem.ImasButtonSize
import com.fugaif.imaslivedb.ui.designsystem.ImasCandidateCount
import com.fugaif.imaslivedb.ui.designsystem.ImasChoice
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCards
import com.fugaif.imaslivedb.ui.designsystem.ImasChoiceCardsStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.games.QuizSetupBrandSection
import com.fugaif.imaslivedb.ui.games.QuizSetupInsufficientBanner
import com.fugaif.imaslivedb.ui.theme.ImasText
import com.fugaif.imaslivedb.ui.theme.DS
import com.fugaif.imaslivedb.ui.theme.ImasTextRole
import kotlinx.coroutines.CancellationException
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
    private val stats = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(IntroDonSetupUiState())
    val uiState: StateFlow<IntroDonSetupUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val brands = stats.fetchBrands()
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
        try {
            val pool = songRepository.fetchIntroDonSongs(_uiState.value.selectedBrandIds)
            _uiState.value = _uiState.value.copy(estimatedCount = pool.size, isEstimating = false)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // 失敗しても「候補を計算中…」のまま止まらないようにする (0 件扱いにして理由を note で出す)。
            _uiState.value = _uiState.value.copy(estimatedCount = 0, isEstimating = false)
        }
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
                title = { Text("設定") },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } }
            )
        }
    ) { padding ->
        ImasPage(modifier = Modifier.padding(padding)) {
            ImasSection(title = "モード", style = ImasSectionHeaderStyle.SMALL) {
                ModeSection(state.mode, viewModel::setMode)
            }

            QuizSetupBrandSection(
                brands = state.brands, selectedBrandIds = state.selectedBrandIds,
                onToggle = { viewModel.toggleBrand(it) }, onClearAll = { viewModel.clearBrands() }
            )

            when (state.mode) {
                IntroDonMode.NORMAL, IntroDonMode.PARTY -> ImasSection(title = "問題数", style = ImasSectionHeaderStyle.SMALL) {
                    CountSection(state.questionCount, viewModel::setQuestionCount)
                }
                IntroDonMode.RUSH -> ImasSection(title = "制限時間", style = ImasSectionHeaderStyle.SMALL) {
                    RushTimeSection(state.rushTimeLimitSec, viewModel::setRushTimeLimit)
                }
                IntroDonMode.ALL_SONGS -> ImasNotice(
                    kind = ImasNoticeKind.INFO,
                    message = "選択した出題範囲の全曲を出し切るまで挑戦。タイムと正答率を競います。",
                    icon = Icons.Filled.AllInclusive
                )
            }

            if (state.mode == IntroDonMode.NORMAL || state.mode == IntroDonMode.PARTY) {
                ImasSection(title = "難易度 (イントロ再生時間)", style = ImasSectionHeaderStyle.SMALL) {
                    DurationSection(state.introDurationMs, viewModel::setIntroDuration)
                }
            }

            ImasCandidateCount(
                count = state.estimatedCount,
                label = "出題候補",
                isLoading = state.isEstimating,
                loadingText = "候補を計算中…"
            )
            if (!state.isEstimating && state.estimatedCount < 4) {
                QuizSetupInsufficientBanner("出題するにはプレビュー付きの曲が最低 4 曲必要です。ブランドの選択を増やしてください。")
            }

            ImasButton(
                title = "スタート",
                onClick = {
                    if (state.mode == IntroDonMode.PARTY) onStartParty(state.toSettings()) else onStartGame(state.toSettings())
                },
                role = ImasButtonRole.PRIMARY,
                size = ImasButtonSize.LARGE,
                fillsWidth = true,
                enabled = state.canStart
            )
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
    ImasChoiceCards(
        choices = IntroDonMode.entries.map { mode ->
            ImasChoice(value = mode, title = mode.label, icon = icons.getValue(mode), subtitle = mode.icon)
        },
        selection = selected,
        onSelect = onSelect,
        style = ImasChoiceCardsStyle.ROW
    )
}

@Composable
private fun CountSection(selected: Int, onSelect: (Int) -> Unit) {
    ImasChoiceCards(
        choices = questionCounts.map { n -> ImasChoice(value = n, title = "$n", subtitle = "問") },
        selection = selected,
        onSelect = onSelect,
        style = ImasChoiceCardsStyle.NUMERAL
    )
}

@Composable
private fun RushTimeSection(selectedSec: Int, onSelect: (Int) -> Unit) {
    ImasChoiceCards(
        choices = rushTimes.map { sec -> ImasChoice(value = sec, title = "$sec", subtitle = "秒") },
        selection = selectedSec,
        onSelect = onSelect,
        style = ImasChoiceCardsStyle.NUMERAL
    )
}

@Composable
private fun DurationSection(selectedMs: Long, onSelect: (Long) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gapLoose)) {
        ImasChoiceCards(
            choices = durations.map { (label, ms) -> ImasChoice(value = ms, title = label, subtitle = if (ms < 1000) "超イントロ" else "再生") },
            selection = selectedMs,
            onSelect = onSelect,
            style = ImasChoiceCardsStyle.NUMERAL,
            // スライダーが同じ selectedMs を連続して動かすため、既定の「値が変わるたび」の
            // 触覚だと動かすたびに鳴ってしまう。札を押した時だけ鳴らす。
            hapticsOnExternalChange = false
        )

        // 細かく秒数を決めるスライダー (0.2〜10秒)。超イントロ (1秒未満) も自由に。
        Column(verticalArrangement = Arrangement.spacedBy(DS.Space.gap)) {
            Row(modifier = Modifier.fillMaxWidth()) {
                ImasText(
                    if (selectedMs < 1000) "超イントロ" else "再生時間",
                    ImasTextRole.META,
                    color = if (selectedMs < 1000) DS.favorite else DS.ink2,
                    modifier = Modifier.weight(1f)
                )
                ImasText(String.format("%.1f秒", selectedMs / 1000.0), ImasTextRole.VALUE)
            }
            Slider(
                value = (selectedMs / 100).toFloat(),
                onValueChange = { onSelect((it.toLong().coerceIn(2, 100)) * 100) },
                valueRange = 2f..100f,
                colors = SliderDefaults.colors(
                    thumbColor = DS.favorite,
                    activeTrackColor = DS.favorite,
                    inactiveTrackColor = DS.fill
                )
            )
        }
    }
}
