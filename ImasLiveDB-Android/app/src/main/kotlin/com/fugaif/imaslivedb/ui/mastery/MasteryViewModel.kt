package com.fugaif.imaslivedb.ui.mastery

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.local.localWrite
import com.fugaif.imaslivedb.data.model.Brand
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.di.AppModule
import com.fugaif.imaslivedb.ui.theme.AppPreferences
import com.fugaif.imaslivedb.ui.theme.MasteryScale
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.MasteryAxis
import uniffi.imas_core.MasteryBulkScope
import uniffi.imas_core.MasteryGroup
import uniffi.imas_core.MasteryGroupSort
import uniffi.imas_core.MasteryProgressFilter
import uniffi.imas_core.MasterySong
import uniffi.imas_core.MasterySummary
import uniffi.imas_core.buildMasteryGroups
import uniffi.imas_core.masteryBulkTargets
import uniffi.imas_core.masterySummary

/** 群の詳細に渡す一式。曲の実体は開かれてから引く。 */
data class MasteryDetailState(
    val group: MasteryGroup,
    val songs: List<Song>,
    val collectedIds: Set<String>,
)

data class MasteryUiState(
    val isLoading: Boolean = true,
    val brands: List<Brand> = emptyList(),
    val axis: MasteryAxis = MasteryAxis.SERIES,
    val brandIds: Set<String> = emptySet(),
    val progress: MasteryProgressFilter = MasteryProgressFilter.ALL,
    val sort: MasteryGroupSort = MasteryGroupSort.SONG_COUNT,
    val nameFilter: String = "",
    val groups: List<MasteryGroup> = emptyList(),
    val summary: MasterySummary = MasterySummary(0u, 0u, 0u, 0u),
    /** 段ごとの曲数 (index 0 が LV.1)。絞り込んだ範囲で数える。 */
    val stageCounts: List<Int> = emptyList(),
    val scopedCount: Int = 0,
    val scale: MasteryScale = MasteryScale.standard,
) {
    val isFilterActive: Boolean
        get() = brandIds.isNotEmpty() || progress != MasteryProgressFilter.ALL ||
            sort != MasteryGroupSort.SONG_COUNT
}

/**
 * 習熟度ダッシュボード。iOS `MasteryView` の移植。
 *
 * 群化・並び・絞り込み・集計は**全部コア** (`imas-core` の `domain/mastery.rs`)。
 * ここは「曲とマークを集めて 1 回渡し、返ってきた群を state に置く」だけ。
 *
 * ⚠️ 集計は Composable から毎回呼ばない。ユニット軸は 1,000 群を超えるうえ、
 * 2,000 曲ぶんの射影を FFI へ渡すので、打鍵や再描画のたびに走らせると目に見えて重い。
 * 条件が変わったときだけ [recompute] を回し、打鍵はデバウンスする。
 */
class MasteryViewModel(app: Application) : AndroidViewModel(app) {

    private val songRepo = AppModule.from(app).songRepository
    private val marks = AppModule.from(app).userMarkRepository
    private val stats = AppModule.from(app).statsRepository

    private val _uiState = MutableStateFlow(MasteryUiState())
    val uiState: StateFlow<MasteryUiState> = _uiState.asStateFlow()

    /** ブランド絞り込みの母集合。読み直さずに使い回す。 */
    private var allSongs: List<Song> = emptyList()
    private var levels: Map<String, UByte> = emptyMap()
    private var collected: Set<String> = emptySet()
    private var recomputeJob: Job? = null

    init {
        viewModelScope.launch {
            allSongs = songRepo.fetchMasterySongs()
            levels = marks.masteryLevels()
            collected = songRepo.fetchCollectedSongIds()
            _uiState.value = _uiState.value.copy(
                brands = stats.fetchBrands(),
                scale = AppPreferences.masteryScale,
                isLoading = false,
            )
            recompute(immediate = true)
        }
    }

    fun setAxis(value: MasteryAxis) { update { it.copy(axis = value) } }
    fun setProgress(value: MasteryProgressFilter) { update { it.copy(progress = value) } }
    fun setSort(value: MasteryGroupSort) { update { it.copy(sort = value) } }
    fun setNameFilter(value: String) { update { it.copy(nameFilter = value) } }
    fun clearBrands() { update { it.copy(brandIds = emptySet()) } }
    fun resetFilters() {
        update {
            it.copy(brandIds = emptySet(), progress = MasteryProgressFilter.ALL,
                    sort = MasteryGroupSort.SONG_COUNT)
        }
    }

    fun toggleBrand(id: String) = update {
        it.copy(brandIds = if (it.brandIds.contains(id)) it.brandIds - id else it.brandIds + id)
    }

    private fun update(block: (MasteryUiState) -> MasteryUiState) {
        _uiState.value = block(_uiState.value)
        recompute()
    }

    /** 一括更新。対象の決め方はコア ([masteryBulkTargets])。 */
    fun applyBulk(group: MasteryGroup, scope: MasteryBulkScope, level: UByte) {
        viewModelScope.launch {
            val targets = masteryBulkTargets(group.songIds, group.levels, scope)
            if (targets.isEmpty()) return@launch
            localWrite("習熟度の記録") { marks.setMastery(targets, level) } ?: return@launch
            onMarksChanged()
        }
    }

    fun setMastery(songId: String, level: UByte) {
        viewModelScope.launch {
            localWrite("習熟度の記録") { marks.setMastery(songId, level) } ?: return@launch
            onMarksChanged()
        }
    }

    /** 段階を書き換えた後の後始末 (再集計 + 開いていれば詳細も差し替え)。 */
    private suspend fun onMarksChanged() {
        levels = marks.masteryLevels()
        // 詳細の数も群から出すので、群を作り直してから差し替える ([recompute] の終わり)。
        recompute(immediate = true)
    }

    // ---- 群の詳細 (画面内で完結させる。ナビは触らない = StatsScreen と同じ流儀) ----

    private val _detail = MutableStateFlow<MasteryDetailState?>(null)
    val detail: StateFlow<MasteryDetailState?> = _detail.asStateFlow()

    fun openGroup(group: MasteryGroup) {
        viewModelScope.launch {
            // 曲の実体は**開かれてから**引く。一覧側で引くと群の数だけ走る。
            val byId = songRepo.fetchSongsByIds(group.songIds).associateBy { it.id }
            _detail.value = MasteryDetailState(
                group = group,
                songs = group.songIds.mapNotNull { byId[it] },
                collectedIds = collected,
            )
        }
    }

    fun closeGroup() { _detail.value = null }

    private fun refreshDetail() {
        val current = _detail.value ?: return
        val refreshed = _uiState.value.groups.firstOrNull { it.key == current.group.key }
        _detail.value = current.copy(group = refreshed ?: current.group)
    }

    private fun recompute(immediate: Boolean = false) {
        recomputeJob?.cancel()
        recomputeJob = viewModelScope.launch {
            // 打鍵ごとに 2,000 件を FFI へ渡さないよう少しだけ待つ。
            if (!immediate) delay(180)
            val s = _uiState.value
            val steps = s.scale.steps
            val scoped = if (s.brandIds.isEmpty()) allSongs
                         else allSongs.filter { it.brandId in s.brandIds }
            val entries = scoped.map { song ->
                MasterySong(
                    songId = song.id, title = song.title,
                    seriesGroup = song.seriesGroup, cdSeries = song.cdSeries,
                    unitName = song.unitName, singerLabel = song.singerLabel,
                    releaseDate = song.releaseDate,
                    level = levels[song.id] ?: 0u,
                    collected = song.id in collected,
                )
            }
            val counts = IntArray(steps.toInt())
            entries.forEach { e ->
                val i = minOf(e.level, steps).toInt() - 1
                if (i in counts.indices) counts[i]++
            }
            _uiState.value = _uiState.value.copy(
                groups = buildMasteryGroups(entries, s.axis, steps, s.sort, s.progress, s.nameFilter),
                summary = masterySummary(entries, steps),
                stageCounts = counts.toList(),
                scopedCount = scoped.size,
            )
            refreshDetail()
        }
    }
}
