package com.fugaif.imaslivedb.data.repository

import com.fugaif.imaslivedb.data.core.SnapshotStoreProvider
import com.fugaif.imaslivedb.data.core.hydrateInOrder
import com.fugaif.imaslivedb.data.db.AppDatabase
import com.fugaif.imaslivedb.data.model.Idol
import com.fugaif.imaslivedb.data.model.SearchResults
import com.fugaif.imaslivedb.data.model.Song

/** 検索スコープ。UI 上の絞り込み単位 (iOS `UnifiedSearchScope` の移植)。 */
enum class SearchScope(val label: String, val prompt: String, val emptyNoun: String) {
    ALL("すべて", "ライブ・楽曲・アイドルを検索", "項目"),
    EVENTS("ライブ", "ライブ名 / 会場で検索", "ライブ"),
    SONGS("楽曲", "曲名で検索", "楽曲"),
    IDOLS("アイドル", "アイドル名 / CV名で検索", "アイドル");

    /** このスコープで結果セクションを表示するか。 */
    fun includes(other: SearchScope): Boolean = this == ALL || this == other
}

/**
 * 横断検索。
 *
 * 「すべて」スコープの曲検索だけ共有コア (imas-core) の globalSearch を第一経路にしている。
 * 深い曲検索・ライブ検索・アイドル検索は、対応するコア API の条件が Android の仕様や
 * スキーマと食い違うので SQL 経路のまま (各メソッドのコメント参照)。
 */
class SearchRepository(
    private val db: AppDatabase,
    // null = スナップショット経路なし (テスト等)。その場合は常に SQL 経路。
    private val snapshots: SnapshotStoreProvider? = null
) {

    /**
     * スコープに応じた検索。「すべて」は3種を各20件、スコープ指定時は該当種別のみ深く引く。
     */
    suspend fun search(query: String, scope: SearchScope = SearchScope.ALL): SearchResults {
        return when (scope) {
            SearchScope.ALL -> SearchResults(
                songs = searchSongs(query, SHALLOW_LIMIT, deep = false),
                idols = searchIdols(query, SHALLOW_LIMIT),
                events = searchEvents(query, SHALLOW_LIMIT)
            )
            SearchScope.SONGS -> SearchResults(
                songs = searchSongs(query, DEEP_LIMIT, deep = true), idols = emptyList(), events = emptyList()
            )
            SearchScope.IDOLS -> SearchResults(
                songs = emptyList(), idols = searchIdols(query, DEEP_LIMIT), events = emptyList()
            )
            SearchScope.EVENTS -> SearchResults(
                songs = emptyList(), idols = emptyList(), events = searchEvents(query, DEEP_LIMIT)
            )
        }
    }

    /**
     * アイドル検索。**SQL 経路のまま残す。**
     *
     * コアの searchIdols は CV 名を idol_voice_actors テーブル経由でしか見ないが、
     * Android のスキーマに idol_voice_actors は無く、CV 名は idols.voice_actors
     * (カンマ区切りの1列) が持っている。コアへ寄せると「CV 名でアイドルを引く」という
     * このアプリの主要な探し方がヒットゼロになるため、Android に idol_voice_actors を
     * 載せる (= 同期対象に加える) までは SQL が正。
     * 名前/かな/ローマ字/別名・sort_order 順・limit の条件は両者一致している。
     */
    private suspend fun searchIdols(query: String, limit: Int): List<Idol> {
        return db.searchDao().searchIdols("%$query%", limit)
    }

    private suspend fun searchSongs(query: String, limit: Int, deep: Boolean): List<Song> {
        if (!deep) {
            // コアの globalSearch は曲について title/title_kana の部分一致・上限 20 件で、
            // Android の「すべて」スコープと同条件。上限が固定なので、200 件まで引く
            // 深いスコープ (楽曲タブ) には使えず、そちらは SQL のまま。
            snapshots?.query { store -> store.globalSearch(query).songIds }
                ?.let { return hydrateInOrder(it, Song::id) { ids -> db.songDao().fetchSongsByIds(ids) } }
        }
        return db.searchDao().searchSongs("%$query%", limit)
    }

    /**
     * ライブ検索は会場名 (shows.venue) 一致も含むのが Android の仕様。コアの globalSearch は
     * イベント名しか見ず、会場で探す動線が消えるため SQL 経路のまま
     * (会場一致は venuesMatching が別 API で、事前に event_id 集合を要求するので置換にならない)。
     */
    private suspend fun searchEvents(query: String, limit: Int) =
        db.searchDao().searchEvents("%$query%", limit)

    private companion object {
        const val SHALLOW_LIMIT = 20
        const val DEEP_LIMIT = 200
    }
}
