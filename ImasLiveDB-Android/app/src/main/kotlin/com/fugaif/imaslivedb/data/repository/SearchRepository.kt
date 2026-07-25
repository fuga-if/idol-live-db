package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.SearchResults

/** 検索スコープ。UI 上の絞り込み単位 (iOS `UnifiedSearchScope` の移植)。 */
enum class SearchScope(val label: String, val prompt: String, val emptyNoun: String) {
    ALL("すべて", "ライブ・楽曲・アイドルを検索", "項目"),
    EVENTS("ライブ", "ライブ名 / 会場で検索", "ライブ"),
    SONGS("楽曲", "曲名で検索", "楽曲"),
    IDOLS("アイドル", "アイドル名 / CV名で検索", "アイドル");

    /** このスコープで結果セクションを表示するか。 */
    fun includes(other: SearchScope): Boolean = this == ALL || this == other
}

class SearchRepository(private val db: AppDatabase) {

    /**
     * スコープに応じた検索。「すべて」は3種を各20件、スコープ指定時は該当種別のみ深く引く。
     */
    suspend fun search(query: String, scope: SearchScope = SearchScope.ALL): SearchResults {
        val pattern = "%$query%"
        val dao = db.searchDao()
        return when (scope) {
            SearchScope.ALL -> SearchResults(
                songs = dao.searchSongs(pattern),
                idols = dao.searchIdols(pattern),
                events = dao.searchEvents(pattern)
            )
            SearchScope.SONGS -> SearchResults(
                songs = dao.searchSongs(pattern, DEEP_LIMIT), idols = emptyList(), events = emptyList()
            )
            SearchScope.IDOLS -> SearchResults(
                songs = emptyList(), idols = dao.searchIdols(pattern, DEEP_LIMIT), events = emptyList()
            )
            SearchScope.EVENTS -> SearchResults(
                songs = emptyList(), idols = emptyList(), events = dao.searchEvents(pattern, DEEP_LIMIT)
            )
        }
    }

    private companion object {
        const val DEEP_LIMIT = 200
    }
}
