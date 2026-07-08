package com.fugaif.imaslivedb.ui.stats

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.BrandCollectionProgress
import com.fugaif.imaslivedb.data.model.BrandSongCount
import com.fugaif.imaslivedb.data.model.CastShowCount
import com.fugaif.imaslivedb.data.model.DatabaseStats
import com.fugaif.imaslivedb.data.model.FavoriteRankingEntry
import com.fugaif.imaslivedb.data.model.Show
import com.fugaif.imaslivedb.data.model.SongPlayCount
import com.fugaif.imaslivedb.data.model.UncollectedSong
import com.fugaif.imaslivedb.data.model.UpcomingCatchChance
import com.fugaif.imaslivedb.data.model.YearlyShowCount
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** 未回収リストのスコープ (iOS UncollectedScope の移植)。 */
enum class UncollectedScope { MY_PICK, ALL }

data class StatsUiState(
    val isLoading: Boolean = true,

    // 回収サマリー + ブランド別回収率
    val overallCollected: Int = 0,
    val overallTotal: Int = 0,
    val brandProgress: List<BrandCollectionProgress> = emptyList(),

    // この公演で聴けるかも
    val catchChances: List<UpcomingCatchChance> = emptyList(),

    // まだ生で聴けていない曲
    val isLoadingDashboard: Boolean = true,
    val uncollectedScope: UncollectedScope = UncollectedScope.MY_PICK,
    val pickUncollected: List<UncollectedSong> = emptyList(),
    val allUncollected: List<UncollectedSong> = emptyList(),
    val myPickCollected: Int = 0,
    val myPickTotal: Int = 0,

    // 最新の動き
    val latestShow: Show? = null,
    val latestShowSongCount: Int = 0,
    val latestShowBrandColor: String? = null,

    // コミュニティの熱量
    val brands: List<Brand> = emptyList(),
    val favoriteBrandId: String? = null,
    val favoritesRanking: List<FavoriteRankingEntry> = emptyList(),
    val isLoadingFavorites: Boolean = false,

    // 活動量 / マスタ規模 (既存)
    val brandSongCounts: List<BrandSongCount> = emptyList(),
    val yearlyShowCounts: List<YearlyShowCount> = emptyList(),
    val songPlayCounts: List<SongPlayCount> = emptyList(),
    val castShowCounts: List<CastShowCount> = emptyList(),
    val databaseStats: DatabaseStats? = null
) {
    val uncollectedSongs: List<UncollectedSong>
        get() = if (uncollectedScope == UncollectedScope.MY_PICK) pickUncollected else allUncollected
}

class StatsViewModel(app: Application) : AndroidViewModel(app) {

    private val statsRepo = AppModule.from(app).statsRepository
    private val songRepo = AppModule.from(app).songRepository
    private val idolRepo = AppModule.from(app).idolRepository
    private val eventRepo = AppModule.from(app).eventRepository
    private val userMarkRepo = AppModule.from(app).userMarkRepository

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
            val brands = statsRepo.fetchBrands()

            val latestShow = eventRepo.fetchLatestShow()
            val latestShowSongCount = latestShow?.let { statsRepo.fetchLatestShowSongCount(it.id) } ?: 0
            val latestShowBrandColor = latestShow?.let { show ->
                val event = eventRepo.fetchEvent(show.eventId)
                brands.firstOrNull { it.id == event?.brandId }?.color
            }

            _uiState.value = _uiState.value.copy(
                brandSongCounts = brandSongCounts,
                yearlyShowCounts = yearlyShowCounts,
                songPlayCounts = songPlayCounts,
                castShowCounts = castShowCounts,
                databaseStats = databaseStats,
                brands = brands,
                latestShow = latestShow,
                latestShowSongCount = latestShowSongCount,
                latestShowBrandColor = latestShowBrandColor,
                isLoading = false
            )
        }
        loadDashboard()
        loadFavoritesRanking()
    }

    /** 回収ダッシュボードの重い集計 (iOS StatsView.loadDashboard の移植)。 */
    private fun loadDashboard() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingDashboard = true)
            val collectedIds = userMarkRepo.autoCollectedSongIds()
            val pickIdolIds = userMarkRepo.pickedIdolIds()
            val dashboard = statsRepo.fetchCollectionDashboard(collectedIds, pickIdolIds)
            _uiState.value = _uiState.value.copy(
                overallCollected = dashboard.overallCollected,
                overallTotal = dashboard.overallTotal,
                brandProgress = dashboard.brandProgress,
                pickUncollected = dashboard.pickUncollected,
                allUncollected = dashboard.allUncollected,
                myPickCollected = dashboard.myPickCollected,
                myPickTotal = dashboard.myPickTotal,
                catchChances = dashboard.catchChances,
                isLoadingDashboard = false
            )
        }
    }

    fun setUncollectedScope(scope: UncollectedScope) {
        _uiState.value = _uiState.value.copy(uncollectedScope = scope)
    }

    fun selectFavoriteBrand(brandId: String?) {
        _uiState.value = _uiState.value.copy(favoriteBrandId = brandId)
        loadFavoritesRanking()
    }

    private fun loadFavoritesRanking() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoadingFavorites = true)
            val ranking = statsRepo.fetchFavoritesRanking(_uiState.value.favoriteBrandId, limit = 20)
            _uiState.value = _uiState.value.copy(favoritesRanking = ranking, isLoadingFavorites = false)
        }
    }
}
