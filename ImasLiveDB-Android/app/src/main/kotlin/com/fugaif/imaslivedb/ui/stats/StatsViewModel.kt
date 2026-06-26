package com.fugaif.imaslivedb.ui.stats

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.BrandSongCount
import com.fugaif.imaslivedb.data.model.CastShowCount
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.SongPlayCount
import com.fugaif.imaslivedb.data.model.YearlyShowCount
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class StatsUiState(
    val brandSongCounts: List<BrandSongCount> = emptyList(),
    val yearlyShowCounts: List<YearlyShowCount> = emptyList(),
    val songPlayCounts: List<SongPlayCount> = emptyList(),
    val castShowCounts: List<CastShowCount> = emptyList(),
    val databaseStats: DatabaseStats? = null,
    val isLoading: Boolean = true
)

class StatsViewModel(app: Application) : AndroidViewModel(app) {

    private val statsRepo = AppModule.from(app).statsRepository
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository

    private val _uiState = MutableStateFlow(StatsUiState())
    val uiState: StateFlow<StatsUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    private fun load() {
        viewModelScope.launch {
            val brandSongCounts = statsRepo.fetchBrandSongCounts()
            val yearlyShowCounts = statsRepo.fetchYearlyShowCounts()
            val songPlayCounts = songRepo.fetchSongPlayCountRanking(20)
            val castShowCounts = idolRepo.fetchIdolShowCountRanking(20)
            val databaseStats = statsRepo.fetchDatabaseStats()

            _uiState.value = StatsUiState(
                brandSongCounts = brandSongCounts,
                yearlyShowCounts = yearlyShowCounts,
                songPlayCounts = songPlayCounts,
                castShowCounts = castShowCounts,
                databaseStats = databaseStats,
                isLoading = false
            )
        }
    }
}
