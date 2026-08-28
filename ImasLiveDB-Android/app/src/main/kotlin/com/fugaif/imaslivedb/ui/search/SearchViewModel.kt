package com.fugaif.imaslivedb.ui.search

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.fugaif.imaslivedb.data.model.SearchResults
import com.fugaif.imaslivedb.data.model.Song
import com.fugaif.imaslivedb.data.repository.SearchScope
import com.fugaif.imaslivedb.di.AppModule
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SearchUiState(
    val query: String = "",
    /**
     * いま画面に出ている結果を引いた語。ハイライトはこれで敷く。
     *
     * 打鍵中の [query] で敷くと、まだ引いていない語で古い結果に色が付く (1 打鍵ぶん先の語で
     * 色が消えたり動いたりする)。「なぜこの行が出ているか」を示す印なので、行を出した語と
     * 必ず同じにする。
     */
    val matchedQuery: String = "",
    val scope: SearchScope = SearchScope.ALL,
    val results: SearchResults = SearchResults(emptyList(), emptyList(), emptyList()),
    val history: List<String> = emptyList(),
    val isSearching: Boolean = false
) {
    /**
     * 現在スコープで表示される結果の件数。
     *
     * あいまい候補も数に入れる。ここが 0 だと画面は「見つかりません」を出すので、
     * 数えないと「もしかして」しか無いとき (打ち間違い・かな入力) に候補ごと隠れる。
     */
    val visibleResultCount: Int
        get() = (if (scope.includes(SearchScope.IDOLS)) results.idols.size else 0) +
            (if (scope.includes(SearchScope.SONGS)) results.songs.size + results.fuzzySongs.size else 0) +
            (if (scope.includes(SearchScope.EVENTS)) results.events.size else 0)
}

class SearchViewModel(app: Application) : AndroidViewModel(app) {

    private val repo = AppModule.from(app).searchRepository
    private val historyStore = SearchHistoryStore(app)

    private val _uiState = MutableStateFlow(SearchUiState())
    val uiState: StateFlow<SearchUiState> = _uiState.asStateFlow()

    private var searchJob: Job? = null

    init {
        refreshHistory()
    }

    /** 呼び出し元タブのスコープで開く。 */
    fun setInitialScope(scope: SearchScope) {
        if (_uiState.value.scope == scope) return
        _uiState.value = _uiState.value.copy(scope = scope)
        refreshHistory()
    }

    fun setScope(scope: SearchScope) {
        _uiState.value = _uiState.value.copy(scope = scope)
        refreshHistory()
        // スコープを変えたら結果を取り直す (ALL は各20件、スコープ指定時はより深く引くため)。
        val query = _uiState.value.query
        if (query.isNotBlank()) scheduleSearch(query, debounce = false)
    }

    fun setQuery(query: String) {
        _uiState.value = _uiState.value.copy(query = query)
        if (query.isBlank()) {
            searchJob?.cancel()
            _uiState.value = _uiState.value.copy(
                results = SearchResults(emptyList(), emptyList(), emptyList()),
                matchedQuery = "",
                isSearching = false
            )
            return
        }
        scheduleSearch(query, debounce = true)
    }

    /** 確定 (キーボードの検索 / 履歴タップ)。ヒットしたスコープにだけ履歴を残す。 */
    fun commit(query: String = _uiState.value.query) {
        val trimmed = query.trim()
        if (trimmed.isEmpty()) return
        _uiState.value = _uiState.value.copy(query = trimmed)
        historyStore.record(trimmed, matchedScopes())
        refreshHistory()
        scheduleSearch(trimmed, debounce = false)
    }

    fun removeHistory(item: String) {
        historyStore.remove(item, _uiState.value.scope)
        refreshHistory()
    }

    fun clearHistory() {
        historyStore.clear(_uiState.value.scope)
        refreshHistory()
    }

    private fun matchedScopes(): List<SearchScope> {
        val state = _uiState.value
        if (state.scope != SearchScope.ALL) return listOf(state.scope)
        val matched = buildList {
            if (state.results.idols.isNotEmpty()) add(SearchScope.IDOLS)
            if (state.results.songs.isNotEmpty()) add(SearchScope.SONGS)
            if (state.results.events.isNotEmpty()) add(SearchScope.EVENTS)
        }
        return matched.ifEmpty { listOf(SearchScope.SONGS) }
    }

    private fun refreshHistory() {
        _uiState.value = _uiState.value.copy(history = historyStore.history(_uiState.value.scope))
    }

    private fun scheduleSearch(query: String, debounce: Boolean) {
        searchJob?.cancel()
        val scope = _uiState.value.scope
        searchJob = viewModelScope.launch {
            if (debounce) delay(DEBOUNCE_MS)
            _uiState.value = _uiState.value.copy(isSearching = true)
            val results = repo.search(query, scope)

            // 確実な一致は候補を待たせずに出す。あいまい一致は全曲の綴りを突き合わせるので、
            // 同じ待ちに乗せると打った通りの結果まで丸ごと遅れて出ることになる。
            //
            // 例外は確実な一致が 0 件のとき。ここで出すと「見つかりません」が一瞬映った
            // 直後に「もしかして」が生えて画面が入れ替わるので、そのときだけ候補を待つ。
            val exact = _uiState.value.copy(results = results, matchedQuery = query, isSearching = false)
            if (exact.visibleResultCount > 0) _uiState.value = exact

            val fuzzy: List<Song> = try {
                repo.fuzzySongs(query, results.songs, scope)
            } catch (e: CancellationException) {
                // 打ち直しでの取り消し。握ると古い回が新しい検索の結果を踏む。
                throw e
            } catch (e: Exception) {
                // 「もしかして」は補助機能。失敗しても確実な一致まで巻き添えにしない。
                Log.w(TAG, "fuzzy_search_failed", e)
                emptyList()
            }
            ensureActive()
            _uiState.value = _uiState.value.copy(
                results = results.copy(fuzzySongs = fuzzy),
                matchedQuery = query,
                isSearching = false
            )
        }
    }

    private companion object {
        const val DEBOUNCE_MS = 200L
        const val TAG = "SearchViewModel"
    }
}
