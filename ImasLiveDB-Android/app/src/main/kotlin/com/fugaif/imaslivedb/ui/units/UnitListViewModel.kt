package com.fugaif.imaslivedb.ui.units

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.ImasUnit
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class UnitListMode { LIST, GRID }

data class UnitListUiState(
    val units: List<ImasUnit> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val searchText: String = "",
    val collapsedBrands: Set<String> = emptySet(),
    val listMode: UnitListMode = UnitListMode.LIST,
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false
)

/**
 * ユニット一覧。`IdolListScreen`/`IdolListViewModel` と同じ骨格 (ブランド別グルーピング + list/grid 切替 + 検索)を
 * 「曲ありユニットのみ」に適用したもの。ユニットにはアイドルのような担当/お気に入りマークが無いため
 * フィルタシートは持たない。
 */
class UnitListViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).unitRepository
    private val statsRepo = AppModule.from(app).statsRepository
    private val syncEngine = AppModule.from(app).syncEngine
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(
        UnitListUiState(
            isLoading = true,
            listMode = if (prefs.getString(KEY_LIST_MODE, null) == VALUE_GRID) UnitListMode.GRID else UnitListMode.LIST
        )
    )
    val uiState: StateFlow<UnitListUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val brands = statsRepo.fetchBrands()
            val units = repo.fetchUnitsForList()
            _uiState.value = _uiState.value.copy(brands = brands, units = units, isLoading = false)
        }
    }

    /** Pull-to-refresh: 増分同期してから再読込。 */
    fun refresh() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isRefreshing = true)
            runCatching { syncEngine.sync() }
            load()
            _uiState.value = _uiState.value.copy(isRefreshing = false)
        }
    }

    fun setSearchText(text: String) {
        _uiState.value = _uiState.value.copy(searchText = text)
    }

    fun toggleBrandCollapse(brandId: String) {
        val current = _uiState.value.collapsedBrands.toMutableSet()
        if (!current.add(brandId)) current.remove(brandId)
        _uiState.value = _uiState.value.copy(collapsedBrands = current)
    }

    fun setListMode(mode: UnitListMode) {
        prefs.edit().putString(KEY_LIST_MODE, if (mode == UnitListMode.GRID) VALUE_GRID else VALUE_LIST).apply()
        _uiState.value = _uiState.value.copy(listMode = mode)
    }

    companion object {
        private const val PREFS_NAME = "unit_list_prefs"
        private const val KEY_LIST_MODE = "list_mode"
        private const val VALUE_GRID = "grid"
        private const val VALUE_LIST = "list"
    }
}
