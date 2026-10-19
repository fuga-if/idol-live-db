package com.fugaif.imaslivedb.ui.stats

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.repository.CommunityRanking
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.CommunityRankingKind

data class CommunityRankingUiState(
    val kind: CommunityRankingKind = CommunityRankingKind.POPULAR,
    val brandId: String? = null,
    val brands: List<Brand> = emptyList(),
    /** null は集計を取れなかったとき。 */
    val ranking: CommunityRanking? = null,
    val isLoading: Boolean = true
)

/** みんなのランキング全体 (上位 [LIMIT] 件)。順位の決め方はコア。 */
class CommunityRankingViewModel(app: Application) : AndroidViewModel(app) {
    private val statsRepo = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(CommunityRankingUiState())
    val uiState: StateFlow<CommunityRankingUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(brands = statsRepo.fetchBrands())
        }
        load()
    }

    fun selectKind(kind: CommunityRankingKind) {
        _uiState.value = _uiState.value.copy(kind = kind)
        load()
    }

    fun selectBrand(brandId: String?) {
        _uiState.value = _uiState.value.copy(brandId = brandId)
        load()
    }

    private fun load() {
        val requested = _uiState.value
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            val ranking = statsRepo.fetchCommunityRanking(requested.kind, requested.brandId, LIMIT)
            // 読んでいる間に切り替えられていたら、古い結果で上書きしない。
            if (_uiState.value.kind == requested.kind && _uiState.value.brandId == requested.brandId) {
                _uiState.value = _uiState.value.copy(ranking = ranking, isLoading = false)
            }
        }
    }

    private companion object {
        const val LIMIT = 100
    }
}
