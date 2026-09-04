package com.fugaif.imaslivedb.ui.songs

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.community.CommunityApi
import com.fugaif.imaslivedb.data.core.FuzzySearch
import com.fugaif.imaslivedb.data.model.AlbumSummary
import com.fugaif.imaslivedb.data.model.SeriesSummary
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

/** 曲一覧の表示形式。iOS `SongListMode` の移植。 */
enum class SongListMode {
    SONGS, ALBUMS, SERIES;

    /** 名前絞り込みが実際に絞る対象。検索欄の頭のチップに出す。 */
    val nameFilterLabel: String
        get() = when (this) {
            SONGS -> "曲名"
            ALBUMS -> "アルバム名"
            SERIES -> "シリーズ名"
        }
}

/**
 * 曲一覧の検索対象 (スコープ)。iOS `SongSearchMode` の移植 (歌詞は Worker API が要るので対象外)。
 *
 * スコープを混ぜて「すべて」で探す案は iOS と同じ理由で採らない。短い語ほど壊れるからで、
 * 「愛」で曲名を探したいのにアイドル名にも作曲者名にも「愛」は入っている。結果は常に
 * 1 スコープぶんにして、**他のスコープに何件あるかだけ知らせる** (scopeSuggestionBar)。
 */
enum class SongSearchMode {
    TITLE, PERFORMER, CREATOR;

    fun label(listMode: SongListMode): String = when (this) {
        // 曲名スコープだけは表示形式で絞る対象が変わる (曲 / アルバム / シリーズ)。
        TITLE -> listMode.nameFilterLabel
        // 「アイドル」ではなく「歌唱」。ほかの 2 つ (曲名 / 作詞作曲) が
        // **何と照合するか**を指すのに、ここだけ実体の名前だった。
        // タブ移動のチップも「アイドルに N」を出すので、同じ列に「アイドル」が
        // 2 つ並んで、別の動作が同じ語に見えてしまう。
        PERFORMER -> "歌唱"
        CREATOR -> "作詞作曲"
    }
}

data class SongListUiState(
    val isLoading: Boolean = true,
    val songs: List<SongWithArtists> = emptyList(),
    val searchText: String = "",
    /** 検索語を何に当てるか。曲名 / アイドル / 作詞作曲。 */
    val searchMode: SongSearchMode = SongSearchMode.TITLE,
    /** 表示形式 (楽曲 / アルバム / シリーズ)。 */
    val listMode: SongListMode = SongListMode.SONGS,
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
    /**
     * 直近のタグ絞り込みの取得が (オフライン等で) 失敗したか。
     *
     * 失敗時に空集合で絞ると「タグに合致する曲が 0 件」と区別が付かない。絞り込み自体を
     * 適用せず、このフラグで画面に警告を出す (iOS tagFilterError と同じ扱い)。
     */
    val tagFilterError: Boolean = false,
    /** 表示中でないスコープに何件当たるか。検索語が空のときは空。 */
    val otherScopeCounts: Map<SongSearchMode, Int> = emptyMap(),
    /** 表示形式 = アルバム / シリーズ のときのカード。 */
    val albums: List<AlbumSummary> = emptyList(),
    val series: List<SeriesSummary> = emptyList(),
    // 打った語には部分一致しないが、あいまい一致で拾えた曲 (「もしかして」)。
    // songs と混ぜない。混ぜると「打った通りの曲」がどれか分からなくなるので、
    // 画面では確実な一致の下に、見出しを挟んで別枠で出す。
    val fuzzySongs: List<SongWithArtists> = emptyList()
) {
    val activeFilterCount: Int get() = filter.activeFilterCount

    /**
     * ツールバーのフィルタバッジ件数。フィルタシートで決まる条件だけを数える。
     * タグはツールバーに専用のバッジ付きボタンがあるので、ここでは数えない (二重表示になる)。
     */
    val filterBadgeCount: Int
        get() {
            var count = activeFilterCount
            if (listMode != SongListMode.SONGS) count++
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

    /** 検索欄の頭のチップからスコープ (曲名 / アイドル / 作詞作曲) を切り替える。 */
    fun setSearchMode(mode: SongSearchMode) {
        if (_uiState.value.searchMode == mode) return
        _uiState.value = _uiState.value.copy(searchMode = mode)
        loadSongs()
    }

    fun applyFilter(
        filter: SongSearchFilter,
        sortOrder: SongSortOrder,
        sortAscending: Boolean?,
        showOtherBrand: Boolean,
        collectFilter: SongCollectFilter,
        myMarkFilter: SongMyMarkFilter,
        listMode: SongListMode
    ) {
        _uiState.value = _uiState.value.copy(
            filter = filter,
            sortOrder = sortOrder,
            sortAscending = sortAscending,
            showOtherBrand = showOtherBrand,
            collectFilter = collectFilter,
            myMarkFilter = myMarkFilter,
            listMode = listMode
        )
        loadSongs()
    }

    /**
     * アルバム/シリーズのカードを押したときの「その中身を見る」導線。
     *
     * iOS は絞り込み済みの曲一覧をシートで開くが、Android は同じ画面で表示形式を楽曲に
     * 戻して該当フィルタを載せる (戻る操作がタブの戻ると衝突しない、チップで解除できる)。
     */
    fun drillIntoAlbum(album: AlbumSummary) {
        _uiState.value = _uiState.value.copy(
            listMode = SongListMode.SONGS,
            filter = _uiState.value.filter.copy(cdSeries = album.cdSeries, seriesGroup = null)
        )
        loadSongs()
    }

    fun drillIntoSeries(series: SeriesSummary) {
        _uiState.value = _uiState.value.copy(
            listMode = SongListMode.SONGS,
            filter = _uiState.value.filter.copy(seriesGroup = series.name, cdSeries = null)
        )
        loadSongs()
    }

    fun applyTagFilter(tags: List<CommunityApi.CommunityTag>) {
        _uiState.value = _uiState.value.copy(
            selectedTags = tags,
            // タグはアルバム/シリーズ集計には掛からない。付けたのに効かない表示形式のまま
            // 残さず、曲一覧に戻してから絞る (iOS applyTagFilter と同じ)。
            listMode = if (tags.isNotEmpty()) SongListMode.SONGS else _uiState.value.listMode
        )
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

    /** 除去可能フィルタチップからの個別解除 (メモあり)。 */
    fun clearNoteFilter() {
        _uiState.value = _uiState.value.copy(myMarkFilter = _uiState.value.myMarkFilter.copy(requireNote = false))
        loadSongs()
    }

    /** 除去可能フィルタチップからの個別解除 (回収済み/未回収)。 */
    fun clearCollectFilter() {
        _uiState.value = _uiState.value.copy(collectFilter = SongCollectFilter.ALL)
        loadSongs()
    }

    /**
     * 除去可能フィルタチップからの個別解除 (フィルタシートで選んだ絞り込み)。
     * どのフィールドを外すかは呼び出し側 (画面) がチップごとに指定する。
     */
    fun clearFilterField(transform: (SongSearchFilter) -> SongSearchFilter) {
        _uiState.value = _uiState.value.copy(filter = transform(_uiState.value.filter))
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
            selectedTags = emptyList(),
            listMode = SongListMode.SONGS
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

    /**
     * 検索語を現在のスコープの絞り込み条件へ載せる。
     *
     * 一箇所に閉じておくのは、表示中スコープの取得と「ほかのスコープの件数」が
     * 必ず同じ規則で組まれるようにするため (片方だけ直すと件数と実際の結果がずれる)。
     *
     * ## 同じ軸をフィルタシートでも指定していたときは「打った語」が勝つ
     * アイドルスコープはシートの「アイドル選択」(idolIds) と、作詞作曲スコープはシートの
     * 「作詞/作曲/編曲者」と同じ軸を指す。コアも SQL も `idol_ids` を先に見る else-if なので、
     * 両方渡すと打った語が黙って無視される — 入力欄に文字が見えているのに効かない状態になる。
     * そこで打った語で上書きし、チップ側 (SongListScreen) は上書きされている間その条件を
     * 出さない (二重に見せない)。
     */
    private fun SongSearchFilter.withSearch(text: String, mode: SongSearchMode): SongSearchFilter {
        if (text.isEmpty()) return this
        return when (mode) {
            SongSearchMode.TITLE -> copy(title = text)
            SongSearchMode.PERFORMER -> copy(idolName = text, idolIds = null)
            SongSearchMode.CREATOR -> copy(songwriter = text)
        }
    }

    private fun loadSongs() {
        val ctx = appContext ?: return
        loadJob?.cancel()
        loadJob = viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true)
            val state = _uiState.value
            val module = AppModule.from(ctx)
            // アルバム / シリーズ表示は曲行を組まない (集計カードだけ)。
            // 曲側の重い取得 (マーク集合・回収数・あいまい候補) も丸ごと不要。
            if (state.listMode != SongListMode.SONGS) {
                loadCollections(module, state)
                return@launch
            }

            val baseFilter = state.filter.copy(includeOtherBrand = state.showOtherBrand)
            val effectiveFilter = baseFilter.withSearch(state.searchText, state.searchMode)

            // タグ絞り込み: Worker D1 (コミュニティタグ) は端末外データなので、選択中タグそれぞれの
            // 詳細 (付いた曲の song_id 一覧) を取得して AND (積集合) を取る。
            val tagDetails = state.selectedTags.map { tag ->
                runCatching { module.communityApi.tagDetail(tag.id) }.getOrNull()
            }
            // 1 つでも取れなければ絞り込みを **適用しない**。空集合で絞ると
            // 「オフラインで引けなかった」が「そのタグの曲は 0 件」と区別が付かない。
            val tagFilterError = state.selectedTags.isNotEmpty() && tagDetails.any { it == null }
            val tagFilterSongIds = if (state.selectedTags.isEmpty() || tagFilterError) {
                null
            } else {
                tagDetails.map { d -> d!!.songs.mapTo(mutableSetOf<String>()) { it.songId } as Set<String> }
                    .reduce { acc, s -> acc intersect s }
            }
            // 単一タグ選択時のみ、行バッジ用の票数を保持する (iOS tagVoteCounts 相当)。
            val tagVoteCounts = if (state.selectedTags.size == 1 && !tagFilterError) {
                tagDetails[0]!!.songs.associate { it.songId to it.voteCount }
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
            // メモ付き song_id。UserMarkRepository には notedIdolIds しか無い (Android に曲メモの
            // 編集導線が無かったため) ので DAO を直に引く。EventListViewModel が brandDao を
            // 直に引いているのと同じ扱い。
            val notedIds = module.database.userMarkDao().idsWithNote(UserMark.SONG).toSet()
            val pickIdolIds = marks.pickedIdolIds()
            val myPickIds = module.songRepository.fetchSongIdsWithAnyArtist(pickIdolIds)
            val collectedCounts = module.songRepository.fetchSongCollectedCounts()

            val criteria = markFilterCriteria(state, favoriteIds, notedIds, myPickIds, collectedCounts)
            songs = applyMarkFilters(songs, criteria)

            _uiState.value = _uiState.value.copy(
                isLoading = false,
                songs = songs,
                favoriteSongIds = favoriteIds,
                myPickSongIds = myPickIds,
                collectedCounts = collectedCounts,
                tagVoteCounts = tagVoteCounts,
                tagFilterError = tagFilterError,
                // 前の語の「もしかして」を残さない (打ち直した直後だけ関係ない曲が下にぶら下がる)。
                fuzzySongs = emptyList(),
                // 件数は下で数え直す。古い数字を残すと「ほかに 8 件」が別の語のままになる。
                otherScopeCounts = emptyMap()
            )

            // ここから先は表示済みの一覧に後追いで足すだけなので isLoading は倒さない。
            val scopeCounts = otherScopeCounts(module, state, baseFilter, tagFilterSongIds)
            if (scopeCounts.isNotEmpty()) {
                _uiState.value = _uiState.value.copy(otherScopeCounts = scopeCounts)
            }
            val fuzzy = fuzzyCandidates(module, state, effectiveFilter, criteria, tagFilterSongIds, songs)
            if (fuzzy.isNotEmpty()) {
                _uiState.value = _uiState.value.copy(fuzzySongs = fuzzy)
            }
        }
    }

    /**
     * アルバム / シリーズ表示のカードを読む。
     *
     * 名前絞り込みは集計側 (コアの albumSummaries / seriesSummaries) が持つので、
     * 曲一覧の検索スコープは使わず打った語をそのまま渡す。
     */
    private suspend fun loadCollections(module: AppModule, state: SongListUiState) {
        val query = state.searchText.takeIf { it.isNotBlank() }
        val brandIds = state.filter.brandIds
        val albums = if (state.listMode == SongListMode.ALBUMS) {
            module.songRepository.fetchAlbumSummaries(brandIds, query)
        } else {
            emptyList()
        }
        val series = if (state.listMode == SongListMode.SERIES) {
            module.songRepository.fetchSeriesSummaries(brandIds, query)
        } else {
            emptyList()
        }
        _uiState.value = _uiState.value.copy(
            isLoading = false,
            albums = albums,
            series = series,
            // 曲行を出さない表示形式では、曲側の付帯情報 (もしかして / スコープ件数) は意味がない。
            fuzzySongs = emptyList(),
            otherScopeCounts = emptyMap()
        )
    }

    /**
     * 表示中でないスコープに何件当たるか (iOS `otherScopeCounts` 相当)。
     *
     * 結果は常に 1 スコープぶんに保ったまま「アイドル名でも 8 件ある」と伝えるためのもの。
     * 数え方を表示中スコープと **同じ経路** (同じ filter → 同じコア) に通すのが要点で、
     * 別実装で数えると「8 件」と出したのに切り替えたら 3 件、が起きる。
     * 実体化はしない ([SongRepository.countSongs] 参照)。
     */
    private suspend fun otherScopeCounts(
        module: AppModule,
        state: SongListUiState,
        baseFilter: SongSearchFilter,
        tagFilterSongIds: Set<String>?
    ): Map<SongSearchMode, Int> {
        val needle = state.searchText
        if (needle.isBlank()) return emptyMap()
        return SongSearchMode.entries
            .filter { it != state.searchMode }
            .associateWith { scope ->
                module.songRepository.countSongs(baseFilter.withSearch(needle, scope), tagFilterSongIds)
            }
            .filterValues { it > 0 }
    }

    /**
     * マイマーク / 回収 絞り込みの条件 (iOS と同じ imas-core song_list_filtering に委譲)。
     *
     * タグ集合絞り込み・タグ票数ランキングは fetchSongs 側の tagFilterSongIds が担うので
     * ここでは未配線 (tagSongIds=null)。
     */
    private fun markFilterCriteria(
        state: SongListUiState,
        favoriteIds: Set<String>,
        notedIds: Set<String>,
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
        requireNote = state.myMarkFilter.requireNote,
        noteIds = notedIds.toList(),
        requireMyPick = state.myMarkFilter.requireMyPick,
        myPickSongIds = myPickIds.toList(),
        tagSongIds = null,
        // Android には歌詞・コール機能がまだ無いので、この絞り込みは使わない。
        // null は「絞り込まない」の意味 (空リストは「該当 0 件」で一覧が消える)。
        callGuideSongIds = null,
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
        // 曲名スコープ限定。コアへ渡す綴りは songs.title / title_kana なので、アイドル名や
        // 作家名で打っている最中に混ぜると「打った語に似た曲名の曲」が無関係に並ぶ。
        if (state.searchMode != SongSearchMode.TITLE) return emptyList()
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
