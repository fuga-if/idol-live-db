package com.fugaif.imaslivedb.ui.settings

import android.app.Application
import android.content.Context
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
    /** iOS `@AppStorage("defaultBrandId")` に相当。空文字は「すべて」。 */
    val defaultBrandId: String = "",
    val isLoading: Boolean = true
)

class SettingsViewModel(app: Application) : AndroidViewModel(app) {

    private val statsRepo = AppModule.from(app).statsRepository
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(SettingsUiState(defaultBrandId = prefs.getString(KEY_DEFAULT_BRAND, "") ?: ""))
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

            _uiState.value = _uiState.value.copy(
                schemaVersion = schemaVersion,
                dataVersion = dataVersion,
                databaseStats = databaseStats,
                brands = brands,
                isLoading = false
            )
        }
    }

    /** デフォルトブランドを永続化する。iOS `MyPageView` の `defaultBrandId` と同じキー意味。 */
    fun setDefaultBrand(brandId: String?) {
        val value = brandId ?: ""
        prefs.edit().putString(KEY_DEFAULT_BRAND, value).apply()
        _uiState.value = _uiState.value.copy(defaultBrandId = value)
    }

    companion object {
        private const val PREFS_NAME = "imas_settings"
        private const val KEY_DEFAULT_BRAND = "default_brand_id"
    }
}
