package com.fugaif.imaslivedb.ui.timeline

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.TimelineBarRecord

data class BrandTimelineUiState(
    val brands: List<Brand> = emptyList(),
    val selectedBrandId: String? = null,
    val bars: List<TimelineBarRecord> = emptyList(),
    val isLoading: Boolean = true
) {
    val selectedBrand: Brand? get() = brands.firstOrNull { it.id == selectedBrandId }
}

/**
 * 年表 (ブランド史) の ViewModel。iOS `BrandTimelineViewModel` の移植。
 *
 * ここが持つのは**データと選択ブランドだけ**。ズーム倍率やスクロール位置のような
 * 「見え方の状態」は画面側 (Composable) に置く — 回転や再生成で位置がリセットされるのは
 * 許容できるが、パン量が ViewModel に居ると描画と状態の同期先が 2 つになる。
 */
class BrandTimelineViewModel(
    app: Application,
    private val initialBrandId: String?
) : AndroidViewModel(app) {

    private val events = AppModule.from(app).eventRepository
    private val stats = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(BrandTimelineUiState())
    val uiState: StateFlow<BrandTimelineUiState> = _uiState.asStateFlow()

    init { load() }

    private fun load() {
        viewModelScope.launch {
            val all = runCatching { stats.fetchBrands() }.getOrDefault(emptyList())
            // "other" は寄せ集めで年表として読めないので選択肢から外す (全ブランド表示には含む)。
            val selectable = all.filter { it.id != "other" }
            // 初期表示は 1 ブランド。全ブランドは 20 年 × 全レーンで段数が多くなりすぎ、
            // 「最初の一目」で歴史を感じ取らせるという目的に対して情報過多になる。
            val initial = initialBrandId?.takeIf { id -> selectable.any { it.id == id } }
                ?: selectable.firstOrNull()?.id
            _uiState.value = _uiState.value.copy(brands = selectable, selectedBrandId = initial)
            loadBars(initial)
        }
    }

    fun select(brandId: String?) {
        if (brandId == _uiState.value.selectedBrandId) return
        _uiState.value = _uiState.value.copy(selectedBrandId = brandId)
        viewModelScope.launch { loadBars(brandId) }
    }

    private suspend fun loadBars(brandId: String?) {
        _uiState.value = _uiState.value.copy(isLoading = true)
        val bars = runCatching { events.fetchTimelineBars(brandId) }.getOrDefault(emptyList())
        _uiState.value = _uiState.value.copy(bars = bars, isLoading = false)
    }

    class Factory(
        private val app: Application,
        private val initialBrandId: String?
    ) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <T : ViewModel> create(modelClass: Class<T>): T =
            BrandTimelineViewModel(app, initialBrandId) as T
    }
}
