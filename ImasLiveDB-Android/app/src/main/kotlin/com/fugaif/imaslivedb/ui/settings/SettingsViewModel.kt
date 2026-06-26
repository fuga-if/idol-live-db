package com.fugaif.imaslivedb.ui.settings

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SettingsUiState(
    val schemaVersion: String = "...",
    val dataVersion: String = "...",
    val databaseStats: DatabaseStats? = null,
    val brands: List<Brand> = emptyList(),
    val isLoading: Boolean = true
)

class SettingsViewModel(app: Application) : AndroidViewModel(app) {

    private val statsRepo = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val schemaVersion = statsRepo.fetchMetaValue("schema_version") ?: "不明"
            val dataVersion = statsRepo.fetchMetaValue("data_version") ?: "不明"
            val databaseStats = statsRepo.fetchDatabaseStats()
            val brands = statsRepo.fetchBrands()

            _uiState.value = SettingsUiState(
                schemaVersion = schemaVersion,
                dataVersion = dataVersion,
                databaseStats = databaseStats,
                brands = brands,
                isLoading = false
            )
        }
    }
}
