package com.fugaif.imaslivedb.ui.idols

import android.app.Application
import android.content.Context
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class IdolDisplayMode { IDOL_NAME, CV_NAME }
enum class IdolListMode { LIST, GRID }

/**
 * ブランド内サブカテゴリ属性 (idols.attribute) の定義。(内部値, 表示ラベル)。
 * iOS `FilterSheet.swift` の `brandAttributes` と同一。
 */
val IDOL_BRAND_ATTRIBUTES: Map<String, List<Pair<String, String>>> = mapOf(
    "cg" to listOf("cute" to "キュート", "cool" to "クール", "passion" to "パッション"),
    "ml" to listOf("princess" to "プリンセス", "fairy" to "フェアリー", "angel" to "エンジェル"),
    "765as" to listOf("princess" to "プリンセス", "fairy" to "フェアリー", "angel" to "エンジェル"),
    "sidem" to listOf("intelli" to "インテリ", "physical" to "フィジカル", "mental" to "メンタル"),
    "sc" to listOf("sol" to "Sol", "luna" to "Luna", "stella" to "Stella")
)

data class IdolListUiState(
    val idols: List<Idol> = emptyList(),
    val brands: List<Brand> = emptyList(),
    /** idol_id → 現役CV名 (name/nameKana に加えて検索対象にする)。 */
    val castNames: Map<String, String> = emptyMap(),
    val selectedBrandIds: Set<String> = emptySet(),
    val selectedAttribute: String? = null,
    val searchText: String = "",
    val collapsedBrands: Set<String> = emptySet(),
    val displayMode: IdolDisplayMode = IdolDisplayMode.IDOL_NAME,
    val showCV: Boolean = false,
    val listMode: IdolListMode = IdolListMode.LIST,
    val requireMyPick: Boolean = false,
    val requireFavorite: Boolean = false,
    val requireNote: Boolean = false,
    val pickIds: Set<String> = emptySet(),
    val favoriteIds: Set<String> = emptySet(),
    val noteIds: Set<String> = emptySet(),
    val isLoading: Boolean = false,
    val isRefreshing: Boolean = false
) {
    val activeFilterCount: Int
        get() = (if (selectedBrandIds.isEmpty()) 0 else 1) +
            (if (selectedAttribute != null) 1 else 0) +
            (if (requireMyPick) 1 else 0) +
            (if (requireFavorite) 1 else 0) +
            (if (requireNote) 1 else 0)

    val filterBadgeCount: Int
        get() = activeFilterCount + (if (displayMode != IdolDisplayMode.IDOL_NAME) 1 else 0)
}

/**
 * アイドル一覧の ViewModel。iOS `IdolListViewModel` + `IdolListView` の @AppStorage 相当。
 * フィルタ/グルーピングは Composable 側が収集した state から純粋に算出する
 * (ViewModel が `_uiState.value` を直読みする関数を持つと Compose の依存追跡が壊れ空表示になるため、
 * そういった導出関数はここには置かない)。
 */
class IdolListViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).idolRepository
    private val statsRepo = AppModule.from(app).statsRepository
    private val marksRepo = AppModule.from(app).userMarkRepository
    private val syncEngine = AppModule.from(app).syncEngine
    private val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    private val _uiState = MutableStateFlow(
        IdolListUiState(
            isLoading = true,
            displayMode = if (prefs.getString(KEY_DISPLAY_MODE, null) == VALUE_CV) {
                IdolDisplayMode.CV_NAME
            } else {
                IdolDisplayMode.IDOL_NAME
            },
            showCV = prefs.getBoolean(KEY_SHOW_CV, false),
            listMode = if (prefs.getString(KEY_LIST_MODE, null) == VALUE_GRID) {
                IdolListMode.GRID
            } else {
                IdolListMode.LIST
            }
        )
    )
    val uiState: StateFlow<IdolListUiState> = _uiState.asStateFlow()

    init {
        load()
        refreshMarks()
    }

    private fun load() {
        viewModelScope.launch {
            val brands = statsRepo.fetchBrands()
            val idols = repo.fetchIdolsForList()
            val castNames = idols.mapNotNull { idol -> idol.currentVoiceActor?.let { idol.id to it } }.toMap()
            _uiState.value = _uiState.value.copy(
                brands = brands,
                idols = idols,
                castNames = castNames,
                isLoading = false
            )
        }
    }

    fun refreshMarks() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                pickIds = marksRepo.pickedIdolIds(),
                favoriteIds = marksRepo.favoriteIdolIds(),
                noteIds = marksRepo.notedIdolIds()
            )
        }
    }

    /** Pull-to-refresh: 増分同期してから再読込。 */
    fun refresh() {
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isRefreshing = true)
            runCatching { syncEngine.sync() }
            load()
            refreshMarks()
            _uiState.value = _uiState.value.copy(isRefreshing = false)
        }
    }

    fun toggleMyPick(idolId: String) {
        viewModelScope.launch {
            val now = marksRepo.toggle(UserMark.IDOL, idolId, UserMark.PICK)
            val current = _uiState.value.pickIds.toMutableSet()
            if (now) current.add(idolId) else current.remove(idolId)
            _uiState.value = _uiState.value.copy(pickIds = current)
        }
    }

    fun toggleFavorite(idolId: String) {
        viewModelScope.launch {
            val now = marksRepo.toggle(UserMark.IDOL, idolId, UserMark.FAVORITE)
            val current = _uiState.value.favoriteIds.toMutableSet()
            if (now) current.add(idolId) else current.remove(idolId)
            _uiState.value = _uiState.value.copy(favoriteIds = current)
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

    fun setListMode(mode: IdolListMode) {
        prefs.edit().putString(KEY_LIST_MODE, if (mode == IdolListMode.GRID) VALUE_GRID else VALUE_LIST).apply()
        _uiState.value = _uiState.value.copy(listMode = mode)
    }

    /** ツールバーの「フィルタを解除」相当: ブランド/属性/表示形式のみリセット (マイマークは維持)。 */
    fun clearQuickFilters() {
        prefs.edit().putString(KEY_DISPLAY_MODE, VALUE_IDOL).apply()
        _uiState.value = _uiState.value.copy(
            selectedBrandIds = emptySet(),
            selectedAttribute = null,
            displayMode = IdolDisplayMode.IDOL_NAME
        )
    }

    /** フィルタシートの「適用」。 */
    fun applyFilterSheet(
        brandIds: Set<String>,
        attribute: String?,
        displayMode: IdolDisplayMode,
        showCV: Boolean,
        requireMyPick: Boolean,
        requireFavorite: Boolean,
        requireNote: Boolean
    ) {
        prefs.edit()
            .putString(KEY_DISPLAY_MODE, if (displayMode == IdolDisplayMode.CV_NAME) VALUE_CV else VALUE_IDOL)
            .putBoolean(KEY_SHOW_CV, showCV)
            .apply()
        _uiState.value = _uiState.value.copy(
            selectedBrandIds = brandIds,
            selectedAttribute = attribute,
            displayMode = displayMode,
            showCV = showCV,
            requireMyPick = requireMyPick,
            requireFavorite = requireFavorite,
            requireNote = requireNote
        )
    }

    companion object {
        private const val PREFS_NAME = "idol_list_prefs"
        private const val KEY_DISPLAY_MODE = "display_mode"
        private const val KEY_SHOW_CV = "show_cv"
        private const val KEY_LIST_MODE = "list_mode"
        private const val VALUE_CV = "cv"
        private const val VALUE_IDOL = "idol"
        private const val VALUE_GRID = "grid"
        private const val VALUE_LIST = "list"
    }
}
