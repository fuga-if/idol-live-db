package com.fugaif.imaslivedb.ui.games

import android.app.Application
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.PersonSearch
import androidx.compose.material.icons.filled.Warning
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.idolQuizPoolEstimate
import uniffi.imas_core.quizBrandIdsDecode
import uniffi.imas_core.quizBrandIdsEncode

data class IdolQuizSetupUiState(
    val brands: List<Brand> = emptyList(),
    val selectedBrandIds: Set<String> = emptySet(),
    val estimatedCount: Int = 0,
    /** 4 択を組めるか。判定はコアが持つ (ゲーム本体と同じ母集団条件)。 */
    val isSufficient: Boolean = false,
    val isEstimating: Boolean = true
) {
    /** 推計中は暫定的に許可して二重ロードを防ぐ。 */
    val canStart: Boolean get() = isEstimating || isSufficient
}

class IdolQuizSetupViewModel(app: Application) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val brandDao = AppModule.from(app).database.brandDao()
    private val snapshots = AppModule.from(app).snapshotStoreProvider
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(
        IdolQuizSetupUiState(selectedBrandIds = quizBrandIdsDecode(prefs.getString(KEY_BRAND_IDS, "") ?: "").toSet())
    )
    val uiState: StateFlow<IdolQuizSetupUiState> = _uiState.asStateFlow()

    /**
     * 現任 CV 名。ブランドを切り替えるたびに引き直さないよう 1 度だけ読む
     * (母集団の条件に CV は効かないが、射影はゲーム本体と同じ 1 か所に通す)。
     */
    private var castNames: Map<String, String> = emptyMap()

    init {
        viewModelScope.launch {
            val brands = brandDao.fetchBrands()
            _uiState.value = _uiState.value.copy(brands = brands)
            castNames = fetchIdolCastNames(snapshots)
            estimatePool()
        }
    }

    fun toggleBrand(id: String) {
        val current = _uiState.value.selectedBrandIds
        val updated = if (current.contains(id)) current - id else current + id
        _uiState.value = _uiState.value.copy(selectedBrandIds = updated)
        prefs.edit().putString(KEY_BRAND_IDS, quizBrandIdsEncode(updated.toList())).apply()
        viewModelScope.launch { estimatePool() }
    }

    fun clearBrands() {
        _uiState.value = _uiState.value.copy(selectedBrandIds = emptySet())
        prefs.edit().putString(KEY_BRAND_IDS, "").apply()
        viewModelScope.launch { estimatePool() }
    }

    /**
     * 出題候補の見積り。母集団の条件 (外部ゲスト除外・メンバーカラー必須・
     * プロフィール事実 3 件以上・ブランド絞り込み) はコアが持ち、ゲーム本体の
     * [uniffi.imas_core.idolQuizSession] と同じ 1 関数を共有する。
     * 別条件にすると「開始できるのに候補不足で始まる」ズレが出る。
     */
    private suspend fun estimatePool() {
        _uiState.value = _uiState.value.copy(isEstimating = true)
        val selected = _uiState.value.selectedBrandIds
        val all = idolRepository.fetchIdols()
        val estimate = idolQuizPoolEstimate(idolQuizRefs(all, castNames), selected.toList())
        _uiState.value = _uiState.value.copy(
            estimatedCount = estimate.count.toInt(),
            isSufficient = estimate.isSufficient,
            isEstimating = false
        )
    }

    companion object {
        private const val PREFS_NAME = "quiz_setup_prefs"
        private const val KEY_BRAND_IDS = "idol_quiz_brand_ids"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IdolQuizSetupScreen(
    onBack: () -> Unit,
    onStart: (Set<String>) -> Unit,
    viewModel: IdolQuizSetupViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

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
            QuizSetupHeaderCard(
                icon = Icons.Filled.PersonSearch, title = "アイドル当てクイズ",
                subtitle = "プロフィールのヒントを手がかりに誰かを 4 択で当てよう"
            )
            QuizSetupBrandSection(
                brands = state.brands, selectedBrandIds = state.selectedBrandIds,
                onToggle = { viewModel.toggleBrand(it) }, onClearAll = { viewModel.clearBrands() }
            )
            QuizSetupCountRow(isEstimating = state.isEstimating) {
                Text("出題候補: ${state.estimatedCount} 名", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink)
            }
            if (!state.isEstimating && !state.isSufficient) {
                QuizSetupInsufficientBanner("4 択を出すにはアイドルが最低 4 名必要です。ブランドの選択を増やしてください。")
            }
            QuizPrimaryButton(title = "スタート") { if (state.canStart) onStart(state.selectedBrandIds) }
        }
    }
}

// MARK: - 共通セットアップ UI パーツ (アイドル当て / ソロ曲クイズで共有)

@Composable
fun QuizSetupHeaderCard(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, subtitle: String) {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Box(
            modifier = Modifier.size(52.dp).clip(RoundedCornerShape(14.dp)).background(DS.fill),
            contentAlignment = Alignment.Center
        ) { Icon(icon, null, tint = com.fugaif.imaslivedb.ui.theme.ImasTheme.derive(null, null, dark = true).accent, modifier = Modifier.size(28.dp)) }
        Column {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = DS.ink)
            Text(subtitle, fontSize = 12.sp, color = DS.ink3)
        }
    }
}

@Composable
fun QuizSetupBrandSection(
    brands: List<Brand>,
    selectedBrandIds: Set<String>,
    onToggle: (String) -> Unit,
    onClearAll: () -> Unit
) {
    Column(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(DS.surface).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text("出題ブランド", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = DS.ink)
                Text("複数選択可 · 空=全ブランド対象", fontSize = 12.sp, color = DS.ink3)
            }
            if (selectedBrandIds.isNotEmpty()) {
                Text(
                    "全てに戻す", fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                    color = com.fugaif.imaslivedb.ui.theme.ImasTheme.derive(null, null, dark = true).accent,
                    modifier = Modifier.clickable(onClick = onClearAll)
                )
            }
        }
        GameBrandFilterGrid(brands = brands, selectedBrandIds = selectedBrandIds, onToggle = onToggle, onClearAll = onClearAll)
    }
}

@Composable
fun QuizSetupCountRow(isEstimating: Boolean, content: @Composable () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(DS.fill).padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        if (isEstimating) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
            Text("候補を計算中…", fontSize = 15.sp, color = DS.ink3)
        } else {
            content()
        }
    }
}

@Composable
fun QuizSetupInsufficientBanner(message: String) {
    Row(
        modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(DS.warning.copy(alpha = 0.12f)).padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)
    ) {
        Icon(Icons.Filled.Warning, null, tint = DS.warning, modifier = Modifier.size(18.dp))
        Text(message, fontSize = 12.sp, color = DS.ink)
    }
}
