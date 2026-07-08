package com.fugaif.imaslivedb.ui.songs

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.model.SongCollectFilter
import com.fugaif.imaslivedb.data.model.SongMyMarkFilter
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SongListUiState(
    val isLoading: Boolean = true,
    val songs: List<SongWithArtists> = emptyList(),
    val searchText: String = "",
    val filter: SongSearchFilter = SongSearchFilter(),
    val sortOrder: SongSortOrder = SongSortOrder.TITLE_KANA,
    // nil = sortOrder のデフォルト方向 (iOS と同じ tri-state)。
    val sortAscending: Boolean? = null,
    // ブランド未選択(全件)時に「その他」(歌枠カバー等 brand_id='other') を出すか。既定 OFF で隠す。
    val showOtherBrand: Boolean = false,
    val collectFilter: SongCollectFilter = SongCollectFilter.ALL,
    val myMarkFilter: SongMyMarkFilter = SongMyMarkFilter(),
    // タグ絞り込み (TagFilterSheet) で選択中のタグ。複数選択時は AND (全タグを含む曲) で絞る。
    val selectedTags: List<CommunityApi.CommunityTag> = emptyList(),
    // 行アイコン用のマーク集合・回収数 (song_id ベース)。
    val favoriteSongIds: Set<String> = emptySet(),
    val myPickSongIds: Set<String> = emptySet(),
    val collectedCounts: Map<String, Int> = emptyMap(),
    // タグ絞り込み中(単一タグ選択時のみ)の song_id → 票数。
    val tagVoteCounts: Map<String, Int> = emptyMap()
) {
    val activeFilterCount: Int get() = filter.activeFilterCount
    /** ツールバーのフィルタバッジ件数。表示形式以外の絞り込み状態も含める。 */
    val filterBadgeCount: Int
        get() {
            var count = activeFilterCount
            if (collectFilter != SongCollectFilter.ALL) count++
            count += myMarkFilter.activeCount
            return count
        }
}

class SongListViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SongListUiState())
    val uiState: StateFlow<SongListUiState> = _uiState.asStateFlow()

    private var loadJob: Job? = null
    private var appContext: Context? = null

    fun init(context: Context) {
        appContext = context.applicationContext
        loadSongs()
    }

    fun setSearchText(text: String) {
        _uiState.value = _uiState.value.copy(searchText = text)
        loadSongs()
    }

    fun applyFilter(
        filter: SongSearchFilter,
        sortOrder: SongSortOrder,
        sortAscending: Boolean?,
        showOtherBrand: Boolean,
        collectFilter: SongCollectFilter,
        myMarkFilter: SongMyMarkFilter
    ) {
        _uiState.value = _uiState.value.copy(
            filter = filter,
            sortOrder = sortOrder,
            sortAscending = sortAscending,
            showOtherBrand = showOtherBrand,
            collectFilter = collectFilter,
            myMarkFilter = myMarkFilter
        )
        loadSongs()
    }

    fun applyTagFilter(tags: List<CommunityApi.CommunityTag>) {
        _uiState.value = _uiState.value.copy(selectedTags = tags)
        loadSongs()
    }

    /** 除去可能フィルタチップからの個別解除 (担当)。 */
    fun clearMyPickFilter() {
        _uiState.value = _uiState.value.copy(myMarkFilter = _uiState.value.myMarkFilter.copy(requireMyPick = false))
        loadSongs()
    }

    /** 除去可能フィルタチップからの個別解除 (お気に入り)。 */
    fun clearFavoriteFilter() {
        _uiState.value = _uiState.value.copy(myMarkFilter = _uiState.value.myMarkFilter.copy(requireFavorite = false))
        loadSongs()
    }

    /** 除去可能フィルタチップからの個別解除 (回収済み/未回収)。 */
    fun clearCollectFilter() {
        _uiState.value = _uiState.value.copy(collectFilter = SongCollectFilter.ALL)
        loadSongs()
    }

    /** 除去可能フィルタチップからの個別解除 (タグ)。 */
    fun removeTag(tag: CommunityApi.CommunityTag) {
        applyTagFilter(_uiState.value.selectedTags.filter { it.id != tag.id })
    }

    fun resetAllFilters() {
        _uiState.value = _uiState.value.copy(
            filter = SongSearchFilter(),
            sortOrder = SongSortOrder.TITLE_KANA,
            sortAscending = null,
            showOtherBrand = false,
            collectFilter = SongCollectFilter.ALL,
            myMarkFilter = SongMyMarkFilter(),
            selectedTags = emptyList()
        )
        loadSongs()
    }

    /** 一覧行のお気に入り☆をタップしたときの ON/OFF トグル。 */
    fun toggleFavorite(songId: String) {
        val ctx = appContext ?: return
        viewModelScope.launch {
            val on = AppModule.from(ctx).userMarkRepository.toggle(UserMark.SONG, songId, UserMark.FAVORITE)
            val current = _uiState.value.favoriteSongIds
            _uiState.value = _uiState.value.copy(
                favoriteSongIds = if (on) current + songId else current - songId
            )
        }
    }

    private fun loadSongs() {
        val ctx = appContext ?: return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            val state = _uiState.value
            val module = AppModule.from(ctx)
            val effectiveFilter = (
                if (state.searchText.isNotEmpty()) state.filter.copy(title = state.searchText) else state.filter
                ).copy(includeOtherBrand = state.showOtherBrand)

            // タグ絞り込み: Worker D1 (コミュニティタグ) は端末外データなので、選択中タグそれぞれの
            // 詳細 (付いた曲の song_id 一覧) を取得して AND (積集合) を取る。
            val tagFilterSongIds = if (state.selectedTags.isNotEmpty()) {
                val sets = state.selectedTags.map { tag ->
                    runCatching { module.communityApi.tagDetail(tag.id) }
                        .getOrNull()?.songs?.map { it.songId }?.toSet() ?: emptySet()
                }
                sets.reduce { acc, s -> acc intersect s }
            } else {
                null
            }
            // 単一タグ選択時のみ、行バッジ用の票数を保持する (iOS tagVoteCounts 相当)。
            val tagVoteCounts = if (state.selectedTags.size == 1) {
                runCatching { module.communityApi.tagDetail(state.selectedTags[0].id) }
                    .getOrNull()?.songs?.associate { it.songId to it.voteCount } ?: emptyMap()
            } else {
                emptyMap()
            }

            var songs = module.songRepository.fetchSongs(
                filter = effectiveFilter,
                sortOrder = state.sortOrder,
                ascending = state.sortAscending,
                tagFilterSongIds = tagFilterSongIds
            )

            // 行アイコン用のマーク集合・回収数 (マイマーク/回収フィルタにも使う)。
            val marks = module.userMarkRepository
            val favoriteIds = marks.favoriteSongIds()
            val pickIdolIds = marks.pickedIdolIds()
            val myPickIds = module.songRepository.fetchSongIdsWithAnyArtist(pickIdolIds)
            val collectedCounts = module.songRepository.fetchSongCollectedCounts()

            // マイマーク / 回収 絞り込み (取得後にメモリ上で適用。iOS applySongMarkFilters 相当)。
            if (state.myMarkFilter.requireFavorite) {
                songs = songs.filter { favoriteIds.contains(it.song.id) }
            }
            if (state.myMarkFilter.requireMyPick) {
                songs = songs.filter { myPickIds.contains(it.song.id) }
            }
            when (state.collectFilter) {
                SongCollectFilter.COLLECTED -> songs = songs.filter { (collectedCounts[it.song.id] ?: 0) > 0 }
                SongCollectFilter.UNCOLLECTED -> songs = songs.filter { (collectedCounts[it.song.id] ?: 0) == 0 }
                SongCollectFilter.ALL -> {}
            }

            _uiState.value = _uiState.value.copy(
                isLoading = false,
                songs = songs,
                favoriteSongIds = favoriteIds,
                myPickSongIds = myPickIds,
                collectedCounts = collectedCounts,
                tagVoteCounts = tagVoteCounts
            )
        }
    }
}
