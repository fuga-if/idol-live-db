package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class IdolListUiState(
    val idols: List<Idol> = emptyList(),
    val brands: List<Brand> = emptyList(),
    val selectedBrandId: String? = null,
    val searchText: String = "",
    val collapsedBrands: Set<String> = emptySet(),
    val isLoading: Boolean = false
)

class IdolListViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).idolRepository
    private val statsRepo = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(IdolListUiState(isLoading = true))
    val uiState: StateFlow<IdolListUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val brands = statsRepo.fetchBrands()
            val idols = repo.fetchIdols()
            _uiState.value = _uiState.value.copy(
                brands = brands,
                idols = idols,
                isLoading = false
            )
        }
    }

    fun selectBrand(brandId: String?) {
        _uiState.value = _uiState.value.copy(selectedBrandId = brandId)
    }

    fun setSearchText(text: String) {
        _uiState.value = _uiState.value.copy(searchText = text)
    }

    fun toggleBrandCollapse(brandId: String) {
        val current = _uiState.value.collapsedBrands.toMutableSet()
        if (current.contains(brandId)) current.remove(brandId) else current.add(brandId)
        _uiState.value = _uiState.value.copy(collapsedBrands = current)
    }

    fun filteredIdolsForBrand(brandId: String): List<Idol> {
        val state = _uiState.value
        var result = state.idols.filter { it.brandId == brandId }
        if (state.selectedBrandId != null && state.selectedBrandId != brandId) return emptyList()
        if (state.searchText.isNotEmpty()) {
            val q = state.searchText.lowercase()
            result = result.filter { idol ->
                idol.name.lowercase().contains(q) ||
                    idol.nameKana?.lowercase()?.contains(q) == true
            }
        }
        return result
    }

    fun visibleBrands(): List<Brand> {
        val state = _uiState.value
        return state.brands.filter { filteredIdolsForBrand(it.id).isNotEmpty() }
    }
}
