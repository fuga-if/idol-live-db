package com.fugaif.imaslivedb.ui.songs

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.core.FuzzySearch
import com.fugaif.imaslivedb.data.model.SongCollectFilter
import com.fugaif.imaslivedb.data.model.SongMyMarkFilter
import com.fugaif.imaslivedb.data.model.SongSearchFilter
import com.fugaif.imaslivedb.data.model.SongSortOrder
import com.fugaif.imaslivedb.data.model.SongWithArtists
import com.fugaif.imaslivedb.data.model.UserMark
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import uniffi.imas_core.SongCollectMode
import uniffi.imas_core.SongListFilterCriteria
import uniffi.imas_core.SongListFilterEntry
import uniffi.imas_core.filterSongList

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
    val tagVoteCounts: Map<String, Int> = emptyMap(),
    // 打った語には部分一致しないが、あいまい一致で拾えた曲 (「もしかして」)。
    // songs と混ぜない。混ぜると「打った通りの曲」がどれか分からなくなるので、
    // 画面では確実な一致の下に、見出しを挟んで別枠で出す。
    val fuzzySongs: List<SongWithArtists> = emptyList()
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

            val criteria = markFilterCriteria(state, favoriteIds, myPickIds, collectedCounts)
            songs = applyMarkFilters(songs, criteria)

            _uiState.value = _uiState.value.copy(
                isLoading = false,
                songs = songs,
                favoriteSongIds = favoriteIds,
                myPickSongIds = myPickIds,
                collectedCounts = collectedCounts,
                tagVoteCounts = tagVoteCounts,
                // 前の語の「もしかして」を残さない (打ち直した直後だけ関係ない曲が下にぶら下がる)。
                fuzzySongs = emptyList()
            )

            // ここから先は表示済みの一覧に後追いで足すだけなので isLoading は倒さない。
            val fuzzy = fuzzyCandidates(module, state, effectiveFilter, criteria, tagFilterSongIds, songs)
            if (fuzzy.isNotEmpty()) {
                _uiState.value = _uiState.value.copy(fuzzySongs = fuzzy)
            }
        }
    }

    /**
     * マイマーク / 回収 絞り込みの条件 (iOS と同じ imas-core song_list_filtering に委譲)。
     *
     * メモ絞り込み・タグ集合絞り込み・タグ票数ランキングはデータ供給側が未実装のため
     * 未配線 (requireNote=false / tagSongIds=null)。
     */
    private fun markFilterCriteria(
        state: SongListUiState,
        favoriteIds: Set<String>,
        myPickIds: Set<String>,
        collectedCounts: Map<String, Int>
    ) = SongListFilterCriteria(
        collectMode = when (state.collectFilter) {
            SongCollectFilter.ALL -> SongCollectMode.ALL
            SongCollectFilter.COLLECTED -> SongCollectMode.COLLECTED
            SongCollectFilter.UNCOLLECTED -> SongCollectMode.UNCOLLECTED
        },
        // Android の回収状態は song_id → 回数の map なので、回収済み (回数 > 0) の集合へ落とす。
        collectedIds = collectedCounts.filterValues { it > 0 }.keys.toList(),
        requireFavorite = state.myMarkFilter.requireFavorite,
        favoriteIds = favoriteIds.toList(),
        requireNote = false,
        noteIds = emptyList(),
        requireMyPick = state.myMarkFilter.requireMyPick,
        myPickSongIds = myPickIds.toList(),
        tagSongIds = null,
        rankByTagVotes = false,
        tagVoteCounts = emptyMap()
    )

    /**
     * 射影 + 採用 index 方式なので FFI 呼び出しはリスト 1 本につき 1 回。
     *
     * あいまい候補にも**同じ条件を通す**こと。通さないと「お気に入りのみ」表示の下に
     * お気に入りでない曲が並ぶ。
     */
    private fun applyMarkFilters(
        songs: List<SongWithArtists>,
        criteria: SongListFilterCriteria
    ): List<SongWithArtists> {
        if (songs.isEmpty()) return songs
        val entries = songs.map {
            SongListFilterEntry(songId = it.song.id, title = it.song.title, titleKana = it.song.titleKana)
        }
        return filterSongList(entries, criteria).map { songs[it.toInt()] }
    }

    /**
     * 「もしかして」候補。打った語には部分一致しないが、あいまい一致で拾えた曲。
     *
     * SQL の `LIKE '%語%'` は打ち間違い・かな入力・音引きの揺れで 0 件になる。そこを
     * コア (imas-core `domain/fuzzy_search.rs`) の編集距離で補う。曲名だけでなく
     * `songs.title_kana` の読みも綴りとして渡すので「おねがいしんでれら」で
     * 「お願い！シンデレラ」が当たる。
     *
     * 打った通りに十分見つかっているときは足さない。既に 30 件出ている画面の末尾に
     * 候補を積んでも読まれず、一致の精度を疑わせるだけになる。
     *
     * ## なぜ候補 id を tagFilterSongIds に載せて引き直すか
     * あいまい一致は綴りしか見ないので、ブランド・リミックス・曲種などの絞り込みを
     * 素通りしてしまう。`tagFilterSongIds` は「この id 集合に限る」通過フィルタなので、
     * ここへ候補を渡せば**現在の絞り込みを全部通した上で**候補だけが返る。
     */
    private suspend fun fuzzyCandidates(
        module: AppModule,
        state: SongListUiState,
        effectiveFilter: SongSearchFilter,
        criteria: SongListFilterCriteria,
        tagFilterSongIds: Set<String>?,
        shown: List<SongWithArtists>
    ): List<SongWithArtists> {
        val needle = state.searchText
        if (needle.isBlank() || shown.size > FuzzySearch.SUGGEST_THRESHOLD) return emptyList()
        // 打鍵のたびに loadSongs が前のジョブを cancel するので、この待ちがそのまま
        // 「入力が落ち着くまで引かない」debounce になる (全曲ぶんの編集距離は 20ms 前後)。
        delay(FUZZY_DEBOUNCE_MS)

        // 上限ちょうどだけ引くと、下の絞り込みを通した後に候補が空になる。多めに引いて後で切る。
        val candidateIds = module.songRepository.fuzzySongIds(
            needle = needle,
            shownIds = shown.mapTo(HashSet()) { it.song.id },
            limit = FuzzySearch.LIMIT * 3
        )
        if (candidateIds.isEmpty()) return emptyList()
        val scoped = candidateIds.toSet().let { ids -> tagFilterSongIds?.intersect(ids) ?: ids }
        if (scoped.isEmpty()) return emptyList()

        val hydrated = module.songRepository.fetchSongs(
            // 打った語で絞ると候補が全部落ちる (部分一致しないから候補になっている)。
            filter = effectiveFilter.copy(title = null),
            sortOrder = state.sortOrder,
            ascending = state.sortAscending,
            tagFilterSongIds = scoped
        )
        val allowed = applyMarkFilters(hydrated, criteria).associateBy { it.song.id }
        // 並びはコアが返した順 (部分一致 → 編集距離が小さい順) が正。一覧のソート順に戻さない。
        return candidateIds.mapNotNull { allowed[it] }.take(FuzzySearch.LIMIT)
    }

    private companion object {
        /** 入力が落ち着いたと見なすまでの待ち (iOS FuzzySearchTuning.debounce と同値)。 */
        const val FUZZY_DEBOUNCE_MS = 250L
    }
}
