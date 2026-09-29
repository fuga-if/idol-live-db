package com.fugaif.imaslivedb.ui.games

import android.app.Application
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.DS
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.quizBrandIdsDecode
import uniffi.imas_core.quizBrandIdsEncode

// =============================================================================
// セトリ当てクイズの出題設定画面。iOS SetlistQuizSetupView の移植。
// ブランドを絞り込んでからクイズを開始する。設定は SharedPreferences で次回起動まで保持する。
//
// 出題できる公演数の見積りはゲーム本体と同じ条件で imas-core の
// `domain/setlist_quiz.rs` が数える (SnapshotStore.setlistQuizPoolEstimate)。
// =============================================================================

data class SetlistQuizSetupUiState(
    val brands: List<Brand> = emptyList(),
    val selectedBrandIds: Set<String> = emptySet(),
    /** 出題できる公演数 (コアがゲーム本体と同じ条件で数えた結果)。 */
    val showCount: Int = 0,
    val isSufficient: Boolean = false,
    val isEstimating: Boolean = true
) {
    val canStart: Boolean get() = isEstimating || isSufficient
}

class SetlistQuizSetupViewModel(app: Application) : AndroidViewModel(app) {
    private val snapshots = AppModule.from(app).snapshotStoreProvider
    private val stats = AppModule.from(app).statsRepository
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private var estimateJob: Job? = null

    private val _uiState = MutableStateFlow(
        SetlistQuizSetupUiState(
            selectedBrandIds = quizBrandIdsDecode(prefs.getString(KEY_BRAND_IDS, "") ?: "").toSet()
        )
    )
    val uiState: StateFlow<SetlistQuizSetupUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val brands = runCatching { stats.fetchBrands() }.getOrDefault(emptyList())
            _uiState.value = _uiState.value.copy(brands = brands)
        }
        estimatePool()
    }

    fun toggleBrand(id: String) {
        val current = _uiState.value.selectedBrandIds
        val updated = if (current.contains(id)) current - id else current + id
        _uiState.value = _uiState.value.copy(selectedBrandIds = updated)
        prefs.edit().putString(KEY_BRAND_IDS, quizBrandIdsEncode(updated.toList())).apply()
        estimatePool()
    }

    fun clearBrands() {
        _uiState.value = _uiState.value.copy(selectedBrandIds = emptySet())
        prefs.edit().putString(KEY_BRAND_IDS, "").apply()
        estimatePool()
    }

    /** 出題候補の見積り。母集団の条件 (セトリの曲数など) はコアがゲーム本体と共有する。 */
    private fun estimatePool() {
        estimateJob?.cancel()
        estimateJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isEstimating = true)
            val brandIds = _uiState.value.selectedBrandIds.toList()
            val estimate = runCatching {
                snapshots.query { store -> store.setlistQuizPoolEstimate(brandIds) }
            }.getOrNull()
            _uiState.value = _uiState.value.copy(
                showCount = estimate?.showCount?.toInt() ?: _uiState.value.showCount,
                isSufficient = estimate?.isSufficient ?: _uiState.value.isSufficient,
                isEstimating = false
            )
        }
    }

    companion object {
        private const val PREFS_NAME = "quiz_setup_prefs"
        /** iOS の AppStorage キー "setlistQuizBrandIds" に相当。ソロ曲クイズとは別キー。 */
        private const val KEY_BRAND_IDS = "setlist_quiz_brand_ids"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetlistQuizSetupScreen(
    onBack: () -> Unit,
    onStart: (Set<String>) -> Unit,
    viewModel: SetlistQuizSetupViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("セトリ当て", fontWeight = FontWeight.Bold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "戻る") } }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).background(DS.bg).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            QuizSetupHeaderCard(
                icon = Icons.Filled.FormatListNumbered, title = "セトリ当て",
                subtitle = "公演のセトリの空欄に入る曲を 4 択で当てよう"
            )
            QuizSetupBrandSection(
                brands = state.brands, selectedBrandIds = state.selectedBrandIds,
                onToggle = { viewModel.toggleBrand(it) }, onClearAll = { viewModel.clearBrands() }
            )
            QuizSetupCountRow(isEstimating = state.isEstimating) {
                Column {
                    Text(
                        "出題候補: ${state.showCount} 公演",
                        fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink
                    )
                    Text("セトリが 6 曲以上ある公演から出します", fontSize = 12.sp, color = DS.ink3)
                }
            }
            if (!state.isEstimating && !state.canStart) {
                QuizSetupInsufficientBanner("このブランドには出題できる公演がありません。ブランドの選択を増やしてください。")
            }
            QuizPrimaryButton(title = "スタート") { if (state.canStart) onStart(state.selectedBrandIds) }
        }
    }
}
