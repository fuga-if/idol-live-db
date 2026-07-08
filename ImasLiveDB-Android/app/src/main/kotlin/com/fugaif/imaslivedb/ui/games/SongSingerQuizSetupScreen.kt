package com.fugaif.imaslivedb.ui.games

import android.app.Application
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.MusicNote
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SongSingerQuizSetupUiState(
    val brands: List<Brand> = emptyList(),
    val selectedBrandIds: Set<String> = emptySet(),
    val estimatedSongs: Int = 0,
    val estimatedSingers: Int = 0,
    val isEstimating: Boolean = true
) {
    val canStart: Boolean get() = isEstimating || (estimatedSongs >= 4 && estimatedSingers >= 4)
}

class SongSingerQuizSetupViewModel(app: Application) : AndroidViewModel(app) {
    private val idolRepository = AppModule.from(app).idolRepository
    private val songRepository = AppModule.from(app).songRepository
    private val brandDao = AppModule.from(app).database.brandDao()
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(
        SongSingerQuizSetupUiState(selectedBrandIds = decodeBrandIds(prefs.getString(KEY_BRAND_IDS, "") ?: ""))
    )
    val uiState: StateFlow<SongSingerQuizSetupUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val brands = brandDao.fetchBrands()
            _uiState.value = _uiState.value.copy(brands = brands)
            estimatePool()
        }
    }

    fun toggleBrand(id: String) {
        val current = _uiState.value.selectedBrandIds
        val updated = if (current.contains(id)) current - id else current + id
        _uiState.value = _uiState.value.copy(selectedBrandIds = updated)
        prefs.edit().putString(KEY_BRAND_IDS, updated.sorted().joinToString(",")).apply()
        viewModelScope.launch { estimatePool() }
    }

    fun clearBrands() {
        _uiState.value = _uiState.value.copy(selectedBrandIds = emptySet())
        prefs.edit().putString(KEY_BRAND_IDS, "").apply()
        viewModelScope.launch { estimatePool() }
    }

    private suspend fun estimatePool() {
        _uiState.value = _uiState.value.copy(isEstimating = true)
        val pairs = resolveSoloSingerPairs(idolRepository, songRepository, _uiState.value.selectedBrandIds)
        _uiState.value = _uiState.value.copy(
            estimatedSongs = pairs.size,
            estimatedSingers = pairs.map { it.second.id }.toSet().size,
            isEstimating = false
        )
    }

    private fun decodeBrandIds(raw: String): Set<String> = raw.split(",").filter { it.isNotEmpty() }.toSet()

    companion object {
        private const val PREFS_NAME = "quiz_setup_prefs"
        private const val KEY_BRAND_IDS = "song_quiz_brand_ids"
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SongSingerQuizSetupScreen(
    onBack: () -> Unit,
    onStart: (Set<String>) -> Unit,
    viewModel: SongSingerQuizSetupViewModel = viewModel()
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()

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
            QuizSetupHeaderCard(
                icon = Icons.Filled.MusicNote, title = "ソロ曲クイズ",
                subtitle = "ソロ曲を聴いてその歌手を 4 択で当てよう"
            )
            QuizSetupBrandSection(
                brands = state.brands, selectedBrandIds = state.selectedBrandIds,
                onToggle = { viewModel.toggleBrand(it) }, onClearAll = { viewModel.clearBrands() }
            )
            QuizSetupCountRow(isEstimating = state.isEstimating) {
                Column {
                    Text(
                        "出題候補: ${state.estimatedSongs} 曲 / ${state.estimatedSingers} 歌手",
                        fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = DS.ink
                    )
                    Text("4択の選択肢は歌手数が基準です", fontSize = 12.sp, color = DS.ink3)
                }
            }
            if (!state.isEstimating && !state.canStart) {
                QuizSetupInsufficientBanner("4 択を出すには原唱歌手が最低 4 名必要です。ブランドの選択を増やしてください。")
            }
            QuizPrimaryButton(title = "スタート") { if (state.canStart) onStart(state.selectedBrandIds) }
        }
    }
}
