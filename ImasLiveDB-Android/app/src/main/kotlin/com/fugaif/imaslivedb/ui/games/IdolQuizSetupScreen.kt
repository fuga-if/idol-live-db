package com.fugaif.imaslivedb.ui.games

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.PersonSearch
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
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.components.ImasBrandPicker
import com.fugaif.imaslivedb.ui.designsystem.ImasCandidateCount
import com.fugaif.imaslivedb.ui.designsystem.ImasCard
import com.fugaif.imaslivedb.ui.designsystem.ImasInlineLoading
import com.fugaif.imaslivedb.ui.designsystem.ImasNotice
import com.fugaif.imaslivedb.ui.designsystem.ImasNoticeKind
import com.fugaif.imaslivedb.ui.designsystem.ImasPage
import com.fugaif.imaslivedb.ui.designsystem.ImasSection
import com.fugaif.imaslivedb.ui.designsystem.ImasSectionHeaderStyle
import com.fugaif.imaslivedb.ui.designsystem.ImasSetupHeader
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
    private val stats = AppModule.from(app).statsRepository
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
            val brands = stats.fetchBrands()
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
        ImasPage(modifier = Modifier.padding(padding)) {
            ImasSetupHeader(
                icon = Icons.Filled.PersonSearch,
                title = "アイドル当てクイズ",
                message = "プロフィールのヒントを手がかりに誰かを 4 択で当てよう"
            )
            QuizSetupBrandSection(
                brands = state.brands, selectedBrandIds = state.selectedBrandIds,
                onToggle = { viewModel.toggleBrand(it) }, onClearAll = { viewModel.clearBrands() }
            )
            ImasCandidateCount(
                count = state.estimatedCount, unit = "名", label = "出題候補",
                isLoading = state.isEstimating, loadingText = "候補を計算中…"
            )
            if (!state.isEstimating && !state.isSufficient) {
                ImasNotice(
                    kind = ImasNoticeKind.WARNING,
                    message = "4 択を出すにはアイドルが最低 4 名必要です。ブランドの選択を増やしてください。"
                )
            }
            QuizPrimaryButton(title = "スタート", enabled = state.canStart) { onStart(state.selectedBrandIds) }
        }
    }
}

// MARK: - 共通セットアップ UI パーツ (アイドル当て / セトリ当て / ソロ曲クイズ・イントロドンの設定画面で共有)

/**
 * 出題ブランドの絞り込み区画 (iOS `ImasSection("出題ブランド", footer:, actionTitle:) { ImasBrandPicker }` の移植)。
 *
 * [onToggle] / [onClearAll] は旧 [GameBrandFilterGrid] 時代からの単体切り替え API のままにしてある
 * (イントロドンの設定画面 `IntroDonSetupScreen` も呼ぶ共有関数なので、呼び出し側のシグネチャは変えない)。
 * 共有アダプタ [ImasBrandPicker] は選択後の完全な集合を返すので、ここで差分に変換して橋渡しする。
 */
@Composable
fun QuizSetupBrandSection(
    brands: List<Brand>,
    selectedBrandIds: Set<String>,
    onToggle: (String) -> Unit,
    onClearAll: () -> Unit
) {
    ImasSection(
        title = "出題ブランド",
        style = ImasSectionHeaderStyle.SMALL,
        footer = "複数選択可 · 空=全ブランド対象",
        actionTitle = if (selectedBrandIds.isNotEmpty()) "全てに戻す" else null,
        onAction = if (selectedBrandIds.isNotEmpty()) onClearAll else null
    ) {
        ImasBrandPicker(
            brands = brands,
            selection = selectedBrandIds,
            onSelectionChange = { updated ->
                if (updated.isEmpty() && selectedBrandIds.isNotEmpty()) {
                    onClearAll()
                } else {
                    ((updated - selectedBrandIds) + (selectedBrandIds - updated)).forEach { onToggle(it) }
                }
            }
        )
    }
}

/**
 * 出題候補を乗せる面 (推計中はくるくる)。中身は呼び出し側が渡す ([content])。
 *
 * イントロドンの設定画面と共有している関数なのでシグネチャはそのまま残し、内側だけ DS 部品化している。
 * アイドル当て・セトリ当て・ソロ曲クイズの 3 設定画面は候補数の形 (単数/複数軸・補足) が
 * [ImasCandidateCount] の引数にそのまま収まるため、この汎用の面は使わず直接 [ImasCandidateCount] を呼ぶ。
 */
@Composable
fun QuizSetupCountRow(isEstimating: Boolean, content: @Composable () -> Unit) {
    ImasCard {
        if (isEstimating) {
            ImasInlineLoading()
        } else {
            content()
        }
    }
}

/** 候補不足などを知らせる注意帯 (iOS `ImasNotice(kind: .warning, message:)` の移植)。 */
@Composable
fun QuizSetupInsufficientBanner(message: String) {
    ImasNotice(kind = ImasNoticeKind.WARNING, message = message)
}
